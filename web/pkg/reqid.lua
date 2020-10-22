local tcheck = require 'tcheck'
local xio = require 'web.xio'

local DEFAULT_SIZE = 12
local DEFAULT_HEADER = 'x-request-id'

local function make_middleware(cfg)
  local len = cfg.size or DEFAULT_SIZE
  local hdr = cfg.header or DEFAULT_HEADER

  return function(req, res, nxt)
    local tok = xio.random(len)
    local btok = xio.b64encode(tok)
    req.locals.request_id = btok
    req.headers:upsert(hdr, btok)
    res.headers:upsert(hdr, btok)
    nxt()
  end
end

local M = {}

-- The reqid package registers a middleware that adds a unique
-- id to each request. The id is added to both the request and the
-- response's headers (under the header name provided in the configuration)
-- and is also added on the request.locals.request_id field.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)

  app:register_middleware('web.pkg.reqid', make_middleware(cfg))
end

return M
