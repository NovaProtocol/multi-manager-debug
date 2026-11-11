-- multi-manager-debug :: util.lua
-- Small defensive helpers shared by every tool implementation. Every access to
-- an entity, prototype or player field goes through here so a missing or
-- renamed API can never take the server down.

local util = {}

--- pcall wrapper that returns (ok, value) and never throws.
function util.safe(fn, ...)
  local args = { ... }
  local ok, res = pcall(fn, table.unpack and table.unpack(args) or unpack(args))
  return ok, res
end

--- Call fn(...), return its result or `fallback` when it throws.
function util.try(fn, fallback, ...)
  local ok, res = pcall(fn, ...)
  if ok and res ~= nil then return res end
  return fallback
end

--- Round to `digits` decimals; keeps JSON payloads compact.
function util.round(n, digits)
  if type(n) ~= 'number' then return n end
  local mult = 10 ^ (digits or 3)
  return math.floor(n * mult + 0.5) / mult
end

function util.clamp(n, lo, hi)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

--- Iterate a Factorio "custom table" (game.players, game.forces, game.surfaces,
--- game.connected_players, LuaForce.technologies, ...). These are userdata and
--- cannot be used with pairs(), only with integer indexing and #.
function util.each_custom(custom_table)
  local i = 1
  return function()
    local v = custom_table[i]
    if v == nil then return nil end
    i = i + 1
    return v
  end
end

--- Iterate a plain Lua table's values.
function util.each_value(t)
  return function()
    local k, v = next(t)
    if k == nil then return nil end
    t[k] = nil
    return v
  end
end

function util.count(t)
  if t == nil then return 0 end
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

--- First element of a Factorio dictionary-like table without pairs().
function util.first_key(t)
  if t == nil then return nil end
  for k in pairs(t) do return k end
  return nil
end

--- Hex-encode a string (used for the token file written for the external).
function util.hex(s)
  return (s:gsub('.', function(c) return string.format('%02x', string.byte(c)) end))
end

function util.random_string(n, alphabet)
  local chars = alphabet or 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
  local len = #chars
  local out = {}
  for _ = 1, n do
    local idx = math.random(len)
    out[#out + 1] = chars:sub(idx, idx)
  end
  return table.concat(out)
end

--- Compact ISO-8601-ish UTC timestamp for a given tick.
function util.tick_to_iso(tick)
  local seconds = (tick or game.tick) / 60
  return string.format('tick:%d', math.floor(tick or game.tick)), util.round(seconds, 3)
end

--- Read a value from a Lua dictionary-ish table with a safe fallback.
function util.get(t, key, fallback)
  if t == nil then return fallback end
  local v = util.try(function() return t[key] end, nil)
  if v == nil then return fallback end
  return v
end

--- Generated-chunk census for one surface.
--- Factorio 2.1 has no chunk-count API, but is_chunk_generated() is cheap and
--- the generated area is contiguous, so expand the claimed bounding box until
--- it stops growing. Bounded by `limit` chunks half-width.
function util.generated_chunk_stats(surface, limit)
  if surface == nil then return nil end
  local n = util.try(function() return surface.count_chunks() end, nil)
  if n ~= nil then return { count = n, exact = true } end
  limit = limit or 256
  local minx, maxx, miny, maxy = nil, nil, nil, nil

  local function generated(cx, cy)
    return util.try(function() return surface.is_chunk_generated({ x = cx, y = cy }) end, false) == true
  end

  local function claim(cx, cy)
    if not generated(cx, cy) then return false end
    if minx == nil or cx < minx then minx = cx end
    if maxx == nil or cx > maxx then maxx = cx end
    if miny == nil or cy < miny then miny = cy end
    if maxy == nil or cy > maxy then maxy = cy end
    return true
  end

  if not claim(0, 0) then
    return { count = 0, exact = true, note = 'spawn chunk not generated yet' }
  end

  local grew = true
  local guard = 0
  while grew and guard < limit do
    grew = false
    guard = guard + 1
    -- probe the ring just outside the claimed box
    for cx = minx - 1, maxx + 1 do
      if claim(cx, miny - 1) then grew = true end
      if claim(cx, maxy + 1) then grew = true end
    end
    for cy = miny - 1, maxy + 1 do
      if claim(minx - 1, cy) then grew = true end
      if claim(maxx + 1, cy) then grew = true end
    end
  end

  local w = (maxx - minx + 1)
  local h = (maxy - miny + 1)
  return {
    count = w * h,
    exact = guard < limit,
    bounds = { minX = minx, maxX = maxx, minY = miny, maxY = maxy },
    widthChunks = w,
    heightChunks = h,
    limitReached = guard >= limit,
  }
end

--- Convenience wrapper returning just the count.
function util.generated_chunk_count(surface, limit)
  local stats = util.generated_chunk_stats(surface, limit)
  return stats and stats.count or 0
end

--- Charted/explored chunk census for a force (window walk; expensive).
function util.charted_chunk_count(surface, force, limit)
  if surface == nil then return 0 end
  if force == nil then force = util.try(function() return game.forces.player end, nil) end
  if force == nil then return 0 end
  limit = limit or 64
  local count = 0
  for cx = -limit, limit do
    for cy = -limit, limit do
      if util.try(function() return force.is_chunk_charted(surface, { x = cx, y = cy }) end, false) then
        count = count + 1
      end
    end
  end
  return count
end

--- Describe a LuaEntity/LuaItemStack position safely.
function util.position(pos)
  if pos == nil then return nil end
  local x = util.try(function() return pos.x end, nil)
  local y = util.try(function() return pos.y end, nil)
  if x == nil or y == nil then return nil end
  return { x = util.round(x, 3), y = util.round(y, 3) }
end

return util
