local lu = require 'luaunit'

TestCron = require 'test.cron'
TestCsrf = require 'test.csrf'
TestMigrate = require 'test.migrate'
TestMqueue = require 'test.mqueue'
TestPubsub = require 'test.pubsub'
TestReadme = require 'test.readme'
TestSendgrid = require 'test.sendgrid'
TestToken = require 'test.token'
TestXstring = require 'test.xstring'
TestXtable = require 'test.xtable'

os.exit(lu.LuaUnit.run())
