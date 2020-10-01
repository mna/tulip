local server = require 'http.server'
local tcheck = require 'tcheck'
local Request = require 'web.pkg.server.Request'
local Response = require 'web.pkg.server.Response'

local function bootstrap_handler(app, readto, writeto)
  return function(_, stm)
    local req = Request.new(stm, readto)
    local res = Response.new(stm, writeto)
    req.app, res.app = app, app
    app(req, res)
  end
end

local function main(app)
  local cfg = app.config.server
  cfg.limits = cfg.limits or {}

  -- TODO: tls, error handler
  -- TODO: should it assert or not?
  local srv = assert(server.listen{
    host = cfg.host,
    port = cfg.port,
    path = cfg.path,
    reuseaddr = cfg.reuseaddr,
    reuseport = cfg.reuseport,
    connection_setup_timeout = cfg.limits.connection_timeout,
    intra_stream_timeout = cfg.limits.idle_timeout,
    max_concurrent = cfg.limits.max_active_connections,
    onstream = bootstrap_handler(app, cfg.limits.read_timeout, cfg.limits.write_timeout),
  })


  assert(srv:listen(cfg.limits.connection_timeout))
  local _, ip, port = assert(srv:localname())
  app:log('i', {ip = ip, port = port, msg = 'listening'})

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
