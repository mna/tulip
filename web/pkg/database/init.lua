local xpgsql = require 'xpgsql'
local Migrator = require 'web.pkg.database.Migrator'

local function make_db(connstr)
  return function(fn, ...)
    local conn = assert(xpgsql.connect(connstr))
    if not fn then return conn end

    local res = table.pack(pcall(fn, conn, ...))
    conn:close()
    assert(res[1], res[2])
    return table.unpack(res, 2, res.n)
  end
end

local M = {}

-- The database package registers a db function on the app that
-- returns a connection when called. If a function is provided as
-- argument, that function is called with the connection, which is
-- then closed automatically when the function is done, regardless
-- of whether an error was raised or not, and the call returns the
-- return values of the function or re-raise the error.
--
-- It also registers the migrator, which runs when the app is
-- started, executing all registered migrations from the config.
function M.register(cfg, app)
  app.db = make_db(cfg.connection_string)
end

function M.onrun(app)
  local cfg = app.config.database
  -- TODO: group migrations of same packages together
  local mig = Migrator.new(cfg.connection_string)
end

return M
