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
  },
}
assert(app:run())
