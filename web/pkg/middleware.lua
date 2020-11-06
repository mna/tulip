local handler = require 'web.handler'
local tcheck = require 'tcheck'

local function app_call(app, req, res, nxt)
  if not app.middleware then
    if nxt then nxt() end
    return
  end
  handler.chain_middleware(app.middleware, req, res, nxt)
end

local M = {}

-- The middleware package enables app-level middleware in the
-- order specified in the configuration. This means that requests
-- will go through those middleware handlers in that order.
-- It also sets up the __call metamethod on the App's metatable so
-- that it can be used as initial middleware.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  app.middleware = cfg

  local mt = getmetatable(app)
  mt.__call = app_call
end

function M.activate(app)
  tcheck('web.App', app)
  app:resolve_middleware(app.middleware)
end

return M
