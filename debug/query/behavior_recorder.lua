-- multi-manager-debug :: behavior_recorder.lua
-- High-frequency player behaviour sampling. Each sample carries 23+ fields
-- (position, movement, health, hand items, inventory snapshot, ...). Records
-- are appended to script-output/multi-manager-debug/behave.jsonl and kept in a
-- bounded in-memory ring so behavior_query_history can serve them even when the
-- external runs on another machine.

local util = require('debug.query.util')
local json = require('debug.query.json')
local clock = require('debug.query.clock')

local recorder = {}

local COLUMNS = {
  'timestamp', 'timestampMs', 'tick', 'playerName', 'playerIndex', 'online', 'health', 'maxHealth', 'healthPercent',
  'posX', 'posY', 'posZ', 'surface', 'yaw', 'pitch', 'movementSpeed', 'isMoving', 'distanceSinceLast',
  'direction', 'walkingState', 'isOnGround', 'isSprinting', 'isSneaking', 'isFlying',
  'mainHandItemId', 'mainHandItemCount', 'offHandItemId', 'offHandItemCount',
  'armorItemId', 'gunItemId', 'ammoItemId', 'ammoItemCount',
  'craftingQueueLength', 'inventorySnapshotCount', 'inventory',
}
recorder.COLUMNS = COLUMNS

local INVENTORY_COLUMNS = { 'itemId', 'slot', 'count', 'quality', 'durability', 'maxDurability', 'durabilityPercent' }

local state = {
  enabled = true,
  trackAllPlayers = true,
  highFreqIntervalMs = 250,
  lowFreqIntervalMs = 1000,
  maxHistoryPerPlayer = 2000,
  flushIntervalTicks = 30,
  logFile = 'multi-manager-debug/behave.jsonl',
  tracked = {},          -- name(lower) -> true
  history = {},          -- name(lower) -> array of records
  lastPositions = {},    -- name(lower) -> {x=,y=}
  lastSampleMs = {},     -- name(lower) -> ms since last sample
  nextDue = {},          -- name(lower) -> accumulated ms until next high freq sample
  queue = {},            -- pending JSONL lines
  totalRecords = 0,
  droppedRecords = 0,
  writeErrors = 0,
  lastFlushTick = 0,
  ioEnabled = true,
  startedTick = 0,
  lastAutoReset = 0,
}

local HIGH_FREQ_FIELDS = { 'position', 'movement', 'health', 'hand', 'inventory', 'surface' }
recorder.HIGH_FREQ_FIELDS = HIGH_FREQ_FIELDS

function recorder.configure(cfg)
  state.enabled = cfg.behavior.enabled
  state.trackAllPlayers = cfg.behavior.trackAllPlayers
  state.highFreqIntervalMs = cfg.behavior.highFreqIntervalMs
  state.lowFreqIntervalMs = cfg.behavior.lowFreqIntervalMs
  state.maxHistoryPerPlayer = cfg.behavior.maxHistoryPerPlayer
  state.flushIntervalTicks = cfg.behavior.flushIntervalTicks
  state.logFile = 'multi-manager-debug/' .. cfg.behavior.logFileName
  state.startedTick = game.tick
end

-- ---------------------------------------------------------------------------
-- sampling
-- ---------------------------------------------------------------------------

