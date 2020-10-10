#!/usr/bin/env -S llrocks run

-- usage: ./scripts/run_server.lua FILE FUNCTIONNAME
-- This scripts runs a web.App by requiring FILE which must be
-- a Lua file reachable from this script, and calls FUNCTIONNAME
-- on this FILE, which must be a valid function exported by the
-- module.
--
-- The function should return the App configuration ready to use,
-- and then the script creates and runs the app with that
-- configuration. In case dynamic port binding is used (port = 0),
-- the first line written to stdout from the script is the port
-- number of the server.

local tcheck = require 'tcheck'
local App = require 'web.App'

local modname, fname = arg[1], arg[2]
tcheck({'string', 'string'}, modname, fname)

local mod = require(modname)
local fn = mod[fname]
assert(type(fn) == 'function', 'function name must be an exported function')

local app = App(fn(table.unpack(arg, 3)))
app.log_level = 'd' -- must force this to get the server pkg log
app:register_logger('run_server', function(t)
  if t.pkg == 'server' and t.port then
    io.write(tostring(t.port) .. '\n')
    io.flush()
  end
end)
assert(app:run())
