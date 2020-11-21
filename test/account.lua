local lu = require 'luaunit'
local xtest = require 'test.xtest'
local App = require 'web.App'

local M = {}

function M:setup()
  xtest.extrasetup(self)
end

function M:teardown()
  xtest.extrateardown(self)
end

function M:beforeAll()
  local ok, cleanup, err = xtest.newdb('')
  if not ok then cleanup() end
  assert(ok, err)

  self.cleanup = cleanup
end

function M:afterAll()
  self.cleanup()
end

function M.test_account_methods()
  local app = App{
    database = {
      connection_string = '',
      pool = {},
      migrations = {
        {
          package = 'test.account',
          after = {'web.pkg.account'};
          [[
            INSERT INTO
              "web_pkg_account_groups" ("name")
            VALUES
              ('a'), ('b'), ('c')
          ]],
        },
      },
    },
    account = {},
  }

  app.main = function()
    -- create an account
    local acct1, err = app:create_account('U1@a.b', 'pwd')
    lu.assertNil(err)
    lu.assertIsNumber(acct1.id)
    lu.assertEquals(acct1.email, 'u1@a.b')
    lu.assertIsString(acct1.password)
    lu.assertFalse(acct1.verified)
    lu.assertEquals(acct1.groups, {})

    -- create another account with some initial groups
    local acct2; acct2, err = app:create_account('U2@a.b', 'pwd', {'a', 'b'})
    lu.assertNil(err)
    lu.assertIsNumber(acct2.id)
    lu.assertEquals(acct2.email, 'u2@a.b')
    lu.assertIsString(acct2.password)
    lu.assertFalse(acct2.verified)
    lu.assertItemsEquals(acct2.groups, {'a', 'b'})

    -- create a duplicate account
    local acct; acct, err = app:create_account('u1@A.b', 'pwd')
    lu.assertNil(acct)
    lu.assertStrContains(err, 'duplicate key')

    -- lookup by email
    acct, err = app:account('u1@a.b')
    lu.assertNil(err)
    lu.assertEquals(acct, acct1)

    -- lookup by id with invalid password
    acct, err = app:account(acct2.id, 'not pwd')
    lu.assertNil(acct)
    lu.assertStrContains(err, 'invalid credentials')

    -- lookup by id with valid password
    acct, err = app:account(acct2.id, 'pwd')
    lu.assertNil(err)
    lu.assertEquals(acct, acct2)

    -- create account with invalid group
    acct, err = app:create_account('U3@a.b', 'pwd', {'a', 'd'})
    lu.assertNil(acct)
    lu.assertStrContains(err, 'null value')

    -- add account a and c, remove b and d
    local conn = app:db()
    local ok; ok, err = acct2:change_groups({'a', 'c'}, {'b', 'd'}, conn)
    lu.assertNil(err)
    lu.assertTrue(ok)
    lu.assertItemsEquals(acct2.groups, {'a', 'c'})

    -- add account d
    ok, err = acct2:change_groups('d', nil, conn)
    lu.assertNil(ok)
    lu.assertStrContains(err, 'null value')
    lu.assertItemsEquals(acct2.groups, {'a', 'c'})

    -- change email
    ok, err = acct1:change_email('U3@b.c', conn)
    lu.assertNil(err)
    lu.assertTrue(ok)
    lu.assertEquals(acct1.email, 'u3@b.c')

    -- change password
    ok, err = acct1:change_pwd('pwd2', conn)
    lu.assertNil(err)
    lu.assertTrue(ok)

    -- validate with old password fails
    acct, err = app:account('U3@b.c', 'pwd')
    lu.assertNil(acct)
    lu.assertStrContains(err, 'invalid credentials')

    -- with new password works
    acct, err = app:account('U3@b.c', 'pwd2')
    lu.assertNil(err)
    lu.assertEquals(acct.id, acct1.id)

    -- verify email of acct2
    ok, err = acct2:verify_email(conn)
    lu.assertNil(err)
    lu.assertTrue(ok)
    lu.assertTrue(acct2.verified)

    -- delete acct2
    ok, err = acct2:delete(conn)
    lu.assertNil(err)
    lu.assertTrue(ok)

    -- cannot look it up anymore
    acct, err = app:account(acct2.id)
    lu.assertNil(acct)
    lu.assertStrContains(err, 'does not exist')

    acct, err = app:account('u2@b.c')
    lu.assertNil(acct)
    lu.assertStrContains(err, 'does not exist')

    conn:close()
  end
  app:run()
end

return M
