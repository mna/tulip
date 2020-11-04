local auxlib = require 'cqueues.auxlib'
local cqueues = require 'cqueues'
local condition = require 'cqueues.condition'
local lu = require 'luaunit'
local socket = require 'cqueues.socket'
local App = require 'web.App'

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
      lu.assertStrContains(err, '"d" is invalid')

      -- use an invalid metric type
      ok, err = app:metrics('a', 'zzz')
      lu.assertNil(ok)
      lu.assertStrContains(err, '"zzz" is invalid')

      -- valid call, defaults to 1
      ok, err = app:metrics('a', 'counter')
      lu.assertNil(err)
      lu.assertTrue(ok)

      -- valid call, explicit value
      ok, err = app:metrics('b', 'gauge', 10)
      lu.assertNil(err)
      lu.assertTrue(ok)

      -- valid call, sampled
      ok, err = app:metrics('c', 'counter', 2, {['@'] = 0.1})
      lu.assertNil(err)
      lu.assertTrue(ok)

      -- valid call, tags
      ok, err = app:metrics('c', 'counter', 3, {x='i', y='ii'})
      lu.assertNil(err)
      lu.assertTrue(ok)

      -- valid call, tags and sampled
      ok, err = app:metrics('c', 'counter', 3, {['@'] = 0.9, x='i', y='ii'})
      lu.assertNil(err)
      lu.assertTrue(ok)

      ok = cond:wait(1)
      lu.assertTrue(ok)
      local inspect = require 'inspect'
      print('>>> ', inspect(received))
    end)
    cq:loop()
  end

  app:run()
end

return M
