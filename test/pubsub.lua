local cqueues = require 'cqueues'
local lu = require 'luaunit'
local App = require 'web.App'

local M = {}

function M.test_pubsub()
  local app = App{
    database = {connection_string = ''},
    pubsub = {
      allowed_channels = {'a', 'b'},
    },
  }

  app.main = function()
    print('>>>>> main started')
    -- publish without listener works
    local ok, err = app:pubsub('a', nil, {x=1})
    lu.assertNil(err)
    lu.assertTrue(ok)

    print('>>>>>  hereasdasd')
    -- register a handler for channel 'a'
    ok, err = app:pubsub('a', function(n)
      print('>>>> ', n)
    end)
    lu.assertNil(err)
    lu.assertTrue(ok)
    print('>>>>>  here')

    -- publish with a listener works
    ok, err = app:pubsub('a', nil, {x=2})
    lu.assertNil(err)
    lu.assertTrue(ok)
  end

  local cq = cqueues.new()
  cq:wrap(function()
    app:run()
    print('>>>>> run done')
  end)
  assert(cq:loop())
  print('>>>>> loop done')
end

return M
