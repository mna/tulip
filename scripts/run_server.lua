#!/usr/bin/env -S llrocks run

-- usage: ./scripts/run_server.lua FILE [FUNCTIONNAME]
-- This scripts runs a tulip.App by requiring FILE which must be
-- a Lua file reachable from this script, and calls FUNCTIONNAME
-- on this FILE, which must be a valid function exported by the
-- module. If FUNCTIONNAME is not provided, FILE should export
-- a table ready to use as tulip.App configuration.
--
-- The function should return the App configuration ready to use,
-- and then the script creates and runs the app with that
-- configuration. In case dynamic port binding is used (port = 0),
-- the first line written to stdout from the script is the port
-- number of the server.

local tcheck = require 'tcheck'
local App = require 'tulip.App'

local modname, fname = arg[1], arg[2]
tcheck({'string', 'string|nil'}, modname, fname)

local mod = require(modname)

local config
if fname then
  local fn = mod[fname]
  assert(type(fn) == 'function', 'function name must be an exported function')
  config = fn(table.unpack(arg, 3))
elseif type(mod) ~= 'table' then
  error('module should export a table')
else
  config = mod
end

local app = App(config)
app.log_level = 'd' -- must force this to get the server pkg log
app:register_logger('run_server', function(t)
  if t.pkg == 'server' and t.port then
    io.write(tostring(t.port) .. '\n')
    io.flush()
  end
end)
assert(app:run())
