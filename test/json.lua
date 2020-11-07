local cjson = require 'cjson'
local lu = require 'luaunit'
local App = require 'web.App'

local JSON_MIME = 'application/json'
local NULL = cjson.null

local M = {}

function M.test_json()
  local cases = {
    {input = nil, output = [[null]]},
    {input = true, output = [[true]]},
    {input = false, output = [[false]]},
    {input = 'abc', output = [["abc"]]},
    {input = 1.234, output = [[1.234]]},
    {input = {}, output = '{}'},
    {input = {1}, output = '[1]'},
    {input = {a = 1}, output = '{"a":1}'},
  }

  local app = App{json = {}}
  app.main = function()
    for _, c in ipairs(cases) do
      local got = app:encode(c.input, JSON_MIME)
      lu.assertEquals(got, c.output)

      got = app:decode(c.output, JSON_MIME)
      if c.input == nil then
        lu.assertEquals(got, NULL)
      else
        lu.assertEquals(got, c.input)
      end
    end
  end
  app:run()
end

return M
