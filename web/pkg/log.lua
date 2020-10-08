local cjson = require('cjson').new()
local tcheck = require 'tcheck'

local M = {}

local function stdout_logger(t)
  io.write(cjson.encode(t) .. '\n')
end

local function log_middleware(req, res, nxt)
  local date = os.date('!%FT%T%z')

  nxt()

  local status = tonumber(res.headers:get(':status'))
  local path = req.url.path
  local rid = req.locals.request_id

  -- TODO: more fields, duration
  req.app:log('i', {pkg = 'log', date = date, path = path, status = status, request_id = rid, full_url = tostring(req.url)})
end

-- The log package register a logging backend to stdout (in fact,
-- it writes to io.output(), so if set to a file, will log to
-- that file). It also configures the log levels to consider for
-- all logging backends and registers a logging middleware that is
-- not enabled by default, under the name 'web.pkg.log'.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)

  app.log_level = cfg.level
  app:register_logger('web.pkg.log', stdout_logger)
  app:register_middleware('web.pkg.log', log_middleware)
end

return M
