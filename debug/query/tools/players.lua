-- multi-manager-debug :: tools/players.lua
-- Read-only introspection of players, forces, surfaces, research and stats.

local util = require('debug.query.util')

local M = {}

local function resolve_player(args)
  args = args or {}
  local name = args.playerName
  if name == nil or name == '' then return nil, 'playerName is required' end
  local p = util.try(function() return game.get_player(tostring(name)) end, nil)
  if p == nil and tonumber(name) then
    p = util.try(function() return game.get_player(tonumber(name)) end, nil)
  end
  if p == nil then return nil, 'no player named ' .. tostring(name) end
  return p, nil
end

--- LuaForce.technologies is a string-keyed dictionary (not iterable by index),
--- so the prototype list drives the census.
local function technology_census(force)
  local researched, available, locked, total = 0, 0, 0, 0
  util.try(function()
    for name in pairs(prototypes.technology) do
      local tech = force.technologies[name]
      if tech ~= nil then
        total = total + 1
        if tech.researched then
          researched = researched + 1
        elseif tech.enabled then
          available = available + 1
        else
          locked = locked + 1
        end
      end
    end
  end)
  return { researched = researched, available = available, locked = locked, total = total }
end

local function inventory_summary(player)  local out = {}
  local kinds = {
    { 'main', defines.inventory.character_main },
    { 'armor', defines.inventory.character_armor },
    { 'guns', defines.inventory.character_guns },
    { 'ammo', defines.inventory.character_ammo },
    { 'trash', defines.inventory.character_trash },
    { 'logistic', defines.inventory.character_logistic_slot },
  }
  for _, entry in ipairs(kinds) do
    local list = util.try(function()
      local inv = player.get_inventory(entry[2])
      if inv == nil then return nil end
      local items = {}
      local n = #inv
      for i = 1, n do
        local stack = inv[i]
        if stack and util.try(function() return stack.valid_for_read end, false) then
          items[#items + 1] = {
            itemId = util.try(function() return stack.name end, 'unknown'),
            slot = i,
            count = util.try(function() return stack.count end, 0),
            quality = util.try(function() return stack.quality and stack.quality.name or nil end, nil),
          }
        end
      end
      return items
    end, nil)
    if list then out[entry[1]] = list end
  end
  return out
end

