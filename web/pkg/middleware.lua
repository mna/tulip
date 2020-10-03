local tcheck = require 'tcheck'

local M = {}

-- The middleware package enables app-level middleware in the
-- order specified in the configuration. This means that requests
-- will go through those middleware handlers in that order.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  app.middleware = cfg
end

function M.activate(app)
  tcheck('web.App', app)
  app:resolve_middleware(app.middleware)
end

return M
