local auxlib = require 'cqueues.auxlib'
local errno = require 'cqueues.errno'
local socket = require 'cqueues.socket'
local tcheck = require 'tcheck'
local xio = require 'web.xio'

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
      pkt = pkt .. '#' .. table.concat(tags, ',')
    end
    pkt = pkt .. ':' .. tostring(val) .. '|' .. type_code
    if sample then
      pkt = pkt .. '@' .. tostring(sample)
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
--
-- TODO: should register a middleware for route metrics.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  app.metrics = make_metrics(cfg)
end

return M
