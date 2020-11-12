local tcheck = require 'tcheck'

local M = {}

-- The account package...
--
-- Requires: a database package, a cron package.
-- Config:
--  * ...
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)

  -- TODO:
  -- * App.account:create
  -- * App.account:login
  -- * App.account:logout
  -- * App.account:delete
  -- * App.account:verify_email
  -- * App.account:reset_pwd (overload request and do reset)
  -- * App.account:change_email (overload request and do change)
end

return M
