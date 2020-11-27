local cqueues = require 'cqueues'
local lu = require 'luaunit'
local App = require 'web.App'

local M = {}

function M.test_pubsub_ok()
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
    lu.assertStrContains(tostring(err), 'channel is invalid')

    -- register another handler for channel 'b'
    ok, err = app:pubsub('b', function(n)
      lu.assertIsTable(n)
      lu.assertEquals(n.channel, 'b')
      lu.assertEquals(n.payload.x, 7)
      n:terminate()
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

-- TODO: cannot be tested like that, this invalidates the fd of the
-- listening socket and the cqueue:loop call fails instead. Not sure
-- how it can be tested, nor if that should in fact be handled
-- somehow. To investigate more closely later, not a high-priority
-- feature.
function M.SKIP_test_pubsub_err()
  local next_count = 1
  local current_pid

  local app; app = App{
    database = {connection_string = ''},
    pubsub = {
      get_connection = function()
        local conn = app:db()
        local res = assert(conn:query([[SELECT pg_backend_pid()]]))
        current_pid = tonumber(res[1][1])
        return conn
      end,
      error_handler = function(conn, count, _, getconn)
        lu.assertEquals(count, next_count)
        next_count = next_count + 1

        conn:close()
        return getconn()
      end,
    },
  }

  local kill_pid = function()
    assert(app:db(function(c)
      assert(c:query(string.format([[SELECT pg_terminate_backend(%d)]], current_pid)))
      return true
    end))
  end


  local notifs_count = 0
  app.main = function()
    -- register a handler for channel 'a'
    local ok, err = app:pubsub('a', function(n)
      lu.assertIsTable(n)
      lu.assertEquals(n.channel, 'a')
      notifs_count = notifs_count + 1

      if n.payload.stop then
        n:terminate()
      end
    end)
    lu.assertNil(err)
    lu.assertTrue(ok)

    -- trigger a notification
    ok, err = app:pubsub('a', nil, {})
    lu.assertNil(err)
    lu.assertTrue(ok)

    cqueues.sleep(1)

    -- kill the connection, should create a new one
    kill_pid()

    -- trigger another notification
    ok, err = app:pubsub('a', nil, {})
    lu.assertNil(err)
    lu.assertTrue(ok)

    -- trigger termination of the pubsub coroutine
    ok, err = app:pubsub('a', nil, {stop=true})
    lu.assertNil(err)
    lu.assertTrue(ok)
  end

  local cq = cqueues.new()
  cq:wrap(function()
    app:run()
  end)
  assert(cq:loop())
  lu.assertIsNumber(current_pid)
  lu.assertEquals(notifs_count, 3)
  lu.assertEquals(next_count, 2)
end

return M
