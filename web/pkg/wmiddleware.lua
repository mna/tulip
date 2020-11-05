local tcheck = require 'tcheck'

local M = {}

-- The wmiddleware package enables app-level worker middleware in the
-- order specified in the configuration. This means that messages
-- will go through those middleware handlers in that order.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  app.wmiddleware = cfg
end

function M.activate(app)
  tcheck('web.App', app)
  app:resolve_wmiddleware(app.wmiddleware)
end

return M
