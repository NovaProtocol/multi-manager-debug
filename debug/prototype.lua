-- multi-manager-debug :: prototype.lua
-- Generic prototype and Lua inspection. The prototype classes are discovered from
-- `prototypes` at runtime; this file does not need an update when a mod adds a class.

local M = {operations = {}}

local PROTOTYPE_TYPES = {
    "accumulator",
    "achievement",
    "active-defense-equipment",
    "agricultural-tower",
    "airborne-pollutant",
    "ambient-sound",
    "ammo",
    "ammo-category",
    "ammo-turret",
    "animation",
    "arithmetic-combinator",
    "armor",
    "arrow",
    "artillery-flare",
    "artillery-projectile",
    "artillery-turret",
    "artillery-wagon",
    "assembling-machine",
    "asteroid",
    "asteroid-chunk",
    "asteroid-collector",
    "autoplace-control",
    "battery-equipment",
    "beacon",
    "beam",
    "belt-immunity-equipment",
    "blueprint",
    "blueprint-book",
    "boiler",
    "build-entity-achievement",
    "burner-generator",
    "burner-usage",
    "capsule",
    "capture-robot",
    "car",
    "cargo-bay",
    "cargo-landing-pad",
    "cargo-pod",
    "cargo-wagon",
    "chain-active-trigger",
    "change-surface-achievement",
    "character",
    "character-corpse",
    "cliff",
    "collision-layer",
    "combat-robot",
    "combat-robot-count-achievement",
    "complete-objective-achievement",
    "constant-combinator",
    "construct-with-robots-achievement",
    "construction-robot",
    "container",
    "copy-paste-tool",
    "corpse",
    "create-platform-achievement",
    "curved-rail-a",
    "curved-rail-b",
    "custom-event",
    "custom-input",
    "damage-type",
    "decider-combinator",
    "deconstruct-with-robots-achievement",
    "deconstructible-tile-proxy",
    "deconstruction-item",
    "delayed-active-trigger",
    "deliver-by-robots-achievement",
    "deliver-category",
    "deliver-impact-combination",
    "deplete-resource-achievement",
    "destroy-cliff-achievement",
    "display-panel",
    "dont-build-entity-achievement",
    "dont-craft-manually-achievement",
    "dont-kill-manually-achievement",
    "dont-research-before-researching-achievement",
    "dont-use-entity-in-energy-production-achievement",
    "editor-controller",
    "electric-energy-interface",
    "electric-energy-interface-equipment",
    "electric-pole",
    "electric-turret",
    "elevated-curved-rail-a",
    "elevated-curved-rail-b",
    "elevated-half-diagonal-rail",
    "elevated-straight-rail",
    "energy-shield-equipment",
    "entity-ghost",
    "equip-armor-achievement",
    "equipment-category",
    "equipment-ghost",
    "equipment-grid",
    "explosion",
    "fire",
    "fish",
    "fluid",
    "fluid-turret",
    "fluid-wagon",
    "font",
    "fuel-category",
    "furnace",
    "fusion-generator",
    "fusion-reactor",
    "gate",
    "generator",
    "generator-equipment",
    "god-controller",
    "group-attack-achievement",
    "gui-style",
    "gun",
    "half-diagonal-rail",
    "heat-interface",
    "heat-pipe",
    "highlight-box",
    "impact-category",
    "infinity-cargo-wagon",
    "infinity-container",
    "infinity-pipe",
    "inserter",
    "inventory-bonus-equipment",
    "item",
    "item-entity",
    "item-group",
    "item-request-proxy",
    "item-subgroup",
    "item-with-entity-data",
    "item-with-inventory",
    "item-with-label",
    "item-with-tags",
    "kill-achievement",
    "lab",
    "lamp",
    "land-mine",
    "lane-splitter",
    "legacy-curved-rail",
    "legacy-straight-rail",
    "lightning",
    "lightning-attractor",
    "linked-belt",
    "linked-container",
    "loader",
    "loader-1x1",
    "locomotive",
    "logistic-container",
    "logistic-robot",
    "map-gen-presets",
    "map-settings",
    "market",
    "mining-drill",
    "mod-data",
    "module",
    "module-category",
    "module-transfer-achievement",
    "mouse-cursor",
    "movement-bonus-equipment",
    "night-vision-equipment",
    "noise-expression",
    "noise-function",
    "offshore-pump",
    "optimized-decorative",
    "optimized-particle",
    "particle-source",
    "pipe",
    "pipe-to-ground",
    "place-equipment-achievement",
    "planet",
    "plant",
    "player-damaged-achievement",
    "player-port",
    "power-switch",
    "procession",
    "procession-layer-inheritance-group",
    "produce-achievement",
    "produce-per-hour-achievement",
    "programmable-speaker",
    "projectile",
    "proxy-container",
    "pump",
    "quality",
    "radar",
    "rail-chain-signal",
    "rail-planner",
    "rail-ramp",
    "rail-remnants",
    "rail-signal",
    "rail-support",
    "reactor",
    "recipe",
    "recipe-category",
    "remote-controller",
    "repair-tool",
    "research-achievement",
    "research-with-science-pack-achievement",
    "resource",
    "resource-category",
    "roboport",
    "roboport-equipment",
    "rocket-silo",
    "rocket-silo-rocket",
    "rocket-silo-rocket-shadow",
    "segment",
    "segmented-unit",
    "selection-tool",
    "selector-combinator",
    "shoot-achievement",
    "shortcut",
    "simple-entity",
    "simple-entity-with-force",
    "simple-entity-with-owner",
    "smoke-with-trigger",
    "solar-panel",
    "solar-panel-equipment",
    "sound",
    "space-connection",
    "space-connection-distance-traveled-achievement",
    "space-location",
    "space-platform-hub",
    "space-platform-starter-pack",
    "spectator-controller",
    "speech-bubble",
    "spider-leg",
    "spider-unit",
    "spider-vehicle",
    "spidertron-remote",
    "splitter",
    "sprite",
    "sticker",
    "storage-tank",
    "straight-rail",
    "stream",
    "surface",
    "surface-property",
    "technology",
    "temporary-container",
    "thruster",
    "tile",
    "tile-effect",
    "tile-ghost",
    "tips-and-tricks-item",
    "tips-and-tricks-item-category",
    "tool",
    "train-path-achievement",
    "train-stop",
    "transport-belt",
    "tree",
    "trigger-target-type",
    "trivial-smoke",
    "turret",
    "tutorial",
    "underground-belt",
    "unit",
    "unit-spawner",
    "upgrade-item",
    "use-entity-in-energy-production-achievement",
    "use-item-achievement",
    "utility-constants",
    "utility-sounds",
    "utility-sprites",
    "valve",
    "virtual-signal",
    "wall",
}

