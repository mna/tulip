local tcheck = require 'tcheck'
local xpgsql = require 'xpgsql'

local MODULE = 'web.migrate'
local MIGRATIONS = {
  [[
    CREATE TABLE "web_migrate_migrations" (
      "module"  VARCHAR(100) NOT NULL,
      "version" INTEGER NOT NULL CHECK ("version" > 0),
      "created" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

      PRIMARY KEY ("module")
    )
  ]],
}

local Migrator = {__name = MODULE .. '.Migrator'}
Migrator.__index = Migrator

local function get_version(conn, module)
  local res, err = conn:query([[
    SELECT
      "version"
    FROM
      "web_migrate_migrations"
    WHERE
      "module" = $1
  ]], module)

  if res then
    if res:ntuples() > 0 then
      return tonumber(res[1][1])
    else
      return 0
    end
  end
  return nil, err
end

local function set_version(conn, module, version)
  assert(conn:exec([[
    INSERT INTO "web_migrate_migrations"
      ("module", "version")
    VALUES
      ($1, $2)
    ON CONFLICT
      ("module")
    DO UPDATE SET
      "version" = $2
  ]], module, version))
  return true
end

-- Registers the migrations for a module. The t table is an array
-- corresponding to the version of the migration, and only the
-- unapplied versions will be run. The values may be a single
-- string statement, in which case it gets executed as-is, or it
-- can be a function, in which case it gets called with the connection
-- instance and the array index as arguments. It should raise an
-- error to indicate failure.
--
-- It raises an error if the module is already registered. Returns
-- true on success.
function Migrator:register(module, t)
  tcheck({'*', 'string', 'table'}, self, module, t)

  local mods = self.modules or {}
  local order = self.order or {}

  if mods[module] then
    error(string.format(
      'module %q is already registered', module))
  end
  mods[module] = t
  table.insert(order, module)

  self.modules = mods
  self.order = order

  return true
end

-- Run executes the registered migrations in the order the modules
-- were registered. Each module's migrations are run in distinct
-- transactions, and it stops and returns at the first error.
-- On success, returns true, otherwise returns nil and an error
-- message.
function Migrator:run()
  local conn = xpgsql.connect(self.connection_string)

  for _, module in ipairs(self.order) do
    -- get the current version of this module
    local latest, err = get_version(conn, module)
    if not latest then
      -- it is ok for get_version to fail if this migration is for the
      -- migration module itself (version table does not exist yet).
      if module == MODULE then
        latest = 0
      else
        conn:close()
        return nil, err
      end
    end

    local migrations = self.modules[module]
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
        set_version(conn, module, #migrations)
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
  o:register(MODULE, MIGRATIONS)
  return o
end

return M
