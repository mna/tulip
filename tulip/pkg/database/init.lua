local cqueues = require 'cqueues'
local tcheck = require 'tcheck'
local tsort = require 'resty.tsort'
local xerror = require 'tulip.xerror'
local xpgsql = require 'xpgsql'
local xtable = require 'tulip.xtable'
local Migrator = require 'tulip.pkg.database.Migrator'

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
    xerror.must(pool.open >= 0, 'negative count for pool.open')
    closefn(self)
  end

  return function(self)
    if #pool >= max_idle then
      return self:_close()
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
    app:register_finalizer('tulip.pkg.database', function()
      for _, c in ipairs(pool) do
        c:_close()
      end
    end)
  end

  return function(_, fn, ...)
    local conn = try_from_pool(pool, idle_to, life_to)

    if (not conn) and max_open > 0 and pool.open >= max_open then
      -- try again in a second, before giving up
      cqueues.sleep(1)
      conn = try_from_pool(pool)
      xerror.must(conn, 'too many open connections')
    end

    if not conn then
      conn = xerror.must(xpgsql.connect(connstr))
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

local M = {
  app = {
    register_migrations = function(self, name, migs)
      tcheck({'*', 'string', 'table'}, self, name, migs)
      self:_register('migrations', name, migs, true)
      if migs.after then
        local v = self:lookup_migrations(name)
        v.after = xtable.toarray(xtable.setunion(
          xtable.toset(v.after), xtable.toset(migs.after)))
      end
    end,

    lookup_migrations = function(self, name)
      tcheck({'*', 'string'}, self, name)
      return self:_lookup('migrations', name)
    end,
  },
}

-- The database package registers a db function on the app.
-- It also runs the migrator, which runs when app:run is
-- called, executing all registered migrations from the config.
--
-- Config:
--
--  * connection_string: string = the connection string
--  * migrations: array of tables = the migrations to run, each
--    table being an array of migration steps (string or function,
--    as described in the Migrator) with a 'package' field that
--    identifies for which package the migrations apply, and an
--    optional 'after' field that identifies package names (array
--    of strings) that must have their migrations run before this package.
--  * pool: table = if set, configures a connection pool so that
--    calling App:db returns a pooled connection if available,
--    and calling conn:close returns it to the pool if possible.
--    The fields are max_idle, max_open, idle_timeout and
--    life_timeout. Defaults are respectively 2, 0 (unlimited),
--    0 (no timeout) and 0 (no timeout).
--
-- Methods:
--
-- TODO: db method should return errors, not raise (or return a conn that will fail on first use).
--
-- conn | ... = App:db([f, ...])
--
--   Returns a connection or, if a function is provided as
--   argument, that function is called with the connection which is
--   then released automatically when the function is done - regardless
--   of whether an error was raised or not - and the call returns the
--   return values of the function or nil and the error message.
--
--   > f: function|nil = function to call with the connection
--   > ... = extra arguments are passed to the function after the connection
--
--   < conn: connection = if no function is provided, returns the connection
--   < ... = if a function is provided, returns the returned values,
--     or nil and an error.
--
-- v = App:lookup_migrations(name)
--
--   Returns the migrations registered for that name, or nil if none.
--
--   > name: string = the name for the registered migrations
--   < v: array = the registered migrations
--
-- App:register_migrations(name, migs)
--
--   Registers the migrations migs for name. If there are already registered
--   migrations for name, the new ones are appended at the end.
--
--   > name: string = the name of the owner of the migrations
--   > migs: array = same as for the migrations configuration field
--
function M.register(cfg, app)
  tcheck({'table', 'tulip.App'}, cfg, app)
  app.db = make_db(cfg, app)
end

function M.activate(cfg, app)
  tcheck({'table', 'tulip.App'}, cfg, app)

  if cfg.migrations then
    for _, v in ipairs(cfg.migrations) do
      app:register_migrations(v.package, v)
    end
  end

  local order
  local migrations = app.migrations
  local migrator = Migrator.new(cfg.connection_string)
  if migrations then
    local graph = tsort.new()
    for nm, migs in pairs(migrations) do
      migrator:register(nm, migs)
      if migs.after then
        for _, from in ipairs(migs.after) do
          graph:add(from, nm)
        end
      else
        graph:add(nm)
      end
    end

    order = graph:sort()
    if not order then
      xerror.throw('circular dependency in database migrations')
    end
  end

  app:log('i', {pkg = 'database', msg = 'migrations started'})
  xerror.must(app:db(function(conn)
    return xerror.must(migrator:run(conn, function(pkg, i)
      app:log('i', {pkg = 'database', migration = string.format('%s:%d', pkg, i), msg = 'applying migration'})
    end, order))
  end))
  app:log('i', {pkg = 'database', msg = 'migrations done'})
end

return M
