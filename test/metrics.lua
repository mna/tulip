local auxlib = require 'cqueues.auxlib'
local condition = require 'cqueues.condition'
local lu = require 'luaunit'
local socket = require 'cqueues.socket'
local App = require 'tulip.App'

local M = {}

function M.test_metrics()
  local app = App{
    metrics = {
      allowed_metrics = {'a', 'b', 'c'},
      host = '127.0.0.1',
      port = 10111,
      write_timeout = 1,
    },
  }

  local server = auxlib.assert(socket.listen {
    type = socket.SOCK_DGRAM,
    host = '127.0.0.1',
    port = 10111,
  }:listen())

  app.main = function(_, cq)
    local received = {}
    local cond = condition.new()

    cq:wrap(function()
      while true do
        local s, err = server:xread('*a', 1)
        if (not s) and err then
          -- done receiving
          cond:signal()
          return
        end
        table.insert(received, s)
      end
    end)

    cq:wrap(function()
      -- use an invalid metric name
      local ok, err = app:metrics('d', 'counter')
      lu.assertNil(ok)
      lu.assertStrContains(tostring(err), 'name is invalid')

      -- use an invalid metric type
      lu.assertErrorMsgContains('"zzz" is invalid', function()
        app:metrics('a', 'zzz')
      end)

      local want = {}
      -- valid call, defaults to 1
      ok, err = app:metrics('a', 'counter')
      lu.assertNil(err)
      lu.assertTrue(ok)
      table.insert(want, 'a:1|c')

      -- valid call, explicit value
      ok, err = app:metrics('b', 'gauge', 2)
      lu.assertNil(err)
      lu.assertTrue(ok)
      table.insert(want, 'b:2|g')

      -- valid call, sampled
      ok, err = app:metrics('c', 'counter', 3, {['@'] = 0.5})
      lu.assertNil(err)
      lu.assertTrue(ok)
      table.insert(want, 'c:3|c|@0.5')

      -- valid call, tags
      ok, err = app:metrics('c', 'counter', 4, {x='i', y='ii'})
      lu.assertNil(err)
      lu.assertTrue(ok)
      table.insert(want, 'c#x=i,y=ii:4|c')

      -- valid call, tags and sampled
      ok, err = app:metrics('c', 'counter', 5, {['@'] = 0.9, x='i', y='ii'})
      lu.assertNil(err)
      lu.assertTrue(ok)
      table.insert(want, 'c#x=i,y=ii:5|c|@0.9')


      ok = cond:wait(1)
      lu.assertTrue(ok)

      -- check the received strings, will always have at least 3 results
      lu.assertTrue(#received >= 3)

      -- now check each received string
      for _, v in ipairs(received) do
        local ix = tonumber(string.match(v, ':(%d)|'))
        if ix == 3 then
          print('> wrote the 0.5 sample')
        elseif ix == 5 then
          print('> wrote the 0.9 sample')
        end
        lu.assertEquals(v, want[ix])
      end
    end)
    assert(cq:loop())
  end

  app:run()
end

function M.test_metrics_datadog()
  local app = App{
    metrics = {
      allowed_metrics = {'a', 'b', 'c'},
      host = '127.0.0.1',
      port = 10112,
      format = 'datadog',
      write_timeout = 1,
    },
  }

  local server = auxlib.assert(socket.listen {
    type = socket.SOCK_DGRAM,
    host = '127.0.0.1',
    port = 10112,
  }:listen())

  app.main = function(_, cq)
    local received = {}
    local cond = condition.new()

    cq:wrap(function()
      while true do
        local s, err = server:xread('*a', 1)
        if (not s) and err then
          -- done receiving
          cond:signal()
          return
        end
        table.insert(received, s)
      end
    end)

    cq:wrap(function()
      local want = {}
      -- valid call, defaults to 1
      local ok, err = app:metrics('a', 'counter')
      lu.assertNil(err)
      lu.assertTrue(ok)
      table.insert(want, 'a:1|c')

      -- valid call, explicit value
      ok, err = app:metrics('b', 'gauge', 2)
      lu.assertNil(err)
      lu.assertTrue(ok)
      table.insert(want, 'b:2|g')

      -- valid call, sampled
      ok, err = app:metrics('c', 'counter', 3, {['@'] = 0.5})
      lu.assertNil(err)
      lu.assertTrue(ok)
      table.insert(want, 'c:3|c|@0.5')

      -- valid call, tags
      ok, err = app:metrics('c', 'counter', 4, {x='i', y='ii'})
      lu.assertNil(err)
      lu.assertTrue(ok)
      table.insert(want, 'c:4|c|#x:i,y:ii')

      -- valid call, tags and sampled
      ok, err = app:metrics('c', 'counter', 5, {['@'] = 0.9, x='i', y='ii'})
      lu.assertNil(err)
      lu.assertTrue(ok)
      table.insert(want, 'c:5|c|@0.9|#x:i,y:ii')

      ok = cond:wait(1)
      lu.assertTrue(ok)

      -- check the received strings, will always have at least 3 results
      lu.assertTrue(#received >= 3)

      -- now check each received string
      for _, v in ipairs(received) do
        local ix = tonumber(string.match(v, ':(%d)|'))
        if ix == 3 then
          print('> wrote the 0.5 sample')
        elseif ix == 5 then
          print('> wrote the 0.9 sample')
        end
        lu.assertEquals(v, want[ix])
      end
    end)
    assert(cq:loop())
  end

  app:run()
end

return M
