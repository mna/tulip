local fn = require 'fn'
local process = require 'process'
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
function M.newdb(connstr, ...)
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
    conn:exec('DROP DATABASE IF EXISTS ' .. dbname .. ' FORCE')
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

  if not ok then
    return nil, cleanup, err
  end

  -- run any extra setup functions with a connection to the new
  -- database.
  local newconn = xpgsql.connect()
  for i = 1, select('#', ...) do
    ok, err = pcall(select(i, ...), newconn)
    if not ok then
      newconn:close()
      return nil, cleanup, err
    end
  end
  newconn:close()
  return true, cleanup
end

function M.mockcron(conn)
  assert(conn:exec('CREATE SCHEMA cron'))
  assert(conn:exec[[
    CREATE FUNCTION cron.schedule(job_name text, schedule text, command text)
      RETURNS BIGINT
    AS $$
      BEGIN
        RETURN 0;
      END;
    $$ LANGUAGE plpgsql;
  ]])
  assert(conn:exec[[
    CREATE FUNCTION cron.unschedule(job_name text)
      RETURNS BOOLEAN
    AS $$
      BEGIN
        RETURN true;
      END;
    $$ LANGUAGE plpgsql;
  ]])
end

-- Runs function f with a server running in a separate process,
-- and ensures the process is terminated on return. The modname
-- and fname are module and function names as expected by the
-- scripts/run_server.lua script, and extra arguments are passed
-- as-is to the fname in the server process.
--
-- The f function is called with the server's port number as first
-- argument, and a function to call to get output from the server's
-- stderr as second argument (returns nil if there is no output
-- available).
function M.withserver(f, modname, fname, ...)
  local child = assert(process.exec('./scripts/run_server.lua', {
    modname, fname, ...
  }, nil, '.', true))

  -- read until we get the port number
  local port
  local MAX_WAIT = 10
  local start = os.time()
  while not port and (os.difftime(os.time(), start) < MAX_WAIT) do
    local s, err, again = child:stdout()
    if not again and (s or err) ~= nil then
      assert(s, err)
      for ln in string.gmatch(s, '([^\n]+)') do
        port = tonumber(ln)
        if port then break end
      end
    else
      -- check if there's something in stderr
      s = child:stderr()
      if s then error('error in server process: ' .. s) end
      process.sleep(1)
    end
  end
  assert(port, 'could not read port number from the server process')

  -- make sure the server is running
  process.sleep(1)

  -- call the function with the port number as argument
  local ok, err = pcall(f, port, function()
    local start = os.time()
    while os.difftime(os.time(), start) < MAX_WAIT do
      local s, err, again = child:stderr()
      if s then return s end
      if again then
        process.sleep(1)
      else
        if err then return err end
        return
      end
    end
  end)
  -- always terminate the server
  local err2 = child:kill(9)
  assert(ok, err)
  if err2 then error(err2) end
end

return M
