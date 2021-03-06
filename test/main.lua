local lu = require 'luaunit'

TestAccount = require 'test.account'
TestAccountMw = require 'test.account_mw'
TestApp = require 'test.app'
TestCron = require 'test.cron'
TestCsrf = require 'test.csrf'
TestDatabase = require 'test.database'
TestFlash = require 'test.flash'
TestGzip = require 'test.gzip'
TestJson = require 'test.json'
TestMetrics = require 'test.metrics'
TestMigrate = require 'test.migrate'
TestMqueue = require 'test.mqueue'
TestPubsub = require 'test.pubsub'
TestReadme = require 'test.readme'
TestRoutes = require 'test.routes'
TestSendgrid = require 'test.sendgrid'
TestServer = require 'test.server'
TestToken = require 'test.token'
TestValidator = require 'test.validator'
TestWroutes = require 'test.wroutes'
TestXerror = require 'test.xerror'
TestXio = require 'test.xio'
TestXstring = require 'test.xstring'
TestXtable = require 'test.xtable'

os.exit(lu.LuaUnit.run())
