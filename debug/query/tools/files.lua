-- multi-manager-debug :: tools/files.lua
-- File tools scoped to the game's write-data directory.
--
-- IMPORTANT: the Factorio Lua sandbox only exposes helpers.write_file(); there
-- is no read/delete/rename primitive. Reads are therefore served from an
-- in-memory buffer of everything this session wrote, and from the append-only
-- session files. The tools keep the debug server contract (read/write/append/
-- delete/list) but report explicitly when an operation cannot be honoured
-- instead of silently pretending it worked.

local util = require('debug.query.util')
local json = require('debug.query.json')

local M = {}

local ROOT = 'script-output'
local SESSION = {}         -- path -> { content = string, bytes = n, appends = n }
local SESSION_ORDER = {}
local MAX_BUFFER = 512 * 1024
local MAX_PAGE = 200 * 1024

local function normalize(path)
  if type(path) ~= 'string' or path == '' then return nil, 'filePath is required' end
  local p = path:gsub('\\', '/'):gsub('^%./', '')
  if p:find('%.%.') then return nil, 'path traversal is not allowed' end
  if p:sub(1, 1) == '/' then return nil, 'absolute paths are not allowed' end
  return p
end

local function remember(path, content, appended)
  local entry = SESSION[path]
  if entry == nil then
    entry = { content = '', bytes = 0, appends = 0 }
    SESSION[path] = entry
    SESSION_ORDER[#SESSION_ORDER + 1] = path
  end
  if appended then
    entry.content = entry.content .. content
    entry.appends = entry.appends + 1
  else
    entry.content = content
  end
  entry.bytes = #entry.content
  if #entry.content > MAX_BUFFER then
    entry.content = entry.content:sub(-MAX_BUFFER)
    entry.truncated = true
  end
  return entry
end

--- get_file_editor_status ----------------------------------------------------
function M.get_file_editor_status()
  local root = false
  local enabled = false
  if _G.__DEBUG_CONFIG then
    enabled = _G.__DEBUG_CONFIG.fileEditor.enabled == true
    root = _G.__DEBUG_CONFIG.fileEditor.root
  end
  return {
    enabled = enabled,
    root = root or ROOT,
    capabilities = {
      read = 'buffered (sandbox has no read primitive)',
      write = true,
      append = true,
      delete = false,
      list = false,
    },
    sessionFiles = #SESSION_ORDER,
    sessionBytes = (function()
      local n = 0
      for _, e in pairs(SESSION) do n = n + e.bytes end
      return n
    end)(),
    note = 'file_delete, file_list and reading files written by an earlier session are not supported by the Factorio Lua API; use the external shell tool for host-side file work',
  }
end

--- file_read -----------------------------------------------------------------
function M.file_read(args)
  args = args or {}
  local path, err = normalize(args.filePath)
  if path == nil then return { error = err } end
  local entry = SESSION[path]
  if entry == nil then
    return {
      error = 'file is not in the session buffer',
      filePath = path,
      hint = 'the Factorio Lua sandbox has no file-read primitive; only files written during this session can be read back',
    }
  end
  local offset = util.clamp(tonumber(args.offset) or 1, 1, math.max(1, entry.bytes))
  local limit = util.clamp(tonumber(args.limit) or MAX_PAGE, 1, MAX_PAGE)
  local content = entry.content:sub(offset, offset + limit - 1)
  return {
    filePath = path,
    bytes = entry.bytes,
    offset = offset,
    returnedBytes = #content,
    truncated = (offset + #content - 1) < entry.bytes,
    bufferedContentTruncated = entry.truncated or false,
    content = content,
  }
end

--- file_write ----------------------------------------------------------------
function M.file_write(args)
  args = args or {}
  local path, err = normalize(args.filePath)
  if path == nil then return { error = err } end
  local content = args.content
  if type(content) ~= 'string' then return { error = 'content (string) is required' } end
  local target = ROOT .. '/' .. path
  local ok, werr = pcall(function()
    helpers.write_file(target, content, false)
  end)
  remember(path, content, false)
  return {
    ok = ok,
    filePath = path,
    writtenPath = target,
    bytes = #content,
    error = (not ok) and tostring(werr) or nil,
  }
end

--- file_append ---------------------------------------------------------------
function M.file_append(args)
  args = args or {}
  local path, err = normalize(args.filePath)
  if path == nil then return { error = err } end
  local content = args.content
  if type(content) ~= 'string' then return { error = 'content (string) is required' } end
  local target = ROOT .. '/' .. path
  local ok, werr = pcall(function()
    helpers.write_file(target, content, true)
  end)
  local entry = remember(path, content, true)
  return {
    ok = ok,
    filePath = path,
    writtenPath = target,
    appendedBytes = #content,
    sessionTotalBytes = entry.bytes,
    error = (not ok) and tostring(werr) or nil,
  }
end

--- file_delete ---------------------------------------------------------------
function M.file_delete(args)
  args = args or {}
  local path, err = normalize(args.filePath)
  if path == nil then return { error = err } end
  SESSION[path] = nil
  local order = {}
  for _, p in ipairs(SESSION_ORDER) do if p ~= path then order[#order + 1] = p end end
  SESSION_ORDER = order
  return {
    ok = false,
    filePath = path,
    bufferEntryRemoved = true,
    supported = false,
    error = 'the Factorio Lua API cannot delete files; remove script-output files from the host instead',
  }
end

--- file_list -----------------------------------------------------------------
function M.file_list(args)
  args = args or {}
  local prefix = (args and args.directory) or ''
  local list = {}
  for _, p in ipairs(SESSION_ORDER) do
    if prefix == '' or p:sub(1, #prefix) == prefix then
      list[#list + 1] = { filePath = p, bytes = SESSION[p].bytes, appends = SESSION[p].appends }
    end
  end
  return {
    directory = prefix,
    count = #list,
    files = list,
    supported = 'session-only',
    error = 'directory listing is not available inside the Factorio Lua sandbox; this lists files written during this session',
  }
end

return M
