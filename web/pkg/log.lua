local cjson = require 'cjson'

local M = {}

local function stdout_logger(t)
  io.write(cjson.encode(t) .. '\n')
end

-- The log package register a logging backend to stdout (in fact,
-- it writes to io.output(), so if set to a file, will log to
-- that file). It also configures the log levels to consider for
-- all logging backends.
function M.register(cfg, app)
  app.log_level = cfg.level
  app.loggers = app.loggers or {}
  table.insert(app.loggers, stdout_logger)
end

return M
