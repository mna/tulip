local tcheck = require 'tcheck'
local xpgsql = require 'xpgsql'

local PACKAGE = 'web.migrate'
local MIGRATIONS = {
  [[
    CREATE TABLE "web_migrate_migrations" (
      "package" VARCHAR(100) NOT NULL,
      "version" INTEGER NOT NULL CHECK ("version" > 0),
      "created" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

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
      "web_migrate_migrations"
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
    INSERT INTO "web_migrate_migrations"
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
-- were registered. Each package's migrations are run in distinct
-- transactions, and it stops and returns at the first error.
-- On success, returns true, otherwise returns nil and an error
-- message.
function Migrator:run()
  local conn = xpgsql.connect(self.connection_string)

  for _, pkg in ipairs(self.order) do
    -- get the current version of this package
    local latest, err = get_version(conn, pkg)
    if not latest then
      -- it is ok for get_version to fail if this migration is for the
      -- migration package itself (version table does not exist yet).
      if pkg == PACKAGE then
        latest = 0
      else
        conn:close()
        return nil, err
      end
    end

    local migrations = self.packages[pkg]
    if #migrations > latest then
      local ok, errtx = conn:tx(function()
        for i = latest + 1, #migrations do
          local mig = migrations[i]
          if type(mig) == 'string' then
            assert(conn:exec(mig))
          else
            mig(conn, i)
          end
        end
        set_version(conn, pkg, #migrations)
        return true
      end)
      if not ok then
        conn:close()
        return nil, errtx
      end
    end
  end

  conn:close()
  return true
end

local M = {}

-- Creates a Migrator instance that will run against the database
-- to connect to with the provided connstr (or environment variables
-- if no connstr is provided).
function M.new(connstr)
  tcheck('string|nil', connstr)

  local o = {connection_string = connstr}
  setmetatable(o, Migrator)

  -- auto-register the migrator's own migrations as first
  o:register(PACKAGE, MIGRATIONS)
  return o
end

return M
