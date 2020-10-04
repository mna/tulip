#!/usr/bin/env -S llrocks run

local handler = require 'web.handler'
local App = require 'web.App'

local app = App{
  log = {
    level = 'd',
  },
  server = {
    host = '127.0.0.1',
    port = 8080,
    reuseaddr = true,
    reuseport = true,
    limits = {
      connection_timeout = 10,
      idle_timeout = 60, -- keepalive?
      max_active_connections = 1000,
      read_timeout = 20,
      write_timeout = 20,
    },
    tls = {
      required = true,
      protocol = 'TLS',
      certificate_path = 'run/certs/fullchain.pem',
      private_key_path = 'run/certs/privkey.pem',
    },
  },
  routes = {
    {method = 'GET', pattern = '^/hello', handler = handler.write{status = 200, body = 'hello, Martin!'}},
    {method = 'GET', pattern = '^/fail', handler = function() error('this totally fails') end},
  },
  middleware = {
    'log',
    handler.recover(function(_, res, err) res:write{status = 500, body = tostring(err)} end),
    'routes',
  },
}
assert(app:run())
