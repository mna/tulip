#!/usr/bin/env -S llrocks run

local cqueues = require 'cqueues'
local xpgsql = require 'xpgsql'

local all = arg[1] and arg[1] == 'all'

local SQL_TESTDB = [[
SELECT
  datname
FROM
  pg_database
WHERE
  (NOT datistemplate) AND
  datname LIKE 'testtulip%'
]]

local SQL_DROPDB = [[
DROP DATABASE %s WITH (FORCE)
]]

local SQL_TESTUSER = [[
SELECT
  usename
FROM
  pg_user
WHERE
  (NOT usesuper) AND
  usename LIKE 'testtulip%'
]]

local SQL_DROPUSER = [[
DROP USER %s
]]

local SQL_CREATEDB = [[
CREATE DATABASE %s
]]

local SQL_CREATECRON = [[
CREATE EXTENSION pg_cron
]]

local maindb = os.getenv('PGDATABASE')
local tempdb = 'testtulip' .. string.gsub(tostring(cqueues.monotime()), '%.', '_')

local conn = assert(xpgsql.connect())
assert(conn:with(true, function()
  local dbs = xpgsql.models(assert(conn:query(SQL_TESTDB)))
  io.write(string.format('deleting %d test databases...\n', #dbs))
  for _, db in ipairs(dbs) do
    assert(conn:exec(string.format(SQL_DROPDB, db.datname)))
  end
  io.write(string.format('deleted %d test databases\n', #dbs))

  local users = xpgsql.models(assert(conn:query(SQL_TESTUSER)))
  io.write(string.format('deleting %d test users\n', #users))
  for _, user in ipairs(users) do
    assert(conn:exec(string.format(SQL_DROPUSER, user.usename)))
  end
  io.write(string.format('deleted %d test users\n', #users))

  if all then
    io.write(string.format('re-creating main database %s\n', maindb))
    assert(conn:exec(string.format(SQL_CREATEDB, tempdb)))
  end

  return true
end))

if all then
  -- now connect to the tempdb and drop the main and re-create it
  conn = assert(xpgsql.connect('dbname=' .. tempdb))
  assert(conn:with(true, function()
    assert(conn:exec(string.format(SQL_DROPDB, maindb)))
    assert(conn:exec(string.format(SQL_CREATEDB, maindb)))
    return true
  end))

  -- and finally, re-connect to the main and drop the temp
  conn = assert(xpgsql.connect())
  assert(conn:with(true, function()
    assert(conn:exec(string.format(SQL_DROPDB, tempdb)))
    assert(conn:exec(SQL_CREATECRON))
    return true
  end))
  io.write(string.format('re-created main database %s\n', maindb))
end
