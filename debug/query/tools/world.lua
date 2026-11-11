-- multi-manager-debug :: tools/world.lua
-- Item / logistics / production oriented tools.

local util = require('debug.query.util')
local players_tools = require('debug.query.tools.players')

local M = {}

local function surface_of(args)
  args = args or {}
  local name = args.surface or 'nauvis'
  local s = util.try(function() return game.surfaces[tostring(name)] end, nil)
  if s == nil then
    s = util.try(function() return game.surfaces[1] end, nil)
  end
  return s, name
end

local function force_of(args)
  args = args or {}
  local name = args.force or 'player'
  local f = util.try(function() return game.forces[tostring(name)] end, nil)
  if f == nil then f = util.try(function() return game.forces.player end, nil) end
  return f, name
end

--- get_logistic_network_status ----------------------------------------------
function M.get_logistic_network_status(args)
  args = args or {}
  local surface, sname = surface_of(args)
  if surface == nil then return { error = 'no surface available' } end
  local force, fname = force_of(args)

  local center = util.try(function()
    return { x = tonumber(args.x) or 0, y = tonumber(args.y) or 0 }
  end, { x = 0, y = 0 })

  local networks = util.try(function()
    return surface.find_logistic_networks_by_construction_area(center, force)
  end, nil)

  local out = {}
  local total_robots, total_available, total_logistic_robots, total_construction_robots = 0, 0, 0, 0
  if networks then
    local n = util.try(function() return #networks end, 0)
    for i = 1, n do
      local net = networks[i]
      local robots = util.try(function() return net.all_robots end, {})
      local avail = util.try(function() return net.available_robots end, {})
      local lr = util.try(function() return net.logistic_robots end, {})
      local cr = util.try(function() return net.construction_robots end, {})
      local nr = util.try(function() return #robots end, 0)
      total_robots = total_robots + nr
      total_available = total_available + util.try(function() return #avail end, 0)
      total_logistic_robots = total_logistic_robots + util.try(function() return #lr end, 0)
      total_construction_robots = total_construction_robots + util.try(function() return #cr end, 0)
      local cells = util.try(function() return net.cells end, {})
      out[#out + 1] = {
        robots = nr,
        availableRobots = util.try(function() return #avail end, 0),
        logisticRobots = util.try(function() return #lr end, 0),
        constructionRobots = util.try(function() return #cr end, 0),
        cellCount = util.try(function() return #cells end, 0),
        networkId = util.try(function() return net.network_id end, nil),
      }
    end
  end

  return {
    surface = sname,
    force = fname,
    position = center,
    networkCount = #out,
    networks = out,
    totalRobots = total_robots,
    totalAvailable = total_available,
    logisticRobots = total_logistic_robots,
    constructionRobots = total_construction_robots,
  }
end

--- get_item_stats ------------------------------------------------------------
function M.get_item_stats(args)
  args = args or {}
  local surface, sname = surface_of(args)
  local force, fname = force_of(args)
  if surface == nil or force == nil then return { error = 'surface/force unavailable' } end

  local item = args.item
  if item ~= nil and item ~= '' then
    local name = tostring(item)
    local counts = {
      entitiesOnSurface = util.try(function() return surface.count_entities_filtered({ name = name }) end, nil),
      tilesOnSurface = util.try(function() return surface.count_tiles_filtered({ name = name }) end, nil),
      harvested = util.try(function()
        local stats = force.get_item_production_statistics(surface)
        return stats and stats.output_counts and stats.output_counts[name] or nil
      end, nil),
    }
    return { surface = sname, force = fname, item = name, counts = counts }
  end

  local prototype_counts = {}
  util.try(function()
    for _, kind in ipairs({ 'item', 'fluid', 'entity', 'recipe', 'technology', 'tile', 'virtual_signal', 'quality', 'equipment' }) do
      local set = prototypes[kind]
      if set then
        local n = 0
        for _ in pairs(set) do n = n + 1 end
        prototype_counts[kind] = n
      end
    end
  end)

  local rows = {}
  if type(args.items) == 'table' then
    for _, name in ipairs(args.items) do
      local nm = tostring(name)
      rows[#rows + 1] = {
        item = nm,
        entitiesOnSurface = util.try(function() return surface.count_entities_filtered({ name = nm }) end, nil),
        tilesOnSurface = util.try(function() return surface.count_tiles_filtered({ name = nm }) end, nil),
      }
    end
  end

  return {
    surface = sname,
    force = fname,
    prototypeCounts = prototype_counts,
    itemCounts = rows,
    hint = 'pass "item" for one item or "items" for a list; per-item counting uses entity and tile censuses which are exact',
  }
end

--- get_inventory -------------------------------------------------------------
function M.get_inventory(args)
  args = args or {}
  local name = args.playerName or args.player
  if name == nil or name == '' then return { error = 'playerName is required' } end
  local player = util.try(function() return game.get_player(tostring(name)) end, nil)
  if player == nil then return { error = 'no player named ' .. tostring(name) } end

  local out = {}
  local kinds = {
    { 'main', defines.inventory.character_main },
    { 'armor', defines.inventory.character_armor },
    { 'guns', defines.inventory.character_guns },
    { 'ammo', defines.inventory.character_ammo },
    { 'trash', defines.inventory.character_trash },
    { 'logistic', defines.inventory.character_logistic_slot },
    { 'cursor', defines.inventory.character_cursor },
  }
  for _, e in ipairs(kinds) do
    local inv = util.try(function() return player.get_inventory(e[2]) end, nil)
    if inv then
      local items = {}
      local n = util.try(function() return #inv end, 0)
      for i = 1, n do
        local stack = inv[i]
        if stack and util.try(function() return stack.valid_for_read end, false) then
          items[#items + 1] = {
            itemId = util.try(function() return stack.name end, 'unknown'),
            slot = i,
            count = util.try(function() return stack.count end, 0),
            quality = util.try(function() return stack.quality and stack.quality.name or nil end, nil),
            durability = util.try(function() return stack.durability end, nil),
            maxDurability = util.try(function() return stack.max_durability end, nil),
            isBlueprint = util.try(function() return stack.is_blueprint end, false),
          }
        end
      end
      out[e[1]] = { slots = n, items = items }
    end
  end

  return {
    playerName = util.try(function() return player.name end, name),
    position = util.position(util.try(function() return player.position end, nil)),
    surface = util.try(function() return player.physical_surface and player.physical_surface.name or nil end, nil),
    inventories = out,
  }
end

--- get_chest_contents --------------------------------------------------------
function M.get_chest_contents(args)
  args = args or {}
  local surface, sname = surface_of(args)
  if surface == nil then return { error = 'no surface available' } end
  if args.x == nil or args.y == nil then
    return { error = 'x and y are required' }
  end
  local pos = { x = tonumber(args.x), y = tonumber(args.y) }
  local entity = util.try(function()
    return surface.find_entity(args.entity or 'wooden-chest', pos)
  end, nil)
  if entity == nil then
    entity = util.try(function()
      return surface.find_entities_filtered({ position = pos, limit = 1 })[1]
    end, nil)
  end
  if entity == nil then return { error = 'no entity at that position', position = pos } end

  local ok, result = pcall(function()
    local inv = entity.get_inventory(defines.inventory.chest)
    if inv == nil then
      inv = entity.get_inventory(defines.inventory.cargo_wagon)
    end
    if inv == nil then return nil end
    local items = {}
    local n = #inv
    for i = 1, n do
      local stack = inv[i]
      if stack and stack.valid_for_read then
        items[#items + 1] = {
          itemId = stack.name,
          slot = i,
          count = stack.count,
          quality = stack.quality and stack.quality.name or nil,
        }
      end
    end
    return items
  end)

  if not ok or result == nil then
    return { error = 'entity has no readable chest inventory', entity = util.try(function() return entity.name end, 'unknown') }
  end

  return {
    surface = sname,
    position = pos,
    entity = util.try(function() return entity.name end, 'unknown'),
    unitNumber = util.try(function() return entity.unit_number end, nil),
    itemCount = #result,
    items = result,
  }
end

--- get_factory_overview ------------------------------------------------------
function M.get_factory_overview(args)
  args = args or {}
  local surface, sname = surface_of(args)
  local force, fname = force_of(args)
  if surface == nil then return { error = 'no surface available' } end

  local out = {
    surface = sname,
    force = fname,
    entities = util.try(function() return surface.count_entities_filtered({ force = force.name }) end, nil),
    totalEntities = util.try(function() return surface.count_entities_filtered({}) end, nil),
    generatedChunks = util.generated_chunk_count(surface),
    chartedChunks = util.charted_chunk_count(surface, nil, 48),
    pollution = util.round(util.try(function() return surface.get_pollution({ 0, 0 }) end, 0) or 0, 4),
    evolution = util.round(util.try(function() return force.get_evolution_factor(surface) end, 0), 6),
  }
  local research = players_tools.get_research_status({ force = fname })
  out.research = {
    current = research.currentResearch and research.currentResearch.name or nil,
    progress = research.currentResearch and research.currentResearch.progress or 0,
    researched = research.researched,
    available = research.available,
    queued = #(research.queue or {}),
  }
  out.bottleneckHints = {}
  return out
end

return M