local function inventory_of(player)
  local inv = util.try(function() return player.get_main_inventory() end, nil)
  if inv == nil then return {} end
  local items = {}
  local n = util.try(function() return #inv end, 0)
  for i = 1, n do
    local stack = inv[i]
    if stack ~= nil and util.try(function() return stack.valid_for_read end, false) then
      local max_dur = util.try(function() return stack.max_durability end, 0) or 0
      local dur = util.try(function() return stack.durability end, nil)
      items[#items + 1] = {
        itemId = util.try(function() return stack.name end, 'unknown'),
        slot = i,
        count = util.try(function() return stack.count end, 0),
        quality = util.try(function() return stack.quality and stack.quality.name or nil end, nil),
        durability = dur,
        maxDurability = max_dur,
        durabilityPercent = (max_dur and max_dur > 0 and dur) and util.round(100 * dur / max_dur, 2) or nil,
      }
    end
  end
  return items
end

local function read_stack(player, kind)
  local stack = nil
  if kind == 'main' then
    stack = util.try(function() return player.cursor_stack end, nil)
  elseif kind == 'off' then
    stack = util.try(function() return player.cursor_stack end, nil)
  end
  return stack
end

local function held_item(stack)
  if stack == nil then return nil, 0 end
  if not util.try(function() return stack.valid_for_read end, false) then return nil, 0 end
  return util.try(function() return stack.name end, nil), util.try(function() return stack.count end, 0)
end

function recorder.sample(player, now_ms, high_freq)
  local name = util.try(function() return player.name end, nil)
  if name == nil then return nil end
  local key = string.lower(name)
  local character = util.try(function() return player.character end, nil)
  local position = util.position(util.try(function() return player.position end, nil))
  local surface = util.try(function() return player.physical_surface and player.physical_surface.name or nil end, nil)

  local prev = state.lastPositions[key]
  local distance = 0
  if prev and position then
    local dx, dy = position.x - prev.x, position.y - prev.y
    distance = util.round(math.sqrt(dx * dx + dy * dy), 3)
  end
  if position then state.lastPositions[key] = position end

  local main_stack = util.try(function() return player.cursor_stack end, nil)
  local main_id, main_count = held_item(main_stack)
  local armor = util.try(function() return player.get_inventory(defines.inventory.character_armor)[1] end, nil)
  local gun = util.try(function() return player.get_inventory(defines.inventory.character_guns)[1] end, nil)
  local ammo = util.try(function() return player.get_inventory(defines.inventory.character_ammo)[1] end, nil)
  local armor_id = held_item(armor)
  local gun_id = held_item(gun)
  local ammo_id, ammo_count = held_item(ammo)

  local record = {
    timestamp = clock.now(),
    timestampMs = util.round(clock.now_ms(), 3),
    tick = game.tick,
    playerName = name,
    playerIndex = util.try(function() return player.index end, nil),
    online = util.try(function() return player.connected end, false),
    health = util.round(util.try(function() return character.health end, 0) or 0, 2),
    maxHealth = util.round(util.try(function() return character.max_health end, 0) or 0, 2),
    healthPercent = 0,
    posX = position and position.x or nil,
    posY = position and position.y or nil,
    posZ = 0,
    surface = surface,
    yaw = nil,
    pitch = nil,
    movementSpeed = util.round(util.try(function() return character.speed end, 0) or 0, 4),
    isMoving = util.try(function() return character.moving end, false),
    distanceSinceLast = distance,
    direction = util.try(function() return defines.direction[character.direction] end, nil),
    walkingState = util.try(function() return character.walking_state and defines.walking_state[character.walking_state.walking_state] or nil end, nil),
    isOnGround = util.try(function() return character.valid and true end, true),
    isSprinting = util.try(function() return character.walking_state and character.walking_state.walking_state == defines.walking_state.walking end, false),
    isSneaking = util.try(function() return player.character and player.character.name == nil end, false),
    isFlying = util.try(function() return character.flying end, false),
    mainHandItemId = main_id,
    mainHandItemCount = main_count or 0,
    offHandItemId = nil,
    offHandItemCount = 0,
    armorItemId = armor_id,
    gunItemId = gun_id,
    ammoItemId = ammo_id,
    ammoItemCount = ammo_count or 0,
    craftingQueueLength = util.try(function() return #player.crafting_queue end, 0),
    inventorySnapshotCount = 0,
    inventory = {},
    sampleMode = high_freq and 'high' or 'low',
  }

  if record.maxHealth and record.maxHealth > 0 then
    record.healthPercent = util.round(100 * record.health / record.maxHealth, 2)
  end

  if high_freq then
    local items = inventory_of(player)
    record.inventory = items
    record.inventorySnapshotCount = #items
  end

  -- rolling history
  local hist = state.history[key]
  if hist == nil then
    hist = {}
    state.history[key] = hist
  end
  hist[#hist + 1] = record
  while #hist > state.maxHistoryPerPlayer do
    table.remove(hist, 1)
    state.droppedRecords = state.droppedRecords + 1
  end
  state.totalRecords = state.totalRecords + 1
  state.queue[#state.queue + 1] = json.encode(record)
  return record
end

--- Called from on_tick. Drives high/low frequency sampling per tracked player.
function recorder.update()
  if not state.enabled then return end
  local dt_ms = 1000 / 60
  local players = game.connected_players
  local n = util.try(function() return #players end, 0)
  for i = 1, n do
    local player = players[i]
    local name = util.try(function() return player.name end, nil)
    if name then
      local key = string.lower(name)
      if state.trackAllPlayers or state.tracked[key] then
        state.tracked[key] = true
        local acc = (state.nextDue[key] or state.lowFreqIntervalMs) + dt_ms
        local high = acc >= state.highFreqIntervalMs
        if high or (state.lastSampleMs[key] or 0) + dt_ms >= state.lowFreqIntervalMs then
          local ok, err = pcall(recorder.sample, player, dt_ms, high)
          if ok then
            state.nextDue[key] = high and 0 or acc
            state.lastSampleMs[key] = 0
          else
            state.writeErrors = state.writeErrors + 1
            log('[multi-manager-debug] behavior sample failed: ' .. tostring(err))
          end
        else
          state.nextDue[key] = acc
          state.lastSampleMs[key] = (state.lastSampleMs[key] or 0) + dt_ms
        end
      end
    end
  end
  recorder.flush()
end

function recorder.flush(force)
  if #state.queue == 0 then return 0 end
  if not force and (game.tick - state.lastFlushTick) < state.flushIntervalTicks then return 0 end
  state.lastFlushTick = game.tick
  if not state.ioEnabled then
    state.queue = {}
    return 0
  end
  local payload = table.concat(state.queue, '\n') .. '\n'
  local count = #state.queue
  state.queue = {}
  local ok, err = pcall(function()
    helpers.write_file(state.logFile, payload, true)
  end)
  if not ok then
    state.ioEnabled = false
    state.writeErrors = state.writeErrors + 1
    log('[multi-manager-debug] behavior log disabled after IO error: ' .. tostring(err))
    return 0
  end
  return count
end

function recorder.on_player_left(player)
  local name = util.try(function() return player.name end, nil)
  if name == nil then return end
  local key = string.lower(name)
  state.lastPositions[key] = nil
  state.lastSampleMs[key] = nil
  state.nextDue[key] = nil
  recorder.flush(true)
end

function recorder.on_player_joined(player)
  local name = util.try(function() return player.name end, nil)
  if name == nil then return end
  if state.trackAllPlayers then
    state.tracked[string.lower(name)] = true
  end
end

-- ---------------------------------------------------------------------------
-- querying
-- ---------------------------------------------------------------------------

function recorder.track(name)
  if name == nil or name == '' or name == '*' then
    state.trackAllPlayers = true
    return true
  end
  state.tracked[string.lower(tostring(name))] = true
  return true
end

function recorder.untrack(name)
  if name == nil then return false end
  local low = string.lower(tostring(name))
  if low == '!all' or low == 'all' then
    state.tracked = {}
    state.trackAllPlayers = false
    return true
  end
  state.tracked[low] = nil
  return true
end

function recorder.clear(playerName)
  if playerName == nil or playerName == '' or playerName == '!all' then
    local cleared = util.count(state.history)
    state.history = {}
    state.droppedRecords = 0
    return cleared
  end
  local key = string.lower(tostring(playerName))
  local had = state.history[key] ~= nil
  state.history[key] = nil
  return had and 1 or 0
end

function recorder.latest(playerName)
  local key = string.lower(tostring(playerName or ''))
  local hist = state.history[key]
  if hist == nil or #hist == 0 then
    -- fall back to a live sample so callers always get something useful
    local n = util.try(function() return #game.connected_players end, 0)
    for i = 1, n do
      local p = game.connected_players[i]
      local nm = util.try(function() return p.name end, nil)
      if nm and string.lower(nm) == key then
        return recorder.sample(p, 0, true)
      end
    end
    return nil
  end
  return hist[#hist]
end

--- @param playerName string|nil nil/""/"*" = all players
--- @param fromTs number|nil unix seconds
--- @param toTs number|nil unix seconds
--- @param limit number|nil max records (newest kept)
function recorder.query(playerName, fromTs, toTs, limit)
  limit = util.clamp(tonumber(limit) or 100, 1, 5000)
  local keys = {}
  if playerName == nil or playerName == '' or playerName == '*' then
    for k in pairs(state.history) do keys[#keys + 1] = k end
  else
    keys[1] = string.lower(tostring(playerName))
  end

  local matched = {}
  for _, k in ipairs(keys) do
    local hist = state.history[k]
    if hist then
      for i = #hist, 1, -1 do
        local r = hist[i]
        local ok = true
        if fromTs and r.timestamp and r.timestamp < fromTs then ok = false end
        if ok and toTs and r.timestamp and r.timestamp > toTs then ok = false end
        if ok then matched[#matched + 1] = r end
      end
    end
  end
  -- matched is newest-first; keep newest `limit` then reverse
  local out = {}
  for i = math.min(#matched, limit), 1, -1 do out[#out + 1] = matched[i] end
  return out, #matched > limit
end

local function csv_escape(v)
  if v == nil then return '' end
  local s = tostring(v)
  if s:find('[,"\n\r]') then
    return '"' .. s:gsub('"', '""') .. '"'
  end
  return s
end

local function flat(record, col)
  if col == 'inventory' then
    local parts = {}
    for _, item in ipairs(record.inventory or {}) do
      parts[#parts + 1] = string.format('%sx%d@%d', item.itemId or '?', item.count or 0, item.slot or 0)
    end
    return table.concat(parts, '|')
  end
  return record[col]
end

function recorder.to_csv(records, include_inventory)
  local cols = {}
  for _, c in ipairs(COLUMNS) do cols[#cols + 1] = c end
  if not include_inventory then
    local trimmed = {}
    for _, c in ipairs(cols) do if c ~= 'inventory' then trimmed[#trimmed + 1] = c end end
    cols = trimmed
  end
  local lines = { table.concat(cols, ',') }
  for _, r in ipairs(records) do
    local row = {}
    for i, c in ipairs(cols) do
      local v = flat(r, c)
      if type(v) == 'number' then
        if c:find('^pos') or c == 'movementSpeed' or c == 'distanceSinceLast' then
          v = string.format('%.4f', v)
        else
          v = tostring(v)
        end
      elseif type(v) == 'boolean' then
        v = v and 'true' or 'false'
      end
      row[i] = csv_escape(v)
    end
    lines[#lines + 1] = table.concat(row, ',')
  end
  return table.concat(lines, '\n')
end

function recorder.inventory_columns()
  return INVENTORY_COLUMNS
end

function recorder.status()
  local per_player = {}
  local keys = {}
  for k in pairs(state.history) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    per_player[#per_player + 1] = { player = k, samples = #state.history[k] }
  end
  return {
    enabled = state.enabled,
    trackAllPlayers = state.trackAllPlayers,
    highFreqIntervalMs = state.highFreqIntervalMs,
    lowFreqIntervalMs = state.lowFreqIntervalMs,
    maxHistoryPerPlayer = state.maxHistoryPerPlayer,
    flushIntervalTicks = state.flushIntervalTicks,
    logFile = state.logFile,
    ioEnabled = state.ioEnabled,
    pendingWrites = #state.queue,
    totalRecords = state.totalRecords,
    droppedRecords = state.droppedRecords,
    ioErrors = state.writeErrors,
    trackedPlayers = (function()
      local t = {}
      for k in pairs(state.tracked) do t[#t + 1] = k end
      table.sort(t)
      return t
    end)(),
    startedTick = state.startedTick,
    runningTicks = game.tick - state.startedTick,
    fields = COLUMNS,
    inventoryFields = INVENTORY_COLUMNS,
    inventorySnapshotWhen = 'high-frequency samples only',
    perPlayer = per_player,
  }
end

--- Mark a player as no longer tracked because they disconnected.
function recorder.forget_runtime(name)
  local key = string.lower(tostring(name))
  state.lastPositions[key] = nil
  state.lastSampleMs[key] = nil
  state.nextDue[key] = nil
end

return recorder
