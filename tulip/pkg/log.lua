local cjson = require('cjson').new()
local cqueues = require 'cqueues'
local tcheck = require 'tcheck'
local xerror = require 'tulip.xerror'

local function stdout_logger(t)
  io.write(cjson.encode(t) .. '\n')
end

local function make_file_logger(path)
  local fd = xerror.must(io.open(path, 'w+'))
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
    type = 'web request',
  })
end

local function log_wmiddleware(msg, nxt)
  local date = os.date('!%FT%T%z')

  local start = cqueues.monotime()
  nxt()
  local dur = cqueues.monotime() - start

  -- TODO: processing result?
  msg.app:log('i', {
    pkg = 'log', date = date,
    queue = msg.queue, attempt = msg.attempts,
    msgid = msg.id, duration = string.format('%.3f', dur),
    type = 'worker message',
  })
end

local M = {}

-- The log package registers a logging backend in JSON format.
--
-- Config:
--
-- * level: string|number = the minimum log level to output. If set to a
--   string, it should be either 'debug', 'error', 'info', or 'warning'
--   or the first letter of those words. Can also be a number. The mapping
--   of string level to number is: debug=1, info=10, warning=100 and
--   error=1000.
-- * file: string = path to a file to log to. If not set, will log to
--   io.output().
--
-- Fields:
--
-- App.log_level: string|number
--
--    Sets the minimum log level to consider for all logging backends.
--    Once the app is activated (in the call to app:run), if the level is
--    a string, it is converted to a number.
--
-- Middleware:
--
-- * tulip.pkg.log
--
--   Registered if the tulip.pkg.middleware package is registered. Logs
--   web requests.
--
-- Wmiddleware:
--
-- * tulip.pkg.log
--
--   Registered if the tulip.pkg.wmiddleware package is registered. Logs
--   processed worker messages.
--
function M.register(cfg, app)
  tcheck({'table', 'tulip.App'}, cfg, app)

  app.log_level = cfg.level
  if cfg.file then
    app:register_logger('tulip.pkg.log', make_file_logger(cfg.file))
  else
    app:register_logger('tulip.pkg.log', stdout_logger)
  end

  if app:has_package('tulip.pkg.middleware') then
    app:register_middleware('tulip.pkg.log', log_middleware)
  end
  if app:has_package('tulip.pkg.wmiddleware') then
    app:register_wmiddleware('tulip.pkg.log', log_wmiddleware)
  end
end

return M