local TOP_LEVEL_CLASSES = {
    "achievement", "ammo-category", "autoplace-control", "custom-event", "custom-input",
    "damage-type", "decorative", "deliver-category", "deliver-impact-combination",
    "entity", "equipment", "equipment-grid", "fluid", "fuel-category", "impact-category",
    "item", "item-group", "item-subgroup", "map-gen-presets", "map-settings", "mod-data",
    "module-category", "mouse-cursor", "noise-expression", "noise-function", "particle",
    "planet", "procession", "procession-layer-inheritance-group", "quality", "recipe",
    "recipe-category", "resource-category", "shortcut", "space-connection", "space-location",
    "surface", "technology", "tile", "tile-effect", "tips-and-tricks-item",
    "trigger-target-type", "utility-constants", "utility-sounds", "utility-sprites",
    "virtual-signal",
}

local MAX_FIELDS = 120
local MAX_DEPTH = 3

local function safe(fn)
    local ok, value = pcall(fn)
    if ok then return value end
end

local function describe(value, depth, seen, field_count)
    depth = depth or MAX_DEPTH
    seen = seen or {}
    field_count = field_count or 0
    local kind = type(value)

    if kind == "nil" or kind == "string" or kind == "number" or kind == "boolean" then
        return value
    end
    if kind == "function" then
        return "<function>"
    end
    if depth <= 0 then
        return "<depth>"
    end
    if kind == "userdata" or kind == "cdata" then
        local name = safe(function() return value.name end)
        local typename = safe(function() return value.type end)
        if name ~= nil then
            return {name = name, type = typename}
        end
        return tostring(value)
    end
    if kind ~= "table" then
        return tostring(value)
    end
    if seen[value] then
        return "<cycle>"
    end

    seen[value] = true
    local out = {}
    local count = 0
    local ok = pcall(function()
        for key, entry in pairs(value) do
            count = count + 1
            if count > MAX_FIELDS then
                out._truncated = true
                break
            end
            out[tostring(key)] = describe(entry, depth - 1, seen, count)
        end
    end)
    seen[value] = nil
    if not ok then
        return tostring(value)
    end
    return out
end

local function prototypes_for(kind)
    if type(kind) ~= "string" or kind == "" then
        error("class is required")
    end
    local direct = safe(function() return prototypes[kind] end)
    if direct then
        return direct
    end
    local out = {}
    for _, broad in ipairs(TOP_LEVEL_CLASSES) do
        local set = safe(function() return prototypes[broad] end)
        if set then
            for name, proto in pairs(set) do
                if safe(function() return proto.type end) == kind then
                    out[name] = proto
                end
            end
        end
    end
    if next(out) == nil then
        error("unknown prototype class: " .. tostring(kind))
    end
    return out
