local cjson = require('cjson').new()
local cqueues = require 'cqueues'
local tcheck = require 'tcheck'

local M = {}

local function stdout_logger(t)
  io.write(cjson.encode(t) .. '\n')
end

local function make_file_logger(path)
  local fd = assert(io.open(path, 'w+'))
  return function(t)
    fd:write(cjson.encode(t) .. '\n')
    fd:flush()
  end
end

local function log_middleware(req, res, nxt)
  local date = os.date('!%FT%T%z')

  local start = cqueues.monotime()
  nxt()
  local dur = cqueues.monotime() - start

  local status = tonumber(res.headers:get(':status'))
  local path = req.url.path
  local rid = req.locals.request_id

  req.app:log('i', {
    pkg = 'log', date = date,
    path = path, status = status,
    request_id = rid, full_url = tostring(req.url),
    authority = req.authority, remote_addr = req.remote_addr,
    http_version = req.proto, method = req.method,
    duration = string.format('%.3f', dur),
    bytes_written = res.bytes_written,
  })
end

-- The log package register a logging backend to stdout (in fact,
-- it writes to io.output(), so if set to a file, will log to
-- that file). It also configures the log levels to consider for
-- all logging backends and registers a logging middleware that is
-- not enabled by default, under the name 'web.pkg.log'.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)

  app.log_level = cfg.level
  if cfg.file then
    app:register_logger('web.pkg.log', make_file_logger(cfg.file))
  else
    app:register_logger('web.pkg.log', stdout_logger)
  end
  app:register_middleware('web.pkg.log', log_middleware)
end

return M
