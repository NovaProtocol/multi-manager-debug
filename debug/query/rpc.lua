-- multi-manager-debug :: rpc.lua
-- Single entry point used by the external. The external runs
--   /silent-command rcon.print(remote.call("multi-manager-debug","rpc","<tool>","<json>"))
-- and always receives one compact JSON line back.

local json = require('debug.query.json')
local util = require('debug.query.util')
local clock = require('debug.query.clock')
local monitoring = require('debug.query.tools.monitoring')

local TOOLS = {}

local function register(module, names)
  local mod = require('debug.query.tools.' .. module)
  for _, name in ipairs(names) do
    if type(mod[name]) ~= 'function' then
      error('tool ' .. name .. ' is missing from debug/query/tools/' .. module .. '.lua')
    end
    TOOLS[name] = mod[name]
  end
end

register('monitoring', {
  'get_server_status',
  'get_performance_metrics',
  'get_memory_metrics',
  'get_entity_metrics',
  'get_recent_logs',
  'get_player_events',
  'get_chat_messages',
  'get_command_history',
})

register('players', {
  'get_player_info',
  'get_force_info',
  'get_surface_info',
  'get_research_status',
  'get_production_stats',
})

register('world', {
  'get_logistic_network_status',
  'get_item_stats',
  'get_inventory',
  'get_chest_contents',
  'get_factory_overview',
})

register('behavior', {
  'behavior_recorder_status',
  'behavior_track_player',
  'behavior_untrack_player',
  'behavior_clear_history',
  'behavior_get_latest',
  'behavior_query_history',
})

register('files', {
  'get_file_editor_status',
  'file_read',
  'file_write',
  'file_append',
  'file_delete',
  'file_list',
})

register('control', {
  'execute_command',
  'get_console_command_list',
  'set_game_speed',
  'set_tick_paused',
  'save_game',
  'broadcast_message',
  'execute_shell',
})

local rpc = {}

rpc.TOOLS = TOOLS
rpc.COUNT = 0
for _ in pairs(TOOLS) do rpc.COUNT = rpc.COUNT + 1 end

function rpc.tool_names()
  local names = {}
  for name in pairs(TOOLS) do names[#names + 1] = name end
  table.sort(names)
  return names
end

--- Parse the argument payload the external sent. Lenient: an empty/invalid
--- payload becomes an empty table rather than an error.
local function parse_args(args_json)
  if args_json == nil or args_json == '' or args_json == 'null' then return {} end
  if type(args_json) == 'table' then return args_json end
  local parsed = json.decode(tostring(args_json))
  if type(parsed) ~= 'table' then return {} end
  return parsed
end

--- Execute one tool. Returns a JSON string (never throws).
--- @param tool string tool name
--- @param args_json string|nil JSON object with the tool arguments
--- @param externalTs number|nil unix seconds from the external, used for time sync
function rpc.call(tool, args_json, externalTs)
  local started = game.tick
  if externalTs ~= nil then clock.sync(externalTs, game.tick) end

  local name = tostring(tool or '')
  local fn = TOOLS[name]
  if fn == nil then
    return json.encode({
      ok = false,
      error = 'unknown tool: ' .. name,
      availableTools = rpc.tool_names(),
    })
  end

  local args = parse_args(args_json)
  local ok, result = pcall(fn, args)
  local elapsed_ticks = game.tick - started

  monitoring.record_rpc(elapsed_ticks)

  if not ok then
    return json.encode({
      ok = false,
      tool = name,
      error = tostring(result),
      tick = game.tick,
    })
  end

  if type(result) == 'table' and result.error ~= nil then
    result.ok = false
    result.tool = name
    result.tick = result.tick or game.tick
    return json.encode(result)
  end

  return json.encode({
    ok = true,
    tool = name,
    tick = game.tick,
    wall = clock.now(),
    clockSynced = clock.is_synced(),
    data = result,
  })
end

--- Compact metadata used by the external's health/selftest paths.
function rpc.info()
  return json.encode({
    ok = true,
    mod = 'multi-manager-debug',
    modVersion = '0.1.0',
    factorioVersion = util.try(function() return script.active_mods['base'] end, 'unknown'),
    tools = rpc.COUNT,
    toolNames = rpc.tool_names(),
    tick = game.tick,
    clock = clock.status(),
    surfaces = (function()
      local out = {}
      local i = 1
      while true do
        local s = game.surfaces[i]
        if s == nil then break end
        out[#out + 1] = s.name
        i = i + 1
      end
      return out
    end)(),
  })
end

return rpc
