local handler = require 'tulip.handler'

return {
  log = {level = 'debug'},

  server = {
    host = '0.0.0.0',
    port = 80,
    reuseaddr = true,
    reuseport = true,

    limits = {
      connection_timeout = 10,
      idle_timeout = 60,
      read_timeout = 20,
      write_timeout = 20,
    },

    --[[
    tls = {
      required = true,
      protocol = 'TLS',
      certificate_path = 'run/certs/fullchain.pem',
      private_key_path = 'run/certs/privkey.pem',
    },
    ]]--
  },

  database = {
    connection_string = '',
    pool = {
      max_idle = 10,
      max_open = 100,
      idle_timeout = 60,
    },
  },

  ['scripts.bench.plugin'] = {},

  routes = {
    {method = 'GET', pattern = '^/hello$', handler = handler.write{status = 200, body = 'hello, Martin!\n'}},
    {method = 'GET', pattern = '^/data/([^/]*)$', middleware = {'scripts.bench.plugin'}},
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
    },
    decoder = {
      allow_invalid_numbers = false,
      max_depth = 100,
    },
  },
}
