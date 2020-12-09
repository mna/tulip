local lu = require 'luaunit'
local xio = require 'tulip.xio'

local M = {}

function M.test_b64()
  local cases = {
    {input = 'abc', output = 'YWJj'},
    {input = 'Martin\n', output = 'TWFydGluCg--'},
    {input = '\\/?.<', output = 'XC8_Ljw-'},
  }

  for _, c in ipairs(cases) do
    local v = xio.b64encode(c.input)
    lu.assertEquals(v, c.output)
    v = xio.b64decode(v)
    lu.assertEquals(v, c.input)
  end
end

return M
