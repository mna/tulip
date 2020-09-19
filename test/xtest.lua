local fn = require 'fn'
local stdlib = require 'posix.stdlib'
local xpgsql = require 'xpgsql'

local M = {}

-- When called inside the setup step of a test table, enables the
-- beforeAll step. Use with extrateardown for afterAll.
function M.extrasetup(t)
  if not t._count then
    local p = fn.pipe(
      fn.filter(function(k) return string.match(k, '^test') end),
      fn.filter(function(_, v) return type(v) == 'function' end)
    )
    t._tests = fn.reduce(function(c) return c + 1 end, 0, p(pairs(t)))
    t._count = 0

    if t.beforeAll then t.beforeAll(t) end
  end
  t._count = t._count + 1
end

-- When called inside the teardown step of a test table, enables the
-- afterAll step. Use with extrasetup for beforeAll.
function M.extrateardown(t)
  if t._count and t._count == t._tests then
    if t.afterAll then t.afterAll(t) end
  end
end

-- This function creates a test database. It returns true on success,
-- along with a function to call to delete the temporary database.  If it
-- fails, it returns nil followed by the cleanup function and an error
-- message.
function M.newdb(connstr)
  local oldpwd = os.getenv('PGPASSWORD')
  if not oldpwd or oldpwd == '' then
    io.input('run/secrets/pgroot_pwd')
    stdlib.setenv('PGPASSWORD', assert(io.read()))
  end

  local conn = assert(xpgsql.connect(connstr))
  local dbname = 'testweb' .. tostring(os.time())

  local olddb = os.getenv('PGDATABASE')
  local olduser = os.getenv('PGUSER')
  local cleanup = function()
    conn:exec('DROP DATABASE IF EXISTS ' .. dbname)
    conn:exec('DROP USER IF EXISTS ' .. dbname)
    conn:close()

    -- reset the pg env vars
    stdlib.setenv('PGPASSWORD', oldpwd)
    stdlib.setenv('PGDATABASE', olddb)
    stdlib.setenv('PGUSER', olduser)
  end

  -- set the new pg env vars
  stdlib.setenv('PGPASSWORD', dbname)
  stdlib.setenv('PGDATABASE', dbname)
  stdlib.setenv('PGUSER', dbname)
  local ok, err = pcall(function()
    assert(conn:exec('CREATE DATABASE ' .. dbname))
    -- create test user for this database, with the same name
    assert(conn:exec("CREATE USER " .. dbname .. " WITH PASSWORD '" .. dbname .. "'"))
    assert(conn:exec('GRANT ALL PRIVILEGES ON DATABASE ' .. dbname .. ' TO ' .. dbname))
    return true
  end)

  if ok then
    return true, cleanup
  end
  return nil, cleanup, err
end

return M
