-- multi-manager-debug :: selftest.lua
-- In-game self test for the pieces that can only be verified inside the game:
-- the JSON encoder/decoder, the lenient config loader and the RPC dispatcher.
-- Exposed as the /debug-selftest console command (and through the remote
-- interface) so it can run on any server without instrumentation.

local json = require('debug.query.json')
local util = require('debug.query.util')
local config = require('debug.query.config')
local rpc = require('debug.query.rpc')

local selftest = {}

function selftest.run()
  local results = {}
  local function check(name, cond, detail)
    results[#results + 1] = { name = name, pass = cond == true, detail = detail }
  end

  -- ---- JSON encoder -------------------------------------------------------
  local enc = json.encode({ a = 1, b = 'x"y', c = true, d = { 1, 2, 3 }, e = nil })
  check('json.encode is single line', enc:find('\n') == nil, enc)
  check('json.encode escapes quotes', enc:find('\\"') ~= nil, enc)
  check('json.encode emits arrays', enc:find('%[1,2,3%]') ~= nil, enc)
  check('json.encode skips nil members', enc:find('null') == nil, enc)
  check('json.encode number', json.encode(42) == '42', json.encode(42))
  check('json.encode float', json.encode(1.5) == '1.5', json.encode(1.5))
  check('json.encode negative', json.encode(-3) == '-3', json.encode(-3))
  check('json.encode escapes newline', json.encode('a\nb') == '"a\\nb"', json.encode('a\nb'))
  check('json.encode handles NaN', json.encode(0 / 0) == 'null', json.encode(0 / 0))
  check('json.encode deep nesting', (function()
    local deep = { a = { b = { c = { d = { e = 1 } } } } }
    return json.decode(json.encode(deep)).a.b.c.d.e == 1
  end)())

  -- ---- JSON decoder -------------------------------------------------------
  local rt = json.decode(json.encode({ hello = 'world', n = 42, arr = { 'a', 'b' }, nested = { k = false } }))
  check('round trip string', rt.hello == 'world', rt.hello)
  check('round trip number', rt.n == 42, rt.n)
  check('round trip array', rt.arr[2] == 'b', rt.arr[2])
  check('round trip boolean', rt.nested.k == false, tostring(rt.nested.k))
  check('decode single quotes', json.decode("{ 'a': 1 }").a == 1)
  check('decode trailing comma', json.decode('{"a":1,}').a == 1)
  check('decode bare key', json.decode('{a:1}').a == 1)
  check('decode empty input', type(json.decode('')) == 'table')
  check('decode garbage does not throw', pcall(function() return json.decode('@@@ not json @@@') end))
  check('decode nested arrays', json.decode('{"a":[[1,2],[3]]}').a[2][1] == 3)

  -- ---- lenient config -----------------------------------------------------
  local cfg, ok, note = config.load()
  check('config.load returns a table', type(cfg) == 'table' and cfg.external ~= nil, note)
  check('config default port', cfg.external.port == 8081, cfg.external.port)
  check('config default token mode', cfg.external.tokenMode == 'auto', cfg.external.tokenMode)
  check('config default behavior intervals', type(cfg.behavior.highFreqIntervalMs) == 'number', cfg.behavior.highFreqIntervalMs)
  check('config default file editor flag', type(cfg.fileEditor.enabled) == 'boolean', cfg.fileEditor.enabled)
  check('config default ssl block', type(cfg.external.ssl) == 'table', cfg.external.ssl and cfg.external.ssl.keystorePath)
  check('config does not crash on missing file', ok == true or type(note) == 'string', note)

  -- ---- console commands ---------------------------------------------------
  -- commands.commands is a userdata dictionary: keyed access works, `pairs` on
  -- it yields nothing, so probe each name directly.
  for _, name in ipairs({ 'debug-rpc', 'debug-health', 'debug-tools', 'debug-selftest' }) do
    check('command registered: /' .. name, commands.commands[name] ~= nil)
  end

  -- ---- rpc dispatcher -----------------------------------------------------
  check('rpc has 37 tools', rpc.COUNT == 37, rpc.COUNT)
  local unknown = json.decode(rpc.call('definitely_not_a_tool', '{}'))
  check('rpc rejects unknown tools', unknown.ok == false, unknown.error)
  local bad_args = json.decode(rpc.call('get_server_status', 'this is not json'))
  check('rpc survives malformed arguments', bad_args.ok == true, bad_args.error)
  local status = json.decode(rpc.call('get_server_status', '{}'))
  check('rpc returns the tool envelope', status.ok == true and status.tool == 'get_server_status', status.error)
  check('rpc envelope carries the tick', type(status.tick) == 'number', status.tick)
  check('rpc data has server fields', type(status.data) == 'table' and status.data.forces ~= nil)
  local file_status = json.decode(rpc.call('get_file_editor_status', '{}'))
  check('rpc file editor status', file_status.ok == true and file_status.data.capabilities ~= nil)
  local console = json.decode(rpc.call('get_console_command_list', '{}'))
  check('rpc console command list', console.ok == true and console.data.count >= 3, console.data and console.data.count)

  -- ---- utilities ----------------------------------------------------------
  check('util.round', util.round(1.23456, 2) == 1.23, util.round(1.23456, 2))
  check('util.clamp', util.clamp(99, 1, 10) == 10 and util.clamp(-5, 1, 10) == 1)
  check('util.position', (function()
    local p = util.position({ x = 1.23456, y = -2.5 })
    return p ~= nil and p.x == 1.235 and p.y == -2.5
  end)())
  check('util.each_custom walks userdata', (function()
    local n = 0
    for _ in util.each_custom(game.surfaces) do n = n + 1 end
    return n >= 1
  end)())

  local passed, failed = 0, 0
  for _, r in ipairs(results) do
    if r.pass then passed = passed + 1 else failed = failed + 1 end
  end
  return {
    passed = passed,
    failed = failed,
    total = #results,
    success = failed == 0,
    results = results,
    factorioVersion = util.try(function() return script.active_mods['base'] end, 'unknown'),
    tick = game.tick,
  }
end

function selftest.to_text(report)
  local lines = { string.format('debug-selftest: %d/%d passed (%d failed) on Factorio %s',
    report.passed, report.total, report.failed, report.factorioVersion) }
  for _, r in ipairs(report.results) do
    lines[#lines + 1] = string.format('  [%s] %s%s', r.pass and 'PASS' or 'FAIL', r.name,
      (not r.pass and r.detail) and (' -> ' .. tostring(r.detail)) or '')
  end
  return table.concat(lines, '\n')
end

return selftest
