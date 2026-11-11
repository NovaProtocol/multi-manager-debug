-- multi-manager-debug :: clock.lua
-- The Factorio Lua sandbox ships an empty `os` table (no os.time / os.clock) and
-- no wall-clock API at all. The external therefore hands its own wall clock to the
-- mod with every RPC and we extrapolate from game.tick in between, so behaviour
-- records still carry real unix timestamps.

local clock = {}

local anchor = {
  wall = nil,      -- unix seconds reported by the external
  tick = nil,      -- game.tick when that wall clock was observed
  rttEstimateMs = 0,
}

--- Called by the RPC layer whenever a call arrives with a external timestamp.
function clock.sync(wall_seconds, tick)
  local w = tonumber(wall_seconds)
  if w == nil or w <= 0 then return end
  anchor.wall = w
  anchor.tick = tonumber(tick) or game.tick
end

--- Best available unix timestamp (integer seconds).
function clock.now()
  if anchor.wall == nil then
    -- Nothing has synced us yet: expose ticks-derived seconds since world start
    -- so callers still get a monotonic, ordered value.
    return math.floor(game.tick / 60)
  end
  return math.floor(anchor.wall + (game.tick - anchor.tick) / 60)
end

--- Fractional unix timestamp (sub-second precision for fast sampling).
function clock.now_ms()
  if anchor.wall == nil then
    return game.tick / 60
  end
  return anchor.wall + (game.tick - anchor.tick) / 60
end

function clock.is_synced()
  return anchor.wall ~= nil
end

function clock.status()
  return {
    synced = anchor.wall ~= nil,
    anchorWall = anchor.wall,
    anchorTick = anchor.tick,
    currentTick = game.tick,
    now = clock.now(),
  }
end

return clock
