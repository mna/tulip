local lu = require 'luaunit'

TestMigrate = require 'test.migrate'
TestWeb = require 'test.web'
TestXstring = require 'test.xstring'

os.exit(lu.LuaUnit.run())
