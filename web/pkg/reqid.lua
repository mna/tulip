local base64 = require 'base64'
local tcheck = require 'tcheck'
local xio = require 'web.xio'

local function make_middleware(cfg)
  local len = cfg.size
  local hdr = cfg.header

  return function(req, res, nxt)
    local tok = xio.random(len)
    local btok = base64.encode(tok)
    req.request_id = btok
    req.headers:upsert(hdr, btok)
    res.headers:upsert(hdr, btok)
    nxt()
  end
end

local M = {}

-- The reqid package registers a middleware that adds a unique
-- id to each request. The id is added to both the request and the
-- response's headers (under the header name provided in the configuration)
-- and is also added on the request field request_id.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)

  app:register_middleware('web.pkg.reqid', make_middleware(cfg))
end

return M
