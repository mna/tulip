local tcheck = require 'tcheck'
local xpgsql = require 'xpgsql'

local PACKAGE = 'web.pkg.database'
local MIGRATIONS = {
  [[
    CREATE TABLE "web_pkg_database_migrations" (
      "package" VARCHAR(100) NOT NULL,
      "version" INTEGER NOT NULL CHECK ("version" > 0),
      "created" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

      PRIMARY KEY ("package")
    )
  ]],
}

local Migrator = {__name = PACKAGE .. '.Migrator'}
Migrator.__index = Migrator

local function get_version(conn, pkg)
  local res, err = conn:query([[
    SELECT
      "version"
    FROM
      "web_pkg_database_migrations"
    WHERE
      "package" = $1
  ]], pkg)

  if res then
    if res:ntuples() > 0 then
      return tonumber(res[1][1])
    else
      return 0
    end
  end
  return nil, err
end

local function set_version(conn, pkg, version)
  assert(conn:exec([[
    INSERT INTO "web_pkg_database_migrations"
      ("package", "version")
    VALUES
      ($1, $2)
    ON CONFLICT
      ("package")
    DO UPDATE SET
      "version" = $2
  ]], pkg, version))
  return true
end

-- Registers the migrations for a package. The t table is an array
-- corresponding to the version of the migration, and only the
-- unapplied versions will be run. The values may be a single
-- string statement, in which case it gets executed as-is, or it
-- can be a function, in which case it gets called with the connection
-- instance and the array index as arguments. It should raise an
-- error to indicate failure.
--
-- It raises an error if the package is already registered. Returns
-- true on success.
function Migrator:register(pkg, t)
  tcheck({'*', 'string', 'table'}, self, pkg, t)

  local pkgs = self.packages or {}
  local order = self.order or {}

  if pkgs[pkg] then
    error(string.format(
      'package %q is already registered', pkg))
  end
  pkgs[pkg] = t
  table.insert(order, pkg)

  self.packages = pkgs
  self.order = order

  return true
end

-- Run executes the registered migrations in the order the packages
-- were registered, unless order is provided (which must be a table
-- of strings). Each package's migrations are run in distinct
-- transactions, and it stops and returns at the first error.
-- On success, returns true, otherwise returns nil and an error
-- message. If cb is provided, it is called with two arguments for
-- each applied migration - the package name and the migration index.
-- If conn is nil, a connection is made to get one that is closed
-- on return.
function Migrator:run(conn, cb, order)
  local close = not conn
  if not conn then
    local err
    conn, err = xpgsql.connect(self.connection_string)
    if not conn then
      return nil, err
    end
  end

  order = order or self.order
  if #order == 0 or order[1] ~= PACKAGE then
    -- ensure the Migrator's migrations always come first
    table.insert(order, 1, PACKAGE)
  end

  return conn:with(close, function()
    for _, pkg in ipairs(order) do
      -- get the current version of this package
      local latest, err = get_version(conn, pkg)
      if not latest then
        -- it is ok for get_version to fail if this migration is for the
        -- migration package itself (version table does not exist yet).
        if pkg == PACKAGE then
          latest = 0
        else
          error(err)
        end
      end

      local migrations = self.packages[pkg]
      if #migrations > latest then
        assert(conn:tx(function()
          for i = latest + 1, #migrations do
            if cb then cb(pkg, i) end

            local mig = migrations[i]
            if type(mig) == 'string' then
              assert(conn:exec(mig))
            else
              mig(conn, i)
            end
          end
          set_version(conn, pkg, #migrations)
          return true
        end))
      end
    end
    return true
  end)
end

-- Creates a Migrator instance that will run against the database
-- to connect to with the provided connstr (or environment variables
-- if no connstr is provided).
function Migrator.new(connstr)
  tcheck('string|nil', connstr)

  local o = {connection_string = connstr}
  setmetatable(o, Migrator)

  -- auto-register the migrator's own migrations as first
  o:register(PACKAGE, MIGRATIONS)
  return o
end

return Migrator
