-- multi-manager-debug :: tools/behavior.lua
-- Player behaviour recording tools (history query, CSV export, tracking).

local util = require('debug.query.util')
local recorder = require('debug.query.behavior_recorder')

local M = {}

local MAX_ROWS = 300

function M.behavior_recorder_status()
  return recorder.status()
end

function M.behavior_track_player(args)
  local name = args and args.playerName
  if name == nil or name == '' then name = '*' end
  recorder.track(name)
  local st = recorder.status()
  return {
    ok = true,
    playerName = name,
    trackAllPlayers = st.trackAllPlayers,
    trackedPlayers = st.trackedPlayers,
    message = name == '*' and 'tracking all players' or ('now tracking ' .. name),
  }
end

function M.behavior_untrack_player(args)
  local name = args and args.playerName
  if name == nil or name == '' then
    return { ok = false, error = "playerName is required (use '!all' to stop tracking everyone)" }
  end
  recorder.untrack(name)
  local st = recorder.status()
  return {
    ok = true,
    playerName = name,
    trackAllPlayers = st.trackAllPlayers,
    trackedPlayers = st.trackedPlayers,
  }
end

function M.behavior_clear_history(args)
  local name = args and args.playerName
  local cleared = recorder.clear(name)
  return { ok = true, playerName = name or '!all', clearedPlayers = cleared }
end

function M.behavior_get_latest(args)
  local name = args and args.playerName
  if name == nil or name == '' then
    return { ok = false, error = 'playerName is required' }
  end
  local record = recorder.latest(name)
  if record == nil then
    return { ok = false, playerName = name, error = 'no samples recorded for that player' }
  end
  return record
end

function M.behavior_query_history(args)
  args = args or {}
  local playerName = args.playerName
  local fromTs = tonumber(args.fromTs)
  local toTs = tonumber(args.toTs)
  local limit = util.clamp(tonumber(args.limit) or 100, 1, MAX_ROWS)
  local format = (args.format == 'csv') and 'csv' or 'json'

  local records, truncated_unused = recorder.query(playerName, fromTs, toTs, limit)
  local truncated = #records >= limit

  -- the RCON transport caps a single response, so keep the payload bounded
  while #records > MAX_ROWS do table.remove(records, 1) end
  if #records == MAX_ROWS then truncated = true end

  if format == 'csv' then
    local csv = recorder.to_csv(records, true)
    while #csv > 600000 and #records > 1 do
      table.remove(records, 1)
      csv = recorder.to_csv(records, true)
      truncated = true
    end
    return {
      format = 'csv',
      playerName = playerName or '*',
      fromTs = fromTs,
      toTs = toTs,
      returned = #records,
      truncated = truncated,
      csv = csv,
      columns = recorder.COLUMNS,
    }
  end

  return {
    format = 'json',
    playerName = playerName or '*',
    fromTs = fromTs,
    toTs = toTs,
    returned = #records,
    truncated = truncated,
    records = records,
    columns = recorder.COLUMNS,
  }
end

return M
