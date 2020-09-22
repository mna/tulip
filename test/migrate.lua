local lu = require 'luaunit'
local xpgsql = require 'xpgsql'
local xtest = require 'test.xtest'

local migrator = require 'web.core.migrate.migrator'

local M = {}

function M:setup()
  xtest.extrasetup(self)
end

function M:teardown()
  xtest.extrateardown(self)
end

function M:beforeAll()
  local ok, cleanup, err = xtest.newdb()
  if not ok then cleanup() end
  assert(ok, err)

  self.cleanup = cleanup
  self.conn = assert(xpgsql.connect())
end

function M:afterAll()
  self.conn:close()
  self.cleanup()
end

function M:test_migrate()
  -- migrate without any extra package
  local mig = migrator.new()
  local ok, err = mig:run()
  lu.assertNil(err)
  lu.assertTrue(ok)

  local listMigrations = [[
    SELECT
      "version",
      "package"
    FROM
      "web_migrate_migrations"
    ORDER BY
      "created"
  ]]
  local tomodel = function(o)
    o.version = tonumber(o.version)
    return o
  end
  local rows = xpgsql.models(self.conn:query(listMigrations), tomodel)

  lu.assertEquals(#rows, 1)
  lu.assertEquals(rows[1].version, 1)

  -- add a package migration
  local myMigs = {
    'CREATE TABLE my_nums (num INTEGER NOT NULL)',
    'INSERT INTO my_nums (num) VALUES (1)',
  }
  mig:register('my', myMigs)

  -- registering again raises an error
  lu.assertErrorMsgContains('is already registered', function()
    mig:register('my', myMigs)
  end)

  -- running the migrations works and sets the version
  ok, err = mig:run()
  lu.assertNil(err)
  lu.assertTrue(ok)

  rows = xpgsql.models(self.conn:query(listMigrations), tomodel)
  lu.assertEquals(#rows, 2)
  lu.assertEquals(rows[1].version, 1)
  lu.assertEquals(rows[2].version, 2)

  -- adding migrations and re-running runs the new migrations
  table.insert(myMigs, 'INSERT INTO my_nums (num) VALUES (2)')
  ok, err = mig:run()
  lu.assertNil(err)
  lu.assertTrue(ok)

  rows = xpgsql.models(self.conn:query(listMigrations), tomodel)
  lu.assertEquals(#rows, 2)
  lu.assertEquals(rows[1].version, 1)
  lu.assertEquals(rows[2].version, 3)

  -- adding migrations that fail rolls back the entire migration run
  table.insert(myMigs, 'INSERT INTO my_nums (num) VALUES (3)')
  table.insert(myMigs, 'INSERT INTO my_nums (num) VALUES ("FAIL")')
  ok, err = mig:run()
  lu.assertNotNil(err)
  lu.assertNil(ok)

  rows = xpgsql.models(self.conn:query(listMigrations), tomodel)
  lu.assertEquals(#rows, 2)
  lu.assertEquals(rows[1].version, 1)
  lu.assertEquals(rows[2].version, 3)

  -- change the last migration to use a function and not fail
  myMigs[5] = function(conn, ix)
    assert(conn:exec('INSERT INTO my_nums (num) VALUES (4)'))
    lu.assertEquals(ix, 5)
  end

  ok, err = mig:run()
  lu.assertNil(err)
  lu.assertTrue(ok)

  rows = xpgsql.models(self.conn:query(listMigrations), tomodel)
  lu.assertEquals(#rows, 2)
  lu.assertEquals(rows[1].version, 1)
  lu.assertEquals(rows[2].version, 5)

  local res = assert(xpgsql.model(self.conn:query[[
    SELECT
      MAX(num) maxnum
    FROM
      my_nums
  ]]))
  lu.assertEquals(tonumber(res.maxnum), 4)
end

return M
