local lu = require 'luaunit'

TestCsrf = require 'test.csrf'
TestMigrate = require 'test.migrate'
TestReadme = require 'test.readme'
TestSendgrid = require 'test.sendgrid'
TestToken = require 'test.token'
TestXstring = require 'test.xstring'

os.exit(lu.LuaUnit.run())
