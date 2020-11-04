local auxlib = require 'cqueues.auxlib'
local cqueues = require 'cqueues'
local errno = require 'cqueues.errno'
local socket = require 'cqueues.socket'
local tcheck = require 'tcheck'
local xio = require 'web.xio'

local function make_middleware(cfg)
  local mw = cfg.middleware
  local counter = mw.counter
  local timer = mw.timer

  return function(req, res, nxt)
    local app = req.app

    local start = cqueues.monotime()
    nxt()
    local dur = cqueues.monotime() - start

    local labels = {
      path = req.url.path,
      method = req.method,
      status = res.headers:get(':status'),
    }
    if counter then
      labels['@'] = counter.sample
      app:metrics(counter.name or 'web.http.requests_total',
        'counter', 1, labels)
    end
    if timer then
      labels['@'] = timer.sample
      app:metrics(timer.name or 'web.http.request_duration_milliseconds',
        'timer', math.modf(dur * 1000), labels)
    end
  end
end

local function make_metrics(cfg)
  -- ok to assert here, this is called during the register phase.
  local sock = auxlib.assert(socket.connect(
    cfg.host, cfg.port, socket.AF_INET, socket.SOCK_DGRAM))
  local to = cfg.write_timeout

  local lookup_names
  if cfg.allowed_metrics then
    lookup_names = {}
    for _, m in ipairs(cfg.allowed_metrics) do
      lookup_names[m] = true
    end
  end

  return function(_, name, typ, val, t)
    if lookup_names and not lookup_names[name] then
      return nil, string.format('name %q is invalid', name)
    end

    val = val or 1

    local type_code
    if typ == 'counter' then
      type_code = 'c'
    elseif typ == 'gauge' then
      type_code = 'g'
    elseif typ == 'timer' then
      type_code = 'ms'
    elseif typ == 'set' then
      type_code = 's'
    else
      return nil, string.format('metric type %q is invalid', typ)
    end

    local sample
    local tags
    if t then
      sample = t['@']
      if sample and sample < 1 and xio.randomint(100) >= (sample * 100) then
        -- do not send this sample
        return true
      end

      for k, v in pairs(t) do
        if k ~= '@' then
          if not tags then tags = {} end
          table.insert(tags, k..'='..v)
        end
      end
    end

    -- build the packet
    local pkt = name
    if tags then
      table.sort(tags)
      pkt = pkt .. '#' .. table.concat(tags, ',')
    end
    pkt = pkt .. ':' .. tostring(val) .. '|' .. type_code
    if sample then
      pkt = pkt .. '|@' .. tostring(sample)
    end

    local ok, ecode = sock:xwrite(pkt, 'n', to)
    if not ok then
      return nil, errno.strerror(ecode), ecode
    end
    return true
  end
end

local M = {}

-- The metrics package registers an App:metrics method that reports
-- a metric to the configured UDP server, in the statsd protocol.
--
-- Config:
--   * allowed_metrics: array of string = if set, only those metrics
--     will be allowed.
--   * host: string = the address of the statsd-compatible UDP server to send
--     metrics to.
--   * port: number = the port of the statsd-compatible UDP server to send
--     metrics to.
--   * write_timeout: number = write timeout of metrics in seconds.
--   * middleware.counter.name,
--     middleware.timer.name: string = the name of the counter/timer metrics
--     to record in the middleware.
--   * middleware.counter.sample,
--     middleware.timer.sample: number = the sample rate of the counter/timer
--     metric.
--   If there is no middleware.counter or middleware.timer config, then that
--   metric is not recorded, and if there is no middleware table, then the
--   middleware is not registered.
--
-- v, err = App:metrics(name, type[, value[, t]])
--   > name: string = name of the metric
--   > type: string = 'counter', 'gauge', 'timer' or 'set'.
--   > value: number|nil = the value to register, defaults to 1.
--   > t: table|nil = a dictionary of key-value strings to register
--     as dimensions (labels, tags) associated with the sample. If the
--     table has an ['@'] field, its value is the sampling rate of the
--     metric. Tags are added in the Librato style, see
--     https://github.com/prometheus/statsd_exporter#tagging-extensions
--   < v: bool|nil = True if the metric was registered successfully.
--     Is nil on error.
--   < err: string|nil = error message if v is nil.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  app.metrics = make_metrics(cfg)

  if cfg.middleware then
    app:register_middleware('web.pkg.metrics', make_middleware(cfg))
  end
end

return M
