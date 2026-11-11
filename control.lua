-- multi-manager-debug
-- One operator command: /debug
--
-- The game half exposes a single RCON command with two namespaces:
--   /debug probe <op> [json]   world, entity and agent operations
--   /debug query <tool> [json] monitoring, players, files and control tools
-- and a small set of lifecycle commands: help, tools, ping.
--
-- Everything is local to the game process. There is no listener and no host external.

local json = require("debug.query.json")
local query = require("debug.query.rpc")
local config = require("debug.query.config")
local log_buffer = require("debug.query.log_buffer")
local recorder = require("debug.query.behavior_recorder")
local agent = require("debug.agent.agent")
local world = require("debug.agent.world")
local blueprints = require("debug.agent.blueprints")

local MOD = "multi-manager-debug"
local STORAGE_KEY = "multi_manager_debug"

local function state()
    storage[STORAGE_KEY] = storage[STORAGE_KEY] or {cache = {}, cache_order = {}}
    return storage[STORAGE_KEY]
end

local groups = {
    agent.operations or {},
    world.operations or {},
    blueprints.operations or {},
}

local operations = {}
for _, group in ipairs(groups) do
    for name, handler in pairs(group) do
        operations[name] = handler
    end
end

operations.ping = function(s)
    s.heartbeat = game.tick
    return {
        ok = true,
        tick = game.tick,
        players = #game.connected_players,
        operations = operations.help(),
    }
end

operations.help = function()
    local names = {}
    for name in pairs(operations) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

local function decode_params(text)
    if text == nil or text == "" then
        return {}
    end
    local value = json.decode(text)
    if type(value) ~= "table" then
        error("arguments must be a JSON object")
    end
    return value
end

local function reply(event, payload)
    local text = type(payload) == "string" and payload or json.encode(payload)
    if event and event.player_index then
        local player = game.get_player(event.player_index)
        if player then
            player.print(text)
            return
        end
    end
    if rcon then
        rcon.print(text)
    else
        log("[" .. MOD .. "] " .. text)
    end
end

local function run_probe(operation, parameters)
    local handler = operations[operation]
    if handler == nil then
        error("unknown operation: " .. tostring(operation))
    end
    return handler(state(), parameters or {})
end

local function run_query(tool, parameters)
    local raw = query.call(tool, json.encode(parameters or {}))
    local decoded = json.decode(raw)
    if type(decoded) ~= "table" then
        error("query returned an unreadable result")
    end
    return decoded
end

local function dispatch(event, text)
    local first, rest = tostring(text or ""):match("^(%S*)%s*(.*)$")
    first = first or ""

    if first == "" or first == "help" then
        local names = operations.help()
        local tools = query.tool_names()
        reply(event, {
            ok = true,
            usage = "/debug probe <operation> [json] | /debug query <tool> [json] | /debug help | /debug ping",
            operations = names,
            tools = tools,
        })
        return
    end

    if first == "ping" then
        reply(event, operations.ping(state()))
        return
    end

    if first == "tools" then
        reply(event, {ok = true, operations = operations.help(), tools = query.tool_names()})
        return
    end

    local namespace, remainder = rest:match("^(%S+)%s*(.*)$")
    if first ~= "probe" and first ~= "query" then
        -- Accept the common shorthand `/debug <operation>` for probe operations.
        namespace, remainder = first, rest
        first = "probe"
    end
    if namespace == nil or namespace == "" then
        error("usage: /debug probe <operation> [json] | /debug query <tool> [json]")
    end

    local parameters = decode_params(remainder)
    if first == "query" then
        reply(event, run_query(namespace, parameters))
    else
        reply(event, run_probe(namespace, parameters))
    end
end

commands.add_command(
    "debug",
    "Operator debug channel. /debug help for operations and tools.",
    function(event)
        if event.player_index then
            return
        end
        local ok, result = pcall(dispatch, event, event.parameter)
        if not ok then
            reply(event, {ok = false, error = tostring(result)})
        end
    end
)

remote.add_interface(MOD, {
    invoke = function(namespace, operation, parameters)
        if namespace == "query" then
            return json.encode(run_query(operation, parameters or {}))
        end
        return json.encode(run_probe(operation, parameters or {}))
    end,
    help = function()
        return json.encode({operations = operations.help(), tools = query.tool_names()})
    end,
})

local function configure()
    local cfg = config.load()
    _G.__DEBUG_CONFIG = cfg
    log_buffer.configure(cfg)
    recorder.configure(cfg)
end

script.on_init(function()
    state()
    configure()
    pcall(agent.initialize, state())
end)

script.on_configuration_changed(function()
    configure()
    pcall(agent.initialize, state())
end)

local function player_name(index)
    local player = game.get_player(index)
    return player and player.name or ("#" .. tostring(index))
end

local event_handlers = {
    { "on_player_joined_game", function(event)
        local name = player_name(event.player_index)
        log_buffer.push("PLAYER_JOIN", name .. " joined the game", {player = name})
        pcall(recorder.on_player_joined, game.get_player(event.player_index))
    end },
    { "on_player_left_game", function(event)
        local name = player_name(event.player_index)
        log_buffer.push("PLAYER_LEAVE", name .. " left the game", {player = name})
        pcall(recorder.on_player_left, game.get_player(event.player_index))
    end },
    { "on_console_chat", function(event)
        if not _G.__DEBUG_CONFIG or not _G.__DEBUG_CONFIG.logBuffer.captureChat then return end
        local name = event.player_index and player_name(event.player_index) or "server"
        log_buffer.push("CHAT", name .. ": " .. tostring(event.message), {player = name, chat = tostring(event.message)})
    end },
    { "on_console_command", function(event)
        if not _G.__DEBUG_CONFIG or not _G.__DEBUG_CONFIG.logBuffer.captureCommands then return end
        local name = event.player_index and player_name(event.player_index) or "server"
        log_buffer.push("COMMAND", name .. " ran /" .. tostring(event.command or "") .. " " .. tostring(event.parameters or ""),
            {player = name, command = tostring(event.command or "")})
    end },
    { "on_player_died", function(event)
        local name = player_name(event.player_index)
        local cause = event.cause and event.cause.name or "unknown"
        log_buffer.push("DEATH", name .. " died (cause: " .. cause .. ")", {player = name, cause = cause})
    end },
    { "on_research_finished", function(event)
        local name = event.research and event.research.name or "unknown"
        log_buffer.push("RESEARCH", "research finished: " .. name, {entity = name})
    end },
    { "on_research_started", function(event)
        local name = event.research and event.research.name or "unknown"
        log_buffer.push("RESEARCH", "research started: " .. name, {entity = name})
    end },
}

for _, entry in ipairs(event_handlers) do
    local event_id = defines.events[entry[1]]
    if event_id ~= nil then
        pcall(function() script.on_event(event_id, entry[2]) end)
    end
end

script.on_event(defines.events.on_tick, function()
    local s = state()
    if not s.spawned then
        pcall(agent.initialize, s)
    end
    if s.spawned then
        pcall(agent.tick, s)
    end
    local cfg = _G.__DEBUG_CONFIG
    if cfg and cfg.behavior.enabled then
        pcall(recorder.update)
    end
    if game.tick % 120 == 0 then
        pcall(log_buffer.flush_mirror)
    end
    if game.tick % 300 == 0 then
        pcall(recorder.flush, true)
    end
end)

script.on_event(defines.events.on_script_path_request_finished, function(event)
    pcall(agent.path_finished, state(), event)
end)
