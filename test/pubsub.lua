local cqueues = require 'cqueues'
local lu = require 'luaunit'
local App = require 'web.App'

local M = {}

function M.test_pubsub()
  local app = App{
    database = {connection_string = ''},
    pubsub = {
      allowed_channels = {'a', 'b'},
    },
  }

  app.main = function()
    -- publish without listener works
    local ok, err = app:pubsub('a', nil, {x=1})
    lu.assertNil(err)
    lu.assertTrue(ok)

    -- register a handler for channel 'a'
    ok, err = app:pubsub('a', function(n)
      lu.assertIsTable(n)
      lu.assertEquals(n.channel, 'a')
      lu.assertEquals(n.payload.x, 2)
    end)
    lu.assertNil(err)
    lu.assertTrue(ok)

    -- publish with a listener works
    ok, err = app:pubsub('a', nil, {x=2})
    lu.assertNil(err)
    lu.assertTrue(ok)

    -- publish on a channel without listener works
    ok, err = app:pubsub('b', nil, {x=3})
    lu.assertNil(err)
    lu.assertTrue(ok)

    -- register a handler for channel 'b'
    ok, err = app:pubsub('b', function(n)
      lu.assertIsTable(n)
      lu.assertEquals(n.channel, 'b')
      lu.assertTrue(n.payload.x > 3)
    end)
    lu.assertNil(err)
    lu.assertTrue(ok)

    -- publish some notifications on channel b
    ok, err = app:pubsub('b', nil, {x=4})
    lu.assertNil(err)
    lu.assertTrue(ok)
    ok, err = app:pubsub('b', nil, {x=5})
    lu.assertNil(err)
    lu.assertTrue(ok)

    cqueues.sleep(1)

    -- publish on invalid channel fails
    ok, err = app:pubsub('c', nil, {x=6})
    lu.assertNotNil(err)
    lu.assertNil(ok)
    lu.assertStrContains(err, 'channel "c" is invalid')

    -- register another handler for channel 'b'
    ok, err = app:pubsub('b', function(n)
      lu.assertIsTable(n)
      lu.assertEquals(n.channel, 'b')
      lu.assertEquals(n.payload.x, 7)
      return nil, 'stop'
    end)
    lu.assertNil(err)
    lu.assertTrue(ok)

    ok, err = app:pubsub('b', nil, {x=7})
    lu.assertNil(err)
    lu.assertTrue(ok)
  end

  local cq = cqueues.new()
  cq:wrap(function()
    app:run()
  end)
  assert(cq:loop())
end

return M
