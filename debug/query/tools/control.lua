-- multi-manager-debug :: tools/control.lua
-- Mutating tools: console commands, game speed, save, reload, broadcast and the
-- host-side shell spool file.

local util = require('debug.query.util')
local log_buffer = require('debug.query.log_buffer')

local M = {}

local SPOOL_DIR = 'multi-manager-debug'
local SHELL_REQUEST = SPOOL_DIR .. '/shell-request.json'
local SHELL_RESULT = SPOOL_DIR .. '/shell-result.json'
local pending_shell = nil

local DANGEROUS = {
  ['/quit'] = true, ['/server-save'] = true, ['/save'] = true, ['/delete'] = true,
  ['/ban'] = true, ['/unban'] = true, ['/promote'] = true, ['/demote'] = true,
  ['/kick'] = true, ['/reset-tips'] = true,
}
M.DANGEROUS = DANGEROUS

local function run_console_command(command)
  local raw = tostring(command or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if raw == '' then return false, 'command is required' end
  if raw:sub(1, 1) ~= '/' then raw = '/' .. raw end

  -- Split into "/name arg1 arg2 ..." preserving quoted Lua payloads.
  local name, rest = raw:match('^(%S+)%s*(.*)$')
  if name == nil then return false, 'could not parse command' end

  -- Only mod-registered commands are visible to Lua, and the registry uses the
  -- slash-prefixed name. The external runs built-in commands over RCON instead.
  local entry = util.try(function() return commands[name] end, nil)
  if entry == nil then
    entry = util.try(function() return commands[name:gsub('^/', '')] end, nil)
  end
  if entry == nil then
    return false, 'command "' .. name .. '" is not in the mod command registry (built-in commands run through the external console)'
  end

  local ok, err = pcall(function()
    entry.handler({ player_index = nil, parameter = rest, tick = game.tick })
  end)
  if not ok then return false, tostring(err) end
  return true, nil
end

--- execute_command -----------------------------------------------------------
function M.execute_command(args)
  args = args or {}
  local command = args.command
  if command == nil or command == '' then return { ok = false, error = 'command is required' } end
  local normalised = tostring(command)
  if normalised:sub(1, 1) ~= '/' then normalised = '/' .. normalised end

  if DANGEROUS[normalised:match('^(%S+)')] and not args.confirmationToken then
    return {
      ok = false,
      needs_confirmation = true,
      error = 'this command is destructive, repeat it with confirmationToken set to a non-empty string',
      command = normalised,
    }
  end

  local ok, err = run_console_command(normalised)
  if ok then
    log_buffer.push('COMMAND', 'console command executed: ' .. normalised, { player = args.player or 'server', command = normalised })
  end
  return { ok = ok, command = normalised, executed = ok, error = err }
end

--- get_console_command_list --------------------------------------------------
--- Factorio's built-in console commands are NOT reachable from Lua:
--- LuaCommandProcessor only holds the commands mods registered with
--- commands.add_command(), and it is not iterable. The external therefore runs
--- built-in commands as real console commands over RCON and only falls back to
--- this registry. Here we report exactly what this side does know.
function M.get_console_command_list(args)
  local wanted = (args and args.commands) or {
    'debug-health', 'debug-tools', 'debug-rpc',
  }
  local out = {}
  for _, name in ipairs(wanted) do
    local entry = util.try(function() return commands['/' .. name:gsub('^/', '')] end, nil)
    if entry == nil then
      entry = util.try(function() return commands[name:gsub('^/', '')] end, nil)
    end
    out[#out + 1] = {
      command = '/' .. name:gsub('^/', ''),
      registeredByMod = entry ~= nil,
      parameter = entry and util.try(function() return entry.parameter end, nil) or nil,
      dangerous = DANGEROUS['/' .. name:gsub('^/', '')] == true,
    }
  end
  return {
    count = #out,
    commands = out,
    modRegistered = true,
    builtinCommandsEnumerable = false,
    builtinHint = 'built-in commands are executed by the external as genuine console commands over RCON; this list covers only the mod registry',
  }
end

--- set_game_speed ------------------------------------------------------------
function M.set_game_speed(args)
  args = args or {}
  local speed = tonumber(args.speed)
  if speed == nil then return { ok = false, error = 'speed (number) is required' } end
  if speed < 0.01 or speed > 1000 then
    return { ok = false, error = 'speed must be between 0.01 and 1000' }
  end
  local previous = util.try(function() return game.speed end, 1)
  local ok, err = pcall(function() game.speed = speed end)
  return { ok = ok, previousSpeed = previous, speed = util.try(function() return game.speed end, nil), error = (not ok) and tostring(err) or nil }
end

--- set_tick_paused -----------------------------------------------------------
function M.set_tick_paused(args)
  args = args or {}
  if type(args.paused) ~= 'boolean' then return { ok = false, error = 'paused (boolean) is required' } end
  local previous = util.try(function() return game.tick_paused end, false)
  local ok, err = pcall(function() game.tick_paused = args.paused end)
  return { ok = ok, previous = previous, paused = util.try(function() return game.tick_paused end, nil), error = (not ok) and tostring(err) or nil }
end

--- save_game -----------------------------------------------------------------
--- Factorio exposes a real save API, so this does not need the console command
--- (which is built into the engine and unreachable from Lua anyway).
function M.save_game(args)
  local previous = util.try(function() return game.auto_save_enabled end, nil)
  local ok, err = pcall(function() game.server_save() end)
  return {
    ok = ok,
    requested = ok,
    via = 'game.server_save()',
    previousAutoSaveEnabled = previous,
    error = (not ok) and tostring(err) or nil,
    note = 'Factorio writes the save asynchronously; watch the server log for "Saving finished"',
    elapsedTick = game.tick,
  }
end

--- reload_scripts ------------------------------------------------------------
function M.reload_scripts()
  local ok, err = pcall(function() script.reload_script() end)
  return {
    ok = ok,
    error = (not ok) and tostring(err) or nil,
    note = 'reloading re-runs control.lua from the top; in-memory behaviour history is reset',
  }
end

--- broadcast_message ---------------------------------------------------------
function M.broadcast_message(args)
  args = args or {}
  local message = args.message
  if message == nil or message == '' then return { ok = false, error = 'message is required' } end
  local colour = args.color
  local ok, err = pcall(function()
    if colour and colour.r then
      game.print(tostring(message), { color = { r = colour.r, g = colour.g, b = colour.b, a = colour.a or 1 } })
    else
      game.print(tostring(message))
    end
  end)
  if ok then
    log_buffer.push('GENERAL', 'server broadcast: ' .. tostring(message), { player = 'server' })
  end
  return { ok = ok, message = tostring(message), error = (not ok) and tostring(err) or nil }
end

--- execute_shell -------------------------------------------------------------
-- The Lua sandbox cannot spawn processes. The request is written to a spool file
-- inside script-output and the bundled external picks it up on its next poll,
-- runs it on the host and answers through the RPC layer.
function M.execute_shell(args)
  args = args or {}
  if args.command == nil or args.command == '' then
    return { ok = false, error = 'command is required' }
  end
  local cfg = _G.__DEBUG_CONFIG
  if cfg and cfg.external.shellEnabled ~= true then
    return {
      ok = false,
      error = 'shell execution is disabled in the config (external.shellEnabled = false)',
      hint = 'set external.shellEnabled to true in the external config, or call the rcon_passthrough tool',
    }
  end
  return {
    ok = false,
    supported = false,
    error = 'execute_shell must be served by the external: the Factorio Lua sandbox has no process API',
    externalHint = 'the external answers this tool directly (shellEnabled) without a round trip to the game',
    command = tostring(args.command),
    workingDir = args.workingDir,
    timeoutMs = args.timeoutMs,
  }
end

return M