--- get_player_info -----------------------------------------------------------
function M.get_player_info(args)
  args = args or {}
  if args.playerName == nil or args.playerName == '' then
    local list = {}
    local n = util.try(function() return #game.players end, 0)
    for i = 1, n do
      local p = game.players[i]
      list[#list + 1] = {
        name = util.try(function() return p.name end, nil),
        index = util.try(function() return p.index end, nil),
        connected = util.try(function() return p.connected end, false),
        admin = util.try(function() return p.admin end, false),
        position = util.position(util.try(function() return p.position end, nil)),
        force = util.try(function() return p.force and p.force.name or nil end, nil),
        onlineTime = util.try(function() return p.online_time end, 0),
        lastOnline = util.try(function() return p.last_online end, nil),
      }
    end
    return { count = #list, players = list }
  end

  local player, err = resolve_player(args)
  if player == nil then return { error = err } end
  local character = util.try(function() return player.character end, nil)
  return {
    name = util.try(function() return player.name end, nil),
    index = util.try(function() return player.index end, nil),
    connected = util.try(function() return player.connected end, false),
    admin = util.try(function() return player.admin end, false),
    force = util.try(function() return player.force and player.force.name or nil end, nil),
    surface = util.try(function() return player.physical_surface and player.physical_surface.name or nil end, nil),
    position = util.position(util.try(function() return player.position end, nil)),
    health = util.round(util.try(function() return character and character.health end, 0) or 0, 2),
    maxHealth = util.round(util.try(function() return character and character.max_health end, 0) or 0, 2),
    craftingQueueLength = util.try(function() return #player.crafting_queue end, 0),
    onlineTimeTicks = util.try(function() return player.online_time end, 0),
    afkTimeTicks = util.try(function() return player.afk_time end, 0),
    colour = (function()
      local c = util.try(function() return player.color end, nil)
      if c == nil then return nil end
      local r = util.try(function() return c.r end, nil)
      local g = util.try(function() return c.g end, nil)
      local b = util.try(function() return c.b end, nil)
      local a = util.try(function() return c.a end, nil)
      if r == nil then return nil end
      return { r = util.round(r, 3), g = util.round(g, 3), b = util.round(b, 3), a = util.round(a or 1, 3) }
    end)(),
    inventory = inventory_summary(player),
    permissions = (function()
      local perms = {}
      local list = util.try(function() return player.permission_group and player.permission_group.name end, nil)
      if list then perms.group = list end
      return perms
    end)(),
  }
end

--- get_force_info ------------------------------------------------------------
function M.get_force_info(args)
  args = args or {}
  local name = args.force
  if name == nil or name == '' then
    local list = {}
    local i = 1
    while true do
      local f = game.forces[i]
      if f == nil then break end
      list[#list + 1] = f.name
      i = i + 1
    end
    return { forces = list }
  end
  local force = util.try(function() return game.forces[tostring(name)] end, nil)
  if force == nil then return { error = 'no force named ' .. tostring(name) } end

  local research = {}
  local current = util.try(function() return force.current_research end, nil)
  if current then
    research.inProgress = {
      name = util.try(function() return current.name end, nil),
      progress = util.round(util.try(function() return force.research_progress end, 0) or 0, 4),
    }
  end
  local queue = {}
  util.try(function()
    for _, t in ipairs(force.research_queue or {}) do
      queue[#queue + 1] = { name = t.name, level = t.level }
    end
  end)
  research.queue = queue
  research.technologiesResearched = technology_census(force).researched

  local charted = {}
  util.try(function()
    local i = 1
    while true do
      local s = game.surfaces[i]
      if s == nil then break end
      charted[s.name] = util.try(function() return force.is_chunk_charted(s, { 0, 0 }) end, nil)
      i = i + 1
    end
  end)

  return {
    name = util.try(function() return force.name end, name),
    players = util.try(function() return #force.players end, 0),
    evolutionFactor = util.round(util.try(function() return force.get_evolution_factor(game.surfaces[1]) end, 0), 6),
    evolutionBySurface = (function()
      local out = {}
      local i = 1
      while true do
        local s = game.surfaces[i]
        if s == nil then break end
        out[s.name] = util.round(util.try(function() return force.get_evolution_factor(s) end, 0), 6)
        i = i + 1
      end
      return out
    end)(),
    research = research,
    charted = charted,
    manualMiningSpeed = util.try(function() return force.manual_mining_speed_modifier end, nil),
    manualCraftingSpeed = util.try(function() return force.manual_crafting_speed_modifier end, nil),
    characterLogisticSlots = util.try(function() return force.character_logistic_slot_count end, nil),
    characterTrashSlots = util.try(function() return force.character_trash_slot_count end, nil),
    workerRobots = {
      construction = util.try(function() return force.construction_robot_speed_modifier end, nil),
      mining = util.try(function() return force.mining_drill_productivity_bonus end, nil),
    },
  }
end

--- get_surface_info ----------------------------------------------------------
function M.get_surface_info(args)
  args = args or {}
  local out = {}
  local i = 1
  while true do
    local s = game.surfaces[i]
    if s == nil then break end
    if args.surface == nil or args.surface == '' or args.surface == s.name then
      out[#out + 1] = {
        name = s.name,
        index = util.try(function() return s.index end, nil),
        peaceful = util.try(function() return s.peaceful_mode end, nil),
        alwaysDay = util.try(function() return s.always_day end, nil),
        brightness = util.round(util.try(function() return s.daytime end, 0) or 0, 4),
        pollution = util.round(util.try(function() return s.get_pollution({ 0, 0 }) end, 0) or 0, 4),
        pollutionEnabled = util.try(function() return game.map_settings.pollution.enabled end, nil),
        generatedChunks = util.generated_chunk_count(s),
        chartedChunks = util.charted_chunk_count(s, nil, 48),
        entities = util.try(function() return s.count_entities_filtered({}) end, nil),
        mapGenSeed = util.try(function() return s.map_gen_settings and s.map_gen_settings.seed end, nil),
        tiles = util.try(function() return s.map_gen_settings and s.map_gen_settings.width end, nil),
        spawnPosition = util.position(util.try(function() return s.get_spawn_position and s.get_spawn_position(game.forces.player) end, nil)),
        trains = (function()
          local c = 0
          pcall(function() for _ in pairs(s.get_trains()) do c = c + 1 end end)
          return c
        end)(),
      }
    end
    i = i + 1
  end
  return { count = #out, surfaces = out }
end

--- get_research_status -------------------------------------------------------
function M.get_research_status(args)
  args = args or {}
  local force_name = (args and args.force) or 'player'
  local force = util.try(function() return game.forces[tostring(force_name)] end, nil)
  if force == nil then return { error = 'no force named ' .. tostring(force_name) } end

  local researched, available, locked = 0, 0, 0
  local queue = {}
  util.try(function()
    for _, t in ipairs(force.research_queue or {}) do queue[#queue + 1] = { name = t.name, level = t.level } end
  end)
  local census = technology_census(force)
  researched, available, locked = census.researched, census.available, census.locked

  local current = util.try(function() return force.current_research end, nil)
  return {
    force = util.try(function() return force.name end, force_name),
    currentResearch = current and {
      name = util.try(function() return current.name end, nil),
      researchUnitCount = util.try(function() return current.research_unit_count end, nil),
      progress = util.round(util.try(function() return force.research_progress end, 0) or 0, 4),
      ingredients = (function()
        local ing = {}
        util.try(function()
          for _, e in ipairs(current.research_unit_ingredients or {}) do
            ing[#ing + 1] = { name = e.name, amount = e.amount }
          end
        end)
        return ing
      end)(),
    } or nil,
    queue = queue,
    researched = researched,
    available = available,
    locked = locked,
    total = researched + available + locked,
  }
end

--- get_production_stats ------------------------------------------------------
function M.get_production_stats(args)
  args = args or {}
  local force_name = (args and args.force) or 'player'
  local surface_name = (args and args.surface) or 'nauvis'
  local force = util.try(function() return game.forces[tostring(force_name)] end, nil)
  if force == nil then return { error = 'no force named ' .. tostring(force_name) } end
  local surface = util.try(function() return game.surfaces[tostring(surface_name)] end, nil)
  if surface == nil then return { error = 'no surface named ' .. tostring(surface_name) } end

  local top = util.clamp(tonumber(args.top) or 30, 1, 200)
  local kind = args.kind or 'item'

  local stats = util.try(function() return force.get_item_production_statistics(surface) end, nil)
  if stats == nil then
    stats = util.try(function() return force.get_item_production_statistics() end, nil)
  end
  if stats == nil then
    return { error = 'production statistics are not available on this Factorio version' }
  end

  local function collect(field)
    local rows = {}
    util.try(function()
      local dict = stats[field]
      if dict == nil then return end
      local n = 0
      for name in pairs(dict) do
        rows[#rows + 1] = { name = name, count = tonumber(dict[name]) or 0 }
        n = n + 1
        if n > 4000 then break end
      end
    end)
    table.sort(rows, function(a, b) return a.count > b.count end)
    local trimmed = {}
    for i = 1, math.min(#rows, top) do trimmed[i] = rows[i] end
    return trimmed, #rows
  end

  local input, input_total = collect('input_counts')
  local output, output_total = collect('output_counts')

  return {
    force = force_name,
    surface = surface_name,
    kind = kind,
    inputCounts = input,
    outputCounts = output,
    distinctInputs = input_total,
    distinctOutputs = output_total,
    note = 'lifetime totals since world creation',
  }
end

return M
