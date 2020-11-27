local lu = require 'luaunit'
local process = require 'process'
local xtest = require 'test.xtest'
local xpgsql = require 'xpgsql'
local App = require 'web.App'

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

function M.test_token()
  local app = App{
    database = { connection_string = '' },
    token = {},
  }
  app.main = function()
    local ok, id
    local tok, err = app:token({
      type = 'test',
      ref_id = 1,
      once = true,
      max_age = 10,
    })
    lu.assertNil(err)
    lu.assertTrue(tok and #tok == 44) -- encoded length = 44

    -- validating works
    ok, id = app:token({
      type = 'test',
      ref_id = 1,
    }, nil, tok)
    lu.assertTrue(ok)
    lu.assertEquals(id, 1)

    -- once used, cannot be reused
    ok, err = app:token({
      type = 'test',
      ref_id = 1,
    }, nil, tok)
    lu.assertNil(err)
    lu.assertFalse(ok)

    -- generate a new one with a short validity
    tok, err = app:token({
      type = 'test',
      once = true,
      ref_id = 1,
      max_age = 1,
    })
    lu.assertNil(err)
    lu.assertTrue(tok and #tok == 44)

    -- wait for expiration
    process.sleep(2)

    -- validating reports false, despite valid type and id
    ok, err = app:token({
      type = 'test',
      ref_id = 1,
    }, nil, tok)
    lu.assertNil(err)
    lu.assertFalse(ok)

    -- at this point the table should be empty (both tokens
    -- consumed and deleted)
    local conn = xpgsql.connect()
    local res = assert(conn:query[[
      SELECT COUNT(*) FROM "web_pkg_token_tokens"
    ]])
    conn:close()
    lu.assertEquals(res[1][1], '0')

    -- generate a new short-lived one
    tok, err = app:token({
      type = 'test',
      ref_id = 2,
      once = true,
      max_age = 1,
    })
    lu.assertNil(err)
    lu.assertTrue(tok and #tok == 44)

    -- let it expire
    process.sleep(1)
    local expired = tok

    -- generate one for the same id again, long-lived
    tok, err = app:token({
      type = 'test',
      once = true,
      ref_id = 2,
      max_age = 120,
    })
    lu.assertNil(err)
    lu.assertTrue(tok and #tok == 44)

    -- it generated a different one
    lu.assertNotEquals(tok, expired)
    -- wait a bit, it should not expire
    process.sleep(1)

    -- validating works
    ok, id = app:token({
      type = 'test',
      ref_id = 2,
    }, nil, tok)
    lu.assertTrue(ok)
    lu.assertEquals(id, 2)

    -- generate another valid one
    tok, err = app:token({
      type = 'test',
      ref_id = 3,
      once = true,
      max_age = 120,
    })
    lu.assertNil(err)
    lu.assertTrue(tok and #tok == 44)

    -- validating with wrong type/id
    ok, err = app:token({
      type = 'nottest',
      ref_id = 0,
    }, nil, tok)
    lu.assertNil(err)
    lu.assertFalse(ok)

    -- token has been consumed, so does not work anymore
    ok, err = app:token({
      type = 'test',
      ref_id = 3,
    }, nil, tok)
    lu.assertNil(err)
    lu.assertFalse(ok)

    -- at this point the table should be empty
    conn = xpgsql.connect()
    res = assert(conn:query[[
      SELECT COUNT(*) FROM "web_pkg_token_tokens"
    ]])
    conn:close()
    lu.assertEquals(res[1][1], '0')

    -- generate a multi-use token
    tok, err = app:token({
      type = 'ssn',
      ref_id = 4,
      max_age = 2,
    })
    lu.assertNil(err)
    lu.assertTrue(tok and #tok == 44)

    -- validating returns the ref_id
    ok, id = app:token({
      type = 'ssn',
    }, nil, tok)
    lu.assertTrue(ok)
    lu.assertEquals(id, 4)

    -- works more than once
    ok, id = app:token({
      type = 'ssn',
    }, nil, tok)
    lu.assertTrue(ok)
    lu.assertEquals(id, 4)

    -- let it expire
    process.sleep(2)

    -- not valid anymore
    ok, id = app:token({
      type = 'ssn',
    }, nil, tok)
    lu.assertFalse(ok)
    lu.assertNil(id)
  end
  app:run()
end

return M
