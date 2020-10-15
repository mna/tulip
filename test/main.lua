local lu = require 'luaunit'

TestCsrf = require 'test.csrf'
TestMigrate = require 'test.migrate'
TestSendgrid = require 'test.sendgrid'
TestToken = require 'test.token'
TestXstring = require 'test.xstring'

os.exit(lu.LuaUnit.run())