end

local function prototype_name(proto)
    return safe(function() return proto.name end) or "<unknown>"
end

local function prototype_type(proto)
    return safe(function() return proto.type end)
end

local function class_names()
    return TOP_LEVEL_CLASSES
end

M.operations.prototype_classes = function()
    local out = {}
    for _, name in ipairs(class_names()) do
        local count = 0
        local set = safe(function() return prototypes[name] end)
        if set then
            pcall(function()
                for _ in pairs(set) do count = count + 1 end
            end)
        end
        out[#out + 1] = {class = name, count = count}
    end
    return {classes = out, total = #out, types = PROTOTYPE_TYPES}
end

M.operations.prototype_list = function(_, p)
    p = p or {}
    local set = prototypes_for(p.class)
    local names = {}
    for name, proto in pairs(set) do
        if p.query == nil or p.query == "" or tostring(name):lower():find(tostring(p.query):lower(), 1, true) then
            names[#names + 1] = tostring(name)
        end
    end
    table.sort(names)
    local offset = math.max(0, tonumber(p.offset) or 0)
    local limit = math.min(math.max(1, tonumber(p.limit) or 100), 1000)
    local out = {}
    for i = offset + 1, math.min(offset + limit, #names) do
        local proto = set[names[i]]
        out[#out + 1] = {
            name = names[i],
            type = prototype_type(proto),
            hidden = safe(function() return proto.hidden end),
            order = safe(function() return proto.order end),
        }
    end
    return {class = p.class, prototypes = out, total = #names, next_offset = offset + limit < #names and offset + limit or nil}
end

M.operations.prototype_get = function(_, p)
    p = p or {}
    local set = prototypes_for(p.class)
    local proto = set[p.name]
    if proto == nil then
        error("unknown " .. tostring(p.class) .. " prototype: " .. tostring(p.name))
    end

    local fields = {}
    local count = 0
    local ok = pcall(function()
        for key, value in pairs(proto) do
            count = count + 1
            if count > (tonumber(p.max_fields) or MAX_FIELDS) then
                fields._truncated = true
                break
            end
            fields[tostring(key)] = describe(value, tonumber(p.depth) or MAX_DEPTH, nil, count)
        end
    end)
    if not ok or count == 0 then
        -- Some prototype userdata tables do not enumerate. The common identity and
        -- geometry fields still make the object useful, and callers can ask for a
        -- specific field with prototype_field.
        for _, key in ipairs({"name", "type", "order", "hidden", "localised_name", "subgroup", "group",
            "flags", "collision_box", "selection_box", "icon", "icon_size"}) do
            local value = safe(function() return proto[key] end)
            if value ~= nil then fields[key] = describe(value, tonumber(p.depth) or MAX_DEPTH, nil, count) end
        end
    end

    return {class = p.class, name = tostring(p.name), type = prototype_type(proto), fields = fields}
end

M.operations.prototype_field = function(_, p)
    p = p or {}
    local set = prototypes_for(p.class)
    local proto = set[p.name]
    if proto == nil then error("unknown " .. tostring(p.class) .. " prototype: " .. tostring(p.name)) end
    local value = proto[p.field]
    if value == nil then error("no field " .. tostring(p.field)) end
    return {class = p.class, name = p.name, field = p.field, value = describe(value, tonumber(p.depth) or 4)}
end

M.operations.prototype_find = function(_, p)
    p = p or {}
    local query = p.query and tostring(p.query):lower() or nil
    local limit = math.min(math.max(1, tonumber(p.limit) or 100), 1000)
    local out = {}
    local total = 0
    local classes = p.class and {p.class} or class_names()
    for _, class in ipairs(classes) do
        local set = safe(function() return prototypes_for(class) end)
        if set then
            for name, proto in pairs(set) do
                if query == nil or tostring(name):lower():find(query, 1, true) then
                    total = total + 1
                    if #out < limit then
                        out[#out + 1] = {class = class, name = tostring(name), type = prototype_type(proto)}
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.class == b.class then return a.name < b.name end
        return a.class < b.class
    end)
    return {prototypes = out, total = total, truncated = total > #out}
end

M.operations.lua = function(_, p)
    p = p or {}
    local code = p.code
    if type(code) ~= "string" or code == "" then error("code is required") end
    local loader = load or loadstring
    if type(loader) ~= "function" then error("this game build does not expose a Lua loader") end
    local fn, err = loader(code, "=(multi-manager-debug)")
    if not fn then error("Lua compile error: " .. tostring(err)) end
    local ok, value = pcall(fn, p.args or {})
    if not ok then error("Lua runtime error: " .. tostring(value)) end
    return {ok = true, result = describe(value, tonumber(p.depth) or 4)}
end

return M
