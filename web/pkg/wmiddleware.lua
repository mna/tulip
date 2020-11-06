local handler = require 'web.handler'
local tcheck = require 'tcheck'

local function app_call(app, msg, nxt)
  if not app.wmiddleware then
    if nxt then nxt() end
    return
  end
  handler.chain_wmiddleware(app.wmiddleware, msg, nxt)
end

local M = {}

-- The wmiddleware package enables app-level worker middleware in the
-- order specified in the configuration. This means that messages
-- will go through those middleware handlers in that order.
-- It also sets up the __call metamethod on the App's metatable so
-- that it can be used as initial wmiddleware.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  app.wmiddleware = cfg

  local mt = getmetatable(app)
  mt.__call = app_call
end

function M.activate(app)
  tcheck('web.App', app)
  app:resolve_wmiddleware(app.wmiddleware)
end

return M
