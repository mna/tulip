local handler = require 'web.handler'

return {
  log = {level = 'debug'},

  server = {
    host = '127.0.0.1',
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
  },

  routes = {
    {method = 'GET', pattern = '^/hello$', handler = handler.write{status = 200, body = 'hello, Martin!\n'}},
  },

  middleware = {
    'log',
    handler.recover(function(_, res, err) res:write{status = 500, body = tostring(err)} end),
    'reqid',
    'routes',
  },

  reqid = {size = 12, header = 'x-request-id'},
}
