-- multi-manager-debug :: tools/monitoring.lua
-- Server health, performance and log/event introspection tools.

local util = require('debug.query.util')
local log_buffer = require('debug.query.log_buffer')
local recorder = require('debug.query.behavior_recorder')

local M = {}

local function force_names()
  local out = {}
  local i = 1
  while true do
    local f = game.forces[i]
    if f == nil then break end
    out[#out + 1] = f.name
    i = i + 1
  end
  return out
end

--- shared perf state, updated by rpc.lua on every call
local state_perf = {
  samples = {},
  last_ms = 0,
  entity_total = 0,
  entity_by_surface = {},
  chunk_total = 0,
  chunk_by_surface = {},
}
M._perf = state_perf

local function surface_names()
  local out = {}
  local i = 1
  while true do
    local s = game.surfaces[i]
    if s == nil then break end
    out[#out + 1] = s.name
    i = i + 1
  end
  return out
end

local function player_count()
  local connected = util.try(function() return #game.connected_players end, 0)
  local total = util.try(function() return #game.players end, 0)
  return connected, total
end

local function online_players()
  local out = {}
  local n = util.try(function() return #game.connected_players end, 0)
  for i = 1, n do
    local p = game.connected_players[i]
    local name = util.try(function() return p.name end, nil)
    if name then
      local char = util.try(function() return p.character end, nil)
      out[#out + 1] = {
        name = name,
        index = util.try(function() return p.index end, nil),
        admin = util.try(function() return p.admin end, false),
        position = util.position(util.try(function() return p.position end, nil)),
        surface = util.try(function() return p.physical_surface and p.physical_surface.name or nil end, nil),
        health = util.round(util.try(function() return char and char.health end, 0) or 0, 2),
        maxHealth = util.round(util.try(function() return char and char.max_health end, 0) or 0, 2),
        onlineTime = util.try(function() return p.online_time end, 0),
        afkTime = util.try(function() return p.afk_time end, 0) or 0,
      }
    end
  end
  return out
end

--- get_server_status ---------------------------------------------------------
function M.get_server_status(args)
  local connected, total = player_count()
  local out = {
    tick = game.tick,
    tickPaused = util.try(function() return game.tick_paused end, false),
    gameSpeed = util.try(function() return game.speed end, 1),
    connectedPlayers = connected,
    totalPlayers = total,
    maxPlayers = util.try(function() return game.max_players end, nil),
    players = online_players(),
    surfaces = surface_names(),
    forces = force_names(),
    factorioVersion = util.try(function() return script.active_mods['base'] end, 'unknown'),
    activeMods = (function()
      local c = 0
      for _ in pairs(script.active_mods) do c = c + 1 end
      return c
    end)(),
    mapName = util.try(function() return game.save_name end, nil),
    uptimeTicks = game.tick,
    uptimeSeconds = util.round(game.tick / 60, 2),
    evolution = (function()
      local i = 1
      while true do
        local f = game.forces[i]
        if f == nil then break end
        if f.name == 'enemy' then
          return { nauvis = util.round(util.try(function() return f.get_evolution_factor(game.surfaces[1]) end, 0), 6) }
        end
        i = i + 1
      end
      return {}
    end)(),
    difficulty = {
      technologyPriceMultiplier = util.try(function() return game.difficulty_settings.technology_price_multiplier end, nil),
      researchQueueSetting = util.try(function() return game.map_settings.research_queue_setting end, nil),
      pollutionEnabled = util.try(function() return game.map_settings.pollution.enabled end, nil),
      evolutionEnabled = util.try(function() return game.map_settings.enemy_evolution.enabled end, nil),
    },
    logStats = log_buffer.stats(),
  }
  return out
end

--- get_performance_metrics ---------------------------------------------------
function M.get_performance_metrics()
  local samples = state_perf.samples
  local avg = 0
  if #samples > 0 then
    local sum = 0
    for _, v in ipairs(samples) do sum = sum + v end
    avg = sum / #samples
  end
  local last = samples[#samples] or 0
  local worst = 0
  for _, v in ipairs(samples) do if v > worst then worst = v end end
  return {
    tick = game.tick,
    gameSpeed = util.try(function() return game.speed end, 1),
    tickPaused = util.try(function() return game.tick_paused end, false),
    measuredRpc = {
      samples = #samples,
      lastMs = util.round(last, 4),
      averageMs = util.round(avg, 4),
      worstMs = util.round(worst, 4),
      note = 'wall-clock cost of recent debug RPC round trips, measured inside the game thread',
    },
    entities = state_perf.entity_total,
    entitiesBySurface = state_perf.entity_by_surface,
    ups = {
      target = 60,
      estimate = util.round(util.clamp(1000 / math.max(avg, 0.0001), 0, 60), 2),
      note = 'estimate derived from RPC wall-clock cost, not the game UPS counter',
    },
    chart = (function()
      local c = {}
      for i = math.max(1, #samples - 29), #samples do c[#c + 1] = util.round(samples[i], 4) end
      return c
    end)(),
  }
end

--- get_memory_metrics --------------------------------------------------------
function M.get_memory_metrics()
  return {
    tick = game.tick,
    lua = {
      note = 'the Lua sandbox exposes no collector statistics; these are RPC-side measurements',
      rpcWallClockMs = util.round(state_perf.last_ms, 4),
      trackedPlayers = util.try(function() return #game.connected_players end, 0),
    },
    registry = {
      itemPrototypes = count_prototypes('item'),
      entityPrototypes = count_prototypes('entity'),
      fluidPrototypes = count_prototypes('fluid'),
      recipePrototypes = count_prototypes('recipe'),
      technologyPrototypes = count_prototypes('technology'),
    },
    entities = state_perf.entity_total,
    chunks = (function()
      M.refresh_chunk_stats(96)
      return state_perf.chunk_total
    end)(),
    chunksBySurface = (function()
      return state_perf.chunk_by_surface
    end)(),
    chunkNote = 'generated-chunk census (bounded walk, exact for maps up to 193x193 chunks)',
    logBufferEntries = log_buffer.stats().buffered,
    behaviorQueuePending = recorder.status().pendingWrites,
    host = {
      note = 'process/host memory is served by the external as /api/memory',
      source = 'external',
    },
  }
end

function count_prototypes(kind)
  local set = util.try(function() return prototypes[kind] end, nil)
  if set == nil then return nil end
  local n = 0
  for _ in pairs(set) do n = n + 1 end
  return n
end

--- get_entity_metrics --------------------------------------------------------
function M.get_entity_metrics(args)
  local surface_filter = args and args.surface or nil
  local top = util.clamp(tonumber(args and args.top) or 20, 1, 200)
  local force_filter = args and args.force or nil
  local counts = {}
  local by_force = {}
  local total = 0
  local surfaces = {}

  local i = 1
  while true do
    local surface = game.surfaces[i]
    if surface == nil then break end
    local sname = surface.name
    if surface_filter == nil or surface_filter == sname then
      surfaces[#surfaces + 1] = sname
      local entities = surface.find_entities_filtered({ force = force_filter })
      local n = #entities
      total = total + n
      for j = 1, n do
        local e = entities[j]
        local etype = util.try(function() return e.type end, 'unknown')
        counts[etype] = (counts[etype] or 0) + 1
        local fname = util.try(function() return e.force and e.force.name or 'neutral' end, 'neutral')
        by_force[fname] = (by_force[fname] or 0) + 1
      end
    end
    i = i + 1
  end

  local ranked = {}
  for k, v in pairs(counts) do ranked[#ranked + 1] = { type = k, count = v } end
  table.sort(ranked, function(a, b) return a.count > b.count end)
  local trimmed = {}
  for k = 1, math.min(#ranked, top) do trimmed[k] = ranked[k] end

  return {
    tick = game.tick,
    surfaces = surfaces,
    totalEntities = total,
    distinctTypes = #ranked,
    topTypes = trimmed,
    byForce = by_force,
    pollution = (function()
      local p = {}
      for _, sname in ipairs(surfaces) do
        local s = game.surfaces[sname]
        p[sname] = util.round(util.try(function() return s.get_pollution({ 0, 0 }) end, 0) or 0, 4)
      end
      return p
    end)(),
    trains = (function()
      local out = {}
      for _, sname in ipairs(surfaces) do
        local s = game.surfaces[sname]
        local c = 0
        util.try(function()
          local ok = pcall(function()
            for _ in pairs(s.get_trains()) do c = c + 1 end
          end)
        end)
        out[sname] = c
      end
      return out
    end)(),
  }
end

--- log / event tools ---------------------------------------------------------

function M.get_recent_logs(args)
  args = args or {}
  local entries = log_buffer.query(args.limit or 100, args.filterType, args.player)
  return { count = #entries, entries = entries, buffer = log_buffer.stats() }
end

function M.get_player_events(args)
  args = args or {}
  local limit = util.clamp(tonumber(args.limit) or 100, 1, 2000)
  local wanted = {
    PLAYER_JOIN = true, PLAYER_LEAVE = true, DEATH = true, COMBAT = true,
  }
  local all = log_buffer.query(log_buffer.stats().capacity, nil, nil)
  local out = {}
  for i = #all, 1, -1 do
    local e = all[i]
    if wanted[e.type] and (not args.player or (e.player and string.lower(e.player) == string.lower(args.player))) then
      out[#out + 1] = e
      if #out >= limit then break end
    end
  end
  local ordered = {}
  for i = #out, 1, -1 do ordered[#ordered + 1] = out[i] end
  return { count = #ordered, events = ordered }
end

function M.get_chat_messages(args)
  args = args or {}
  local entries = log_buffer.query(args.limit or 100, 'CHAT', args.player)
  return { count = #entries, messages = entries }
end

function M.get_command_history(args)
  args = args or {}
  local entries = log_buffer.query(args.limit or 100, 'COMMAND', args.player)
  return { count = #entries, commands = entries }
end

--- shared perf state, updated by rpc.lua on every call -----------------------
function M.record_rpc(ms)
  state_perf.last_ms = ms
  state_perf.samples[#state_perf.samples + 1] = ms
  while #state_perf.samples > 120 do table.remove(state_perf.samples, 1) end
end

--- Refresh cached world statistics (called from on_tick every N ticks).
function M.refresh_world_stats()
  local total = 0
  local by_surface = {}
  local i = 1
  while true do
    local s = game.surfaces[i]
    if s == nil then break end
    local n = util.try(function() return s.count_entities_filtered({}) end, nil)
    if n == nil then
      n = util.try(function() return #s.find_entities_filtered({ limit = 100000 }) end, 0)
    end
    by_surface[s.name] = n
    total = total + (n or 0)
    i = i + 1
  end
  state_perf.entity_total = total
  state_perf.entity_by_surface = by_surface
end

--- Generated-chunk census. On demand only: walking the chunk grid is far too
--- expensive to run from on_tick.
function M.refresh_chunk_stats(limit)
  local total = 0
  local by_surface = {}
  local i = 1
  while true do
    local s = game.surfaces[i]
    if s == nil then break end
    local c = util.generated_chunk_count(s, limit)
    by_surface[s.name] = c
    total = total + c
    i = i + 1
  end
  state_perf.chunk_total = total
  state_perf.chunk_by_surface = by_surface
  return by_surface
end

return M
