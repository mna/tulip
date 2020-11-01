local tcheck = require 'tcheck'

local function make_metrics(cfg, app)

end

local M = {}

-- The metrics package registers an App:metrics method that registers
-- a metric.
--
-- Requires: a database package
-- Config:
--   * allowed_metrics: array of string = if set, only those metrics
--     will be allowed.
--   * resolution: integer = the resolution in seconds of the counter
--     and gauge metrics. Defaults to 1.
--   * buffer.max_entries: integer = maximum number of entries in
--     memory before saving the metrics to the db, defaults to 100.
--   * buffer.max_delay: integer = maximum delay in seconds to keep
--     metrics in memory before saving to the db, defaults to 10.
--     This is the maximum time for which metrics may be lost in case
--     of a process failure.
--
-- v, err = App:metrics(name, type[, value[, t]])
--   > name: string = name of the metric
--   > type: string = 'counter', 'gauge' or 'raw', the supported metric
--     types.
--   > value: number|nil = the value to register, defaults to 1.
--   > t: table|nil = a dictionary of key-value strings to register
--     as dimensions associated with the sample.
--   < v: bool|nil = True if the metric was registered successfully.
--     Is nil on error.
--   < err: string|nil = error message if v is nil.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  app.metrics = make_metrics(cfg, app)

  local db = app.config.database
  if not db then
    error('no database registered')
  end
  db.migrations = db.migrations or {}
  table.insert(db.migrations, {
    package = 'web.pkg.metrics';
    table.unpack(metrics.migrations)
  })
end

return M
