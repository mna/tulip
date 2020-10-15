#!/usr/bin/env -S llrocks run

local handler = require 'web.handler'

local M = {}

if string.match(arg[0], '/serve%.lua') then
  os.execute('./scripts/run_server.lua scripts.serve config')
  return
end

function M.config()
  return {
    log = {level = 'debug'},

    server = {
      host = '127.0.0.1',
      port = 0,
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

    database = {
      connection_string = '',
    },

    routes = {
      {method = 'GET', pattern = '^/hello', handler = handler.write{status = 200, body = 'hello, Martin!'}},
      {method = 'GET', pattern = '^/fail', handler = function() error('this totally fails') end},
      {method = 'GET', pattern = '^/pub/(.+)$', handler = handler.dir('scripts')},
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
      'csrf',
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

    csrf = {
      auth_key = os.getenv('LUAWEB_CSRFKEY'),
      max_age = 3600 * 12, -- 12 hours, validity of token
      http_only = true,
      secure = true,
      same_site = 'lax', -- one of 'strict', 'lax', or 'none'
    },

    token = {},
    mqueue = {},
    sendgrid = {
      from = os.getenv('LUAWEB_TEST_FROMEMAIL'),
      api_key = os.getenv('LUAWEB_TEST_SENDGRIDKEY'),
    },
  }
end

return M
