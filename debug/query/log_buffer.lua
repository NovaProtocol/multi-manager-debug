-- multi-manager-debug :: log_buffer.lua
-- In-memory ring buffer fed by Factorio game events (chat, console commands,
-- build/mine/research/death, plus everything the mod itself logs). The external
-- reads it through the RPC interface, the mod mirrors it to
-- script-output/multi-manager-debug/events.jsonl so an offline external can also
-- tail the stream.

local util = require('debug.query.util')
local json = require('debug.query.json')
local clock = require('debug.query.clock')

local log_buffer = {}

local FILTERS = {
  GENERAL = true,
  PLAYER_JOIN = true,
  PLAYER_LEAVE = true,
  CHAT = true,
  COMMAND = true,
  ERROR = true,
  WARN = true,
  BUILD = true,
  MINE = true,
  RESEARCH = true,
  DEATH = true,
  COMBAT = true,
  TRAIN = true,
  ROBOT = true,
}

log_buffer.FILTERS = FILTERS

local state = {
  entries = {},
  max = 2000,
  head = 0,
  total = 0,
  dropped = 0,
  captureChat = true,
  captureCommands = true,
  mirrorEnabled = true,
  mirrorFile = 'multi-manager-debug/events.jsonl',
  mirrorBuffer = {},
  lastMirrorFlush = 0,
  mirrorFlushTicks = 120,
  mirrorEvery = 1,
  seq = 0,
}

function log_buffer.configure(cfg)
  state.max = cfg.logBuffer.max
  state.captureChat = cfg.logBuffer.captureChat
  state.captureCommands = cfg.logBuffer.captureCommands
  state.mirrorFlushTicks = math.max(1, cfg.logBuffer.flushIntervalTicks or 120)
  if state.max < 50 then state.max = 50 end
  -- trim if the buffer shrank
  while #state.entries > state.max do
    table.remove(state.entries, 1)
  end
end

--- Push one entry. `extra` holds optional structured fields.
function log_buffer.push(kind, message, extra)
  if kind ~= nil and FILTERS[kind] == nil then kind = 'GENERAL' end
  state.seq = state.seq + 1
  local entry = {
    seq = state.seq,
    tick = game.tick,
    ts = clock.now(),
    type = kind or 'GENERAL',
    message = tostring(message or ''),
  }
  if extra then
    for k, v in pairs(extra) do entry[k] = v end
  end
  state.entries[#state.entries + 1] = entry
  state.total = state.total + 1
  while #state.entries > state.max do
    table.remove(state.entries, 1)
    state.dropped = state.dropped + 1
  end
  if state.mirrorEnabled then
    state.mirrorBuffer[#state.mirrorBuffer + 1] = json.encode(entry)
  end
  return entry
end

--- Flush the mirror buffer into events.jsonl (called from on_tick).
function log_buffer.flush_mirror(force)
  if not state.mirrorEnabled then return 0 end
  if #state.mirrorBuffer == 0 then return 0 end
  if not force and (game.tick - state.lastMirrorFlush) < state.mirrorFlushTicks then return 0 end
  state.lastMirrorFlush = game.tick
  local payload = table.concat(state.mirrorBuffer, '\n') .. '\n'
  state.mirrorBuffer = {}
  local ok, err = pcall(function()
    helpers.write_file(state.mirrorFile, payload, true)
  end)
  if not ok then
    state.mirrorEnabled = false -- never spam the game thread with failing IO
    log('[multi-manager-debug] event mirror disabled: ' .. tostring(err))
    return 0
  end
  return #payload
end

--- Query the ring buffer.
--- @param limit number max entries
--- @param filterType string|nil one of FILTERS or nil/"ALL"
--- @param playerName string|nil only entries whose `player` matches
function log_buffer.query(limit, filterType, playerName)
  limit = util.clamp(tonumber(limit) or 100, 1, state.max)
  local want = filterType and string.upper(tostring(filterType)) or nil
  if want == 'ALL' or want == '' then want = nil end
  local wantPlayer = playerName and string.lower(tostring(playerName)) or nil
  local out = {}
  for i = #state.entries, 1, -1 do
    local e = state.entries[i]
    local match = true
    if want and e.type ~= want then match = false end
    if match and wantPlayer then
      local p = e.player and string.lower(tostring(e.player)) or nil
      if p ~= wantPlayer then match = false end
    end
    if match then
      out[#out + 1] = e
      if #out >= limit then break end
    end
  end
  -- reverse into chronological order
  local ordered = {}
  for i = #out, 1, -1 do ordered[#ordered + 1] = out[i] end
  return ordered
end

function log_buffer.stats()
  return {
    buffered = #state.entries,
    capacity = state.max,
    totalRecorded = state.total,
    dropped = state.dropped,
    mirrorEnabled = state.mirrorEnabled,
    mirrorPending = #state.mirrorBuffer,
    mirrorFile = state.mirrorFile,
    filters = (function()
      local f = {}
      for k in pairs(FILTERS) do f[#f + 1] = k end
      table.sort(f)
      return f
    end)(),
  }
end

function log_buffer.clear()
  state.entries = {}
  state.mirrorBuffer = {}
  return true
end

return log_buffer
