-- multi-manager-debug :: prototype.lua
-- Generic prototype and Lua inspection. The prototype classes are discovered from
-- `prototypes` at runtime; this file does not need an update when a mod adds a class.

local M = {operations = {}}

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

local function class_set(kind)
    if type(kind) ~= "string" or kind == "" then
        error("class is required")
    end
    local set = prototypes[kind]
    if not set then
        error("unknown prototype class: " .. tostring(kind))
    end
    return set
end

local function prototype_name(proto)
    return safe(function() return proto.name end) or "<unknown>"
end

local function prototype_type(proto)
    return safe(function() return proto.type end)
end

local function class_names()
    local names = {}
    for name in pairs(prototypes or {}) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

M.operations.prototype_classes = function()
    local out = {}
    for _, name in ipairs(class_names()) do
        local count = 0
        pcall(function()
            for _ in pairs(prototypes[name]) do count = count + 1 end
        end)
        out[#out + 1] = {class = name, count = count}
    end
    return {classes = out, total = #out}
end

M.operations.prototype_list = function(_, p)
    p = p or {}
    local set = class_set(p.class)
    local names = {}
    for name in pairs(set) do
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
    local set = class_set(p.class)
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
    local set = class_set(p.class)
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
        local set = prototypes[class]
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
