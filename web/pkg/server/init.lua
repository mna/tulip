local context = require 'openssl.ssl.context'
local pkey = require 'openssl.pkey'
local server = require 'http.server'
local tcheck = require 'tcheck'
local x509 = require 'openssl.x509'
local xio = require 'web.xio'
local Request = require 'web.pkg.server.Request'
local Response = require 'web.pkg.server.Response'

local function bootstrap_handler(app, readto, writeto)
  return function(_, stm)
    local req = Request.new(stm, readto)
    local res = Response.new(stm, writeto)
    -- TODO: configure trusted proxy headers, to use
    -- Forwarded or X-Forwarded-... headers (maybe via a trusted
    -- secret). X-Real-Ip for peer (configurable? Cloudflare uses
    -- different header).

    stm.request = req
    stm.response = res
    req.app, res.app = app, app
    app(req, res)
  end
end

local function main(app, cq)
  local cfg = app.config.server
  local limits = cfg.limits or {}
  local opts = {
    cq = cq,
    host = cfg.host,
    port = cfg.port,
    path = cfg.path,
    reuseaddr = cfg.reuseaddr,
    reuseport = cfg.reuseport,
    connection_setup_timeout = limits.connection_timeout,
    intra_stream_timeout = limits.idle_timeout,
    max_concurrent = limits.max_active_connections,
    onstream = bootstrap_handler(app, limits.read_timeout, limits.write_timeout),
  }

  if cfg.tls then
    if cfg.tls.required then
      opts.tls = true
    end
    local ctx = context.new(cfg.tls.protocol, true)
    local pk = pkey.new(assert(xio.read_file(cfg.tls.private_key_path)))
    assert(ctx:setPrivateKey(pk))
    local cert = x509.new(assert(xio.read_file(cfg.tls.certificate_path)))
    assert(ctx:setCertificate(cert))
    opts.ctx = ctx
  end

  local srv = assert(server.listen(opts))
  assert(srv:listen(limits.connection_timeout))
  local _, ip, port = assert(srv:localname())
  app:log('i', {pkg = 'server', ip = ip, port = port, msg = 'listening'})

  app.server = srv
  return srv:loop()
end

local M = {}

-- The server package turns the app into a web server. It sets
-- a main method on the app that will start the server and bootstrap
-- handling requests by calling the app as initial middleware.
-- Once the app is started, it registers the http server as the
-- 'server' field on the app.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  app.main = main
end

return M
