local tcheck = require 'tcheck'
local Mux = require 'web.pkg.routes.Mux'

local M = {}

-- The routes package registers a route multiplexer where each
-- request is routed to a specific handler based on the method
-- and path, with optional middleware applied.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  -- nothing to do on register, the actual work is done in onrun.
  -- TODO: hmm maybe it should actually register 'routes' as a
  -- middleware, and enable it in the app-level middleware?
end

function M.onrun(app)
  tcheck('web.App', app)

  local cfg = app.config.routes
  -- TODO: resolve all middleware/handler strings to actual functions
  local mux = Mux.new(cfg)
end

return M
