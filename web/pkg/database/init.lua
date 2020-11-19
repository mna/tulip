local cqueues = require 'cqueues'
local tcheck = require 'tcheck'
local tsort = require 'resty.tsort'
local xpgsql = require 'xpgsql'
local Migrator = require 'web.pkg.database.Migrator'

local function try_from_pool(pool, idle_to, life_to)
  if (not pool) or #pool == 0 then return end

  local now = os.time()
  while #pool > 0 do
    local conn = table.remove(pool, 1)
    if life_to > 0 and os.difftime(now, conn._birth) > life_to then
      -- dispose of conn, too old
      conn:_close()
    elseif idle_to > 0 and os.difftime(now, conn._idle) > idle_to then
      -- dispose of conn, idle for too long
      conn:_close()
    else
      -- conn is good, use it
      conn._idle = nil
      return conn
    end
  end
end

local function make_pooled_close(conn, pool, max_idle)
  local closefn = conn.close
  conn._close = function(self)
    if not self._conn then return end
    pool.open = pool.open - 1
    assert(pool.open >= 0, 'negative count for pool.open')
    closefn(self)
  end

  return function(self)
    if #pool >= max_idle then
      self:_close()
      return
    end
    self._idle = os.time()
    table.insert(pool, self)
  end
end

local function make_db(cfg, app)
  local connstr = cfg.connection_string
  local idle_to = (cfg.pool and cfg.pool.idle_timeout) or 0
  local life_to = (cfg.pool and cfg.pool.life_timeout) or 0
  local max_idle = (cfg.pool and cfg.pool.max_idle) or 2
  local max_open = (cfg.pool and cfg.pool.max_open) or 0
  local pool = cfg.pool and {open = 0}

  if pool then
    app:register_finalizer('web.pkg.database', function()
      for _, c in ipairs(pool) do
        c:_close()
      end
    end)
  end

  return function(_, fn, ...)
    local conn = try_from_pool(pool, idle_to, life_to)

    if max_open > 0 and pool.open >= max_open then
      -- try again in a second, before giving up
      cqueues.sleep(1)
      conn = try_from_pool(pool)
      assert(conn, 'too many open connections')
    end

    if not conn then
      conn = assert(xpgsql.connect(connstr))
      if pool then
        conn.close = make_pooled_close(conn, pool, max_idle)
        conn._birth = os.time()
        pool.open = pool.open + 1
      end
    end
    if not fn then return conn end
    return conn:with(true, fn, ...)
  end
end

local M = {}

-- The database package registers a db function on the app that
-- returns a connection when called. If a function is provided as
-- argument, that function is called with the connection, which is
-- then released automatically when the function is done, regardless
-- of whether an error was raised or not, and the call returns the
-- return values of the function or nil and the error message.
--
-- It also runs the migrator, which runs when the app is
-- started, executing all registered migrations from the config.
--
-- Config:
--   * connection_string: string = the connection string
--   * migrations: array of tables = the migrations to run, each
--     table being an array of migration steps (string or function,
--     as described in the Migrator) with a 'package' field that
--     identifies for which package the migrations apply, and an
--     optional 'after' field that identifies package names (array
--     of strings) that must have their migrations run before this package.
--   * pool: table = if set, configures a connection pool so that
--     calling App:db returns a pooled connection if available,
--     and calling conn:close returns it to the pool if possible.
--     The fields are max_idle, max_open, idle_timeout and
--     life_timeout. Defaults are respectively 2, 0 (unlimited),
--     0 (no timeout) and 0 (no timeout).
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  app.db = make_db(cfg, app)
end

function M.activate(app)
  tcheck('web.App', app)

  local cfg = app.config.database
  cfg.migrations = cfg.migrations or {}

  local graph = tsort.new()
  local migrations = {}
  for _, v in ipairs(cfg.migrations) do
    local ms = migrations[v.package] or {}
    for _, m in ipairs(v) do
      table.insert(ms, m)
    end
    migrations[v.package] = ms
    if v.after then
      for _, from in ipairs(v.after) do
        graph:add(from, v.package)
      end
    else
      graph:add(v.package)
    end
  end

  local mig = Migrator.new(cfg.connection_string)
  for pkg, ms in pairs(migrations) do
    mig:register(pkg, ms)
  end

  local order = graph:sort()
  if not order then
    error('circular dependency in database migrations')
  end

  app:log('i', {pkg = 'database', msg = 'migrations started'})
  assert(app:db(function(conn)
    return assert(mig:run(conn, function(pkg, i)
      app:log('i', {pkg = 'database', migration = string.format('%s:%d', pkg, i), msg = 'applying migration'})
    end, order))
  end))
  app:log('i', {pkg = 'database', msg = 'migrations done'})
end

return M
