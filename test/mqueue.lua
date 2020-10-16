local lu = require 'luaunit'
local process = require 'process'
local xpgsql = require 'xpgsql'
local xtest = require 'test.xtest'
local App = require 'web.App'

local function call_expire(app)
  assert(app:db(function(c)
    assert(c:exec([[ CALL web_pkg_mqueue_expire () ]]))
    return true
  end))
end

local M = {}

function M:setup()
  xtest.extrasetup(self)
end

function M:teardown()
  xtest.extrateardown(self)
end

function M:beforeAll()
  local ok, cleanup, err = xtest.newdb('', xtest.mockcron)
  if not ok then cleanup() end
  assert(ok, err)

  self.cleanup = cleanup
end

function M:afterAll()
  self.cleanup()
end

function M.test_mqueue()
  local app = App{
    database = {connection_string = ''},
    mqueue = {
      default_max_age = 1,
      default_max_attempts = 2,
    },
  }

  app.main = function()
    -- dequeue when queue is empty
    local v, err = app:mqueue({queue = 'q'})
    lu.assertNil(err)
    lu.assertIsTable(v)
    lu.assertEquals(#v, 0)

    -- enqueue a message
    v, err = app:mqueue({
      queue = 'q',
      ref_id = 1,
    }, nil, {x='a'})
    lu.assertNil(err)
    lu.assertTrue(v)

    -- dequeue that message back
    v, err = app:mqueue({queue = 'q'})
    lu.assertNil(err)
    lu.assertEquals(#v, 1)
    lu.assertEquals(v[1].ref_id, 1)
    lu.assertEquals(v[1].attempts, 0) -- attempts completed at this point
    lu.assertIsNumber(v[1].id)
    lu.assertIsTable(v[1].payload)
    lu.assertEquals(v[1].payload.x, 'a')
    local original_id = v[1].id

    -- dequeue again, queue is now empty
    v, err = app:mqueue({queue = 'q'})
    lu.assertNil(err)
    lu.assertEquals(#v, 0)

    -- wait a bit and call expire, message moves back to pending
    process.sleep(2)
    call_expire(app)

    v, err = app:mqueue({queue = 'q'})
    lu.assertNil(err)
    lu.assertEquals(#v, 1)
    lu.assertEquals(v[1].ref_id, 1)
    lu.assertEquals(v[1].attempts, 1)
    lu.assertIsNumber(v[1].id)
    lu.assertIsTable(v[1].payload)
    lu.assertEquals(v[1].payload.x, 'a')

    -- wait a bit and call expire, message moves to dead
    process.sleep(2)
    call_expire(app)

    v, err = app:mqueue({queue = 'q'})
    lu.assertNil(err)
    lu.assertEquals(#v, 0)

    local rows = app:db(function(c)
      return xpgsql.models(assert(c:query(
        'SELECT * FROM web_pkg_mqueue_dead'
      )))
    end)
    lu.assertEquals(#rows, 1)
    lu.assertEquals(tonumber(rows[1].id), original_id)
    lu.assertEquals(tonumber(rows[1].attempts), 2)

    -- enqueue a few in q1, a few in q2
    for _, q in ipairs{'q1', 'q2'} do
      for i = 1, 3 do
        v, err = app:mqueue({
          queue = q,
          ref_id = i,
        }, nil, {x=i})
        lu.assertNil(err)
        lu.assertTrue(v)
      end
    end

    -- use an explicit connection
    local conn = app:db()

    -- get two messages from q1
    v, err = app:mqueue({queue = 'q1', max_receive = 2}, conn)

    -- conn is not closed
    local ok, e2 = conn:query[[ SELECT 1 ]]
    lu.assertNil(e2)
    lu.assertNotNil(ok)
    conn:close()

    lu.assertNil(err)
    lu.assertEquals(#v, 2)
    lu.assertEquals(v[1].ref_id, 1)
    lu.assertEquals(v[2].ref_id, 2)

    -- get 10 messages from q2, has only 3
    v, err = app:mqueue({queue = 'q2', max_receive = 10})
    lu.assertNil(err)
    lu.assertEquals(#v, 3)
    lu.assertEquals(v[1].ref_id, 1)
    lu.assertEquals(v[2].ref_id, 2)
    lu.assertEquals(v[3].ref_id, 3)

    -- get the other message from q1
    v, err = app:mqueue({queue = 'q1'})
    lu.assertNil(err)
    lu.assertEquals(#v, 1)
    lu.assertEquals(v[1].ref_id, 3)

    -- mark it as done
    v, err = app:db(function(c)
      return v[1]:done(c)
    end)
    lu.assertNil(err)
    lu.assertNotNil(v)

    -- wait a bit and call expire, messages move back to pending
    -- except the one that is done.
    process.sleep(2)
    call_expire(app)

    v, err = app:mqueue({queue = 'q1', max_receive = 10})
    lu.assertNil(err)
    lu.assertEquals(#v, 2)
    lu.assertEquals(v[1].ref_id, 1)
    lu.assertEquals(v[2].ref_id, 2)

    -- no messages from q1 in the dead table
    rows = app:db(function(c)
      return xpgsql.models(assert(c:query(
        "SELECT * FROM web_pkg_mqueue_dead WHERE queue = 'q1'"
      )))
    end)
    lu.assertEquals(#rows, 0)
  end

  app:run()
end

return M
