local tcheck = require 'tcheck'

local M = {
  requires = {
    'web.pkg.middleware',
  },
}

function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
end

return M
