local lu = require 'luaunit'

TestCron = require 'test.cron'
TestCsrf = require 'test.csrf'
TestDatabase = require 'test.database'
TestMetrics = require 'test.metrics'
TestMigrate = require 'test.migrate'
TestMqueue = require 'test.mqueue'
TestPubsub = require 'test.pubsub'
TestReadme = require 'test.readme'
TestRoutes = require 'test.routes'
TestSendgrid = require 'test.sendgrid'
TestToken = require 'test.token'
TestWroutes = require 'test.wroutes'
TestXstring = require 'test.xstring'
TestXtable = require 'test.xtable'

os.exit(lu.LuaUnit.run())
