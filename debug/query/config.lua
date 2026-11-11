-- multi-manager-debug :: config.lua
-- Configuration lives in script-output/multi-manager-debug/config.json so the
-- bundled external can read and rewrite the very same file. Parsing is lenient:
-- a corrupted or truncated file never takes the game down, it just falls back
-- to defaults (mirrors the "lenient JSON parsing" behaviour of debug server).

local json = require('debug.query.json')

local config = {}

local CONFIG_DIR = 'multi-manager-debug'
local CONFIG_FILE = 'config.json'

local DEFAULTS = {
  enabled = true,
  external = {
    host = '127.0.0.1',
    port = 8081,
    ssl = {
      enabled = false,
      keystorePath = 'config/multi-manager-debug/keystore.p12',
      keystorePassword = 'factorio-debug',
      keystoreType = 'PKCS12',
      certPath = 'config/multi-manager-debug/fullchain.pem',
      keyPath = 'config/multi-manager-debug/privkey.key',
    },
    tokenMode = 'auto',
    persistentToken = nil,
    shellEnabled = false,
    shellTimeoutMs = 30000,
    corsOrigin = '*',
  },
  rcon = {
    host = '127.0.0.1',
    port = 25575,
    password = '',
  },
  fileEditor = {
    enabled = false,
    root = 'script-output',
  },
  logBuffer = {
    max = 2000,
    captureChat = true,
    captureCommands = true,
  },
  behavior = {
    enabled = true,
    trackAllPlayers = true,
    highFreqIntervalMs = 250,
    lowFreqIntervalMs = 1000,
    maxHistoryPerPlayer = 2000,
    flushIntervalTicks = 30,
    logFileName = 'behave.jsonl',
    maxRecordsOnDisk = 0,
  },
}

config.DEFAULTS = DEFAULTS
config.CONFIG_FILE = CONFIG_FILE

local function is_table(v)
  return type(v) == 'table'
end

local function num(raw, default, min, max)
  local n = tonumber(raw)
  if n == nil then return default end
  if min and n < min then return default end
  if max and n > max then return default end
  return n
end

local function bool(raw, default)
  if type(raw) == 'boolean' then return raw end
  if type(raw) == 'string' then
    local low = raw:lower()
    if low == 'true' then return true end
    if low == 'false' then return false end
  end
  return default
end

local function str(raw, default)
  if type(raw) == 'string' and raw ~= '' then return raw end
  return default
end

local function table_path()
  return CONFIG_DIR .. '/' .. CONFIG_FILE
end
config.path = table_path

--- Read + leniently merge the on-disk config with the defaults.
function config.load()
  local merged = json.decode(json.encode(DEFAULTS)) -- deep copy through the encoder
  local raw_text = nil
  local ok = pcall(function()
    if helpers.file_exists(table_path()) then
      raw_text = helpers.read_file(table_path())
    end
  end)
  if not ok or not raw_text or raw_text == '' then
    return merged, false, 'config file not readable, using defaults'
  end

  local on_disk = json.decode(raw_text)
  if not is_table(on_disk) then
    return merged, false, 'config file is not a JSON object, using defaults'
  end

  merged.enabled = bool(on_disk.enabled, DEFAULTS.enabled)

  local b = on_disk.external
  if is_table(b) then
    merged.external.host = str(b.host, DEFAULTS.external.host)
    merged.external.port = num(b.port, DEFAULTS.external.port, 1, 65535)
    merged.external.tokenMode = (b.tokenMode == 'persistent') and 'persistent' or 'auto'
    if type(b.persistentToken) == 'string' and b.persistentToken ~= '' then
      merged.external.persistentToken = b.persistentToken
    end
    merged.external.shellEnabled = bool(b.shellEnabled, DEFAULTS.external.shellEnabled)
    merged.external.shellTimeoutMs = num(b.shellTimeoutMs, DEFAULTS.external.shellTimeoutMs, 1000, 3600000)
    merged.external.corsOrigin = str(b.corsOrigin, DEFAULTS.external.corsOrigin)
    local s = b.ssl
    if is_table(s) then
      merged.external.ssl.enabled = bool(s.enabled, false)
      merged.external.ssl.keystorePath = str(s.keystorePath, DEFAULTS.external.ssl.keystorePath)
      merged.external.ssl.keystorePassword = str(s.keystorePassword, DEFAULTS.external.ssl.keystorePassword)
      merged.external.ssl.keystoreType = str(s.keystoreType, DEFAULTS.external.ssl.keystoreType)
      merged.external.ssl.certPath = str(s.certPath, DEFAULTS.external.ssl.certPath)
      merged.external.ssl.keyPath = str(s.keyPath, DEFAULTS.external.ssl.keyPath)
    end
  end

  local r = on_disk.rcon
  if is_table(r) then
    merged.rcon.host = str(r.host, DEFAULTS.rcon.host)
    merged.rcon.port = num(r.port, DEFAULTS.rcon.port, 1, 65535)
    merged.rcon.password = str(r.password, DEFAULTS.rcon.password)
  end

  local f = on_disk.fileEditor
  if is_table(f) then
    merged.fileEditor.enabled = bool(f.enabled, DEFAULTS.fileEditor.enabled)
    merged.fileEditor.root = str(f.root, DEFAULTS.fileEditor.root)
  end

  local lb = on_disk.logBuffer
  if is_table(lb) then
    merged.logBuffer.max = num(lb.max, DEFAULTS.logBuffer.max, 50, 100000)
    merged.logBuffer.captureChat = bool(lb.captureChat, DEFAULTS.logBuffer.captureChat)
    merged.logBuffer.captureCommands = bool(lb.captureCommands, DEFAULTS.logBuffer.captureCommands)
  end

  local bh = on_disk.behavior
  if is_table(bh) then
    merged.behavior.enabled = bool(bh.enabled, DEFAULTS.behavior.enabled)
    merged.behavior.trackAllPlayers = bool(bh.trackAllPlayers, DEFAULTS.behavior.trackAllPlayers)
    merged.behavior.highFreqIntervalMs = num(bh.highFreqIntervalMs, DEFAULTS.behavior.highFreqIntervalMs, 50, 60000)
    merged.behavior.lowFreqIntervalMs = num(bh.lowFreqIntervalMs, DEFAULTS.behavior.lowFreqIntervalMs, 50, 600000)
    merged.behavior.maxHistoryPerPlayer = num(bh.maxHistoryPerPlayer, DEFAULTS.behavior.maxHistoryPerPlayer, 10, 200000)
    merged.behavior.flushIntervalTicks = num(bh.flushIntervalTicks, DEFAULTS.behavior.flushIntervalTicks, 1, 3600)
    merged.behavior.logFileName = str(bh.logFileName, DEFAULTS.behavior.logFileName)
    merged.behavior.maxRecordsOnDisk = num(bh.maxRecordsOnDisk, DEFAULTS.behavior.maxRecordsOnDisk, 0, 100000000)
  end

  return merged, true, nil
end

--- Persist a config table (pretty printed for humans).
function config.save(cfg)
  local ok, err = pcall(function()
    helpers.write_file(table_path(), json.encode(cfg), false)
  end)
  return ok, err
end

function config.write_defaults_if_missing(cfg)
  local exists = false
  pcall(function() exists = helpers.file_exists(table_path()) end)
  if not exists then
    return config.save(cfg or DEFAULTS)
  end
  return false, 'exists'
end

return config
