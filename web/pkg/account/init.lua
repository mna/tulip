local tcheck = require 'tcheck'
local Account = require 'web.pkg.account.Account'

local M = {}

-- The account package...
--
-- Requires: database and token packages.
-- Config:
--  * ...
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  app.account = Account.new(app)

  if not app.config.database then
    error('no database registered')
  end
  if not app.config.token then
    error('no token registered')
  end

  -- TODO: Account methods
  -- TODO: middleware:
  -- * signup POST handler
  -- * login POST handler
  -- * authorization middleware, renders either 403 if user is authenticated
  --   but doesn't have required group membership, 401 if user is not
  --   authenticated, or 302 Found and redirect to login page.
  -- * logout handler
  -- * delete POST handler
  -- * change password POST handler
  -- * verify email, change email, reset pwd handlers (likely 3 per type:
  --   trigger the request - e.g. generate token and send email -, GET
  --   the confirmation form, and handle the POST form)
end

return M
