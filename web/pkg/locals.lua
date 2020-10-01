local tcheck = require 'tcheck'

local M = {}

-- The locals package adds a key-value dictionary on the app
-- under the 'locals' field. This can be used to set app-wide
-- information such as name, title, contact email address, etc.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  app.locals = cfg
end

return M
