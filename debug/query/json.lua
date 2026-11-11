-- multi-manager-debug :: json.lua
-- Dependency-free JSON encoder/decoder tuned for the Factorio Lua sandbox.
-- The encoder only ever emits compact, single-line output so the result can be
-- handed straight to rcon.print() without breaking the RCON line framing.

local json = {}

local escape_map = {
  ['"'] = '\\"',
  ['\\'] = '\\\\',
  ['\b'] = '\\b',
  ['\f'] = '\\f',
  ['\n'] = '\\n',
  ['\r'] = '\\r',
  ['\t'] = '\\t',
}

local function escape_string(s)
  return (s:gsub('[%z\1-\31\\"]', function(c)
    local mapped = escape_map[c]
    if mapped then return mapped end
    return string.format('\\u%04x', string.byte(c))
  end))
end
json.escape_string = escape_string

local function is_array(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= 'number' then return false end
    n = n + 1
  end
  if n == 0 then return false end -- empty tables encode as {} (object)
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true
end

local encode_value

local function encode_number(n)
  if n ~= n or n == math.huge or n == -math.huge then return 'null' end
  if n == math.floor(n) and math.abs(n) < 1e15 then
    return string.format('%d', n)
  end
  local s = string.format('%.6f', n)
  s = s:gsub('0+$', ''):gsub('%.$', '')
  return s
end

encode_value = function(v, out, depth)
  local tv = type(v)
  if v == nil then
    out[#out + 1] = 'null'
  elseif tv == 'boolean' then
    out[#out + 1] = v and 'true' or 'false'
  elseif tv == 'number' then
    out[#out + 1] = encode_number(v)
  elseif tv == 'string' then
    out[#out + 1] = '"' .. escape_string(v) .. '"'
  elseif tv == 'table' then
    local marker = rawget(v, '__json')
    if marker ~= nil then
      -- wrapper: {__json = <preencoded string>}
      out[#out + 1] = tostring(marker)
      return
    end
    if depth > 12 then
      out[#out + 1] = 'null'
      return
    end
    if is_array(v) then
      out[#out + 1] = '['
      local n = #v
      for i = 1, n do
        if i > 1 then out[#out + 1] = ',' end
        encode_value(v[i], out, depth + 1)
      end
      out[#out + 1] = ']'
    else
      out[#out + 1] = '{'
      local first = true
      -- deterministic ordering: sorted keys
      local keys = {}
      for k in pairs(v) do
        local tk = type(k)
        if tk == 'string' or tk == 'number' then
          if not (tk == 'string' and k:sub(1, 2) == '__') then
            keys[#keys + 1] = tostring(k)
          end
        end
      end
      table.sort(keys)
      for _, k in ipairs(keys) do
        local val = v[k]
        if val == nil then
          -- tolerate numeric-string keys produced above
          val = rawget(v, tonumber(k))
        end
        if val ~= nil then
          if not first then out[#out + 1] = ',' end
          first = false
          out[#out + 1] = '"' .. escape_string(k) .. '":'
          encode_value(val, out, depth + 1)
        end
      end
      out[#out + 1] = '}'
    end
  else
    -- userdata / function: never leak the raw value
    out[#out + 1] = '"<' .. tv .. '>"'
  end
end

--- Encode a Lua value to a compact single-line JSON string.
function json.encode(v)
  local out = {}
  encode_value(v, out, 0)
  return table.concat(out)
end

--- Wrap an already encoded JSON fragment so it is embedded verbatim.
function json.raw(preencoded)
  return { __json = tostring(preencoded) }
end

-- ---------------------------------------------------------------------------
-- Decoder. Small recursive-descent parser; lenient by design:
--   * trailing commas are tolerated
--   * single quoted strings are tolerated
--   * bare words (unquoted keys / values) are tolerated
-- ---------------------------------------------------------------------------

local function skip_ws(s, i)
  while true do
    local c = s:sub(i, i)
    if c == ' ' or c == '\t' or c == '\n' or c == '\r' then i = i + 1 else return i end
  end
end

local decode_value

local function decode_string(s, i, quote)
  local buf = {}
  i = i + 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == '\\' then
      local e = s:sub(i + 1, i + 1)
      if e == 'n' then buf[#buf + 1] = '\n'
      elseif e == 't' then buf[#buf + 1] = '\t'
      elseif e == 'r' then buf[#buf + 1] = '\r'
      elseif e == 'b' then buf[#buf + 1] = '\b'
      elseif e == 'f' then buf[#buf + 1] = '\f'
      elseif e == 'u' then
        local hex = s:sub(i + 2, i + 5)
        local code = tonumber(hex, 16)
        if code then
          if code < 128 then
            buf[#buf + 1] = string.char(code)
          else
            buf[#buf + 1] = '?'
          end
          i = i + 4
        end
      else
        buf[#buf + 1] = e
      end
      i = i + 2
    elseif c == quote then
      return table.concat(buf), i + 1
    else
      buf[#buf + 1] = c
      i = i + 1
    end
  end
  return table.concat(buf), i
end

local function decode_number(s, i)
  local j = i
  while j <= #s and s:sub(j, j):match('[%d%.eE%+%-]') do j = j + 1 end
  local n = tonumber(s:sub(i, j - 1))
  return n or 0, j
end

local function decode_bare(s, i)
  local j = i
  while j <= #s and not s:sub(j, j):match('[%s,}%]%:]') do j = j + 1 end
  return s:sub(i, j - 1), j
end

decode_value = function(s, i)
  i = skip_ws(s, i)
  local c = s:sub(i, i)
  if c == '{' then
    local obj = {}
    i = skip_ws(s, i + 1)
    if s:sub(i, i) == '}' then return obj, i + 1 end
    while i <= #s do
      i = skip_ws(s, i)
      local key
      local kc = s:sub(i, i)
      if kc == '"' or kc == "'" then
        key, i = decode_string(s, i, kc)
      else
        key, i = decode_bare(s, i)
      end
      i = skip_ws(s, i)
      if s:sub(i, i) == ':' then i = i + 1 end
      local val
      val, i = decode_value(s, i)
      if key ~= '' then obj[key] = val end
      i = skip_ws(s, i)
      local d = s:sub(i, i)
      if d == ',' then
        i = i + 1
      elseif d == '}' then
        return obj, i + 1
      else
        return obj, i
      end
    end
    return obj, i
  elseif c == '[' then
    local arr = {}
    i = skip_ws(s, i + 1)
    if s:sub(i, i) == ']' then return arr, i + 1 end
    while i <= #s do
      local val
      val, i = decode_value(s, i)
      arr[#arr + 1] = val
      i = skip_ws(s, i)
      local d = s:sub(i, i)
      if d == ',' then
        i = i + 1
      elseif d == ']' then
        return arr, i + 1
      else
        return arr, i
      end
    end
    return arr, i
  elseif c == '"' or c == "'" then
    return decode_string(s, i, c)
  elseif c == 't' and s:sub(i, i + 3) == 'true' then
    return true, i + 4
  elseif c == 'f' and s:sub(i, i + 4) == 'false' then
    return false, i + 5
  elseif c == 'n' and s:sub(i, i + 3) == 'null' then
    return nil, i + 4
  elseif c == '-' or c:match('%d') then
    return decode_number(s, i)
  else
    local bare, j = decode_bare(s, i)
    return bare, j
  end
end

--- Decode a JSON string. Returns value, or nil plus an error message.
function json.decode(s)
  if type(s) ~= 'string' or s == '' then return {} end
  local ok, value = pcall(decode_value, s, 1)
  if not ok then return nil, tostring(value) end
  if type(value) ~= 'table' then return value end
  return value
end

return json
