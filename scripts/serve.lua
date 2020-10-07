#!/usr/bin/env -S llrocks run

local handler = require 'web.handler'
local App = require 'web.App'

local app = App{
  log = {level = 'debug'},
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
    {method = 'GET', pattern = '^/json', handler = handler.write{
      status = 200,
      content_type = 'application/json',
      body = {
        name = 'Martin',
        msg = 'Hi!',
      },
    }},
    {method = 'GET', pattern = '^/url', handler = handler.write{
      status = 200,
      content_type = 'application/x-www-form-urlencoded',
      body = {
        name = 'Martin',
        msg = 'Hi!',
        teeth = 12,
      },
    }},
  },
  middleware = {
    'log',
    handler.recover(function(_, res, err) res:write{status = 500, body = tostring(err)} end),
    'reqid',
    'routes',
  },
  reqid = {size = 12, header = 'x-request-id'},
  json = {
    encoder = {
      allow_invalid_numbers = false,
      number_precision = 4,
      max_depth = 100,
      sparse_array = {
        convert_excessive = true, -- convert excessively sparse arrays to dict instead of failing
        ratio = 2,
        safe = 10,
      },
    },
    decoder = {
      allow_invalid_numbers = false,
      max_depth = 100,
    },
  },
  urlenc = {},
}
assert(app:run())
