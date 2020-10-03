#!/usr/bin/env -S llrocks run

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
      protocol = 'TLSv1_2',
      certificate_path = 'run/certs/fullchain.pem',
      private_key_path = 'run/certs/privkey.pem',
    },
  },
}
assert(app:run())
