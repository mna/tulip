local lu = require 'luaunit'

TestMigrate = require 'test.migrate'
TestXstring = require 'test.xstring'

os.exit(lu.LuaUnit.run())
