local lu = require 'luaunit'
local App = require 'web.App'

local M = {}

function M.test_deps()
  lu.assertErrorMsgContains('requires package web.pkg.database', function()
    App{
      -- token depends on database
      token = {},
    }
  end)

  lu.assertErrorMsgContains('package not found', function()
    App{
      ['test.not_found'] = {},
    }
  end)

  local app = App{
    token = {},
    ['test.pkg_replaces_database'] = {},
  }
  lu.assertIsFunction(app.db)
end

return M
