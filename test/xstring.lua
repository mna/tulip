local lu = require 'luaunit'
local xstring = require 'web.xstring'

local M = {}

function M.test_ipat()
  local s = 'AlLo'
  lu.assertFalse(not not string.match(s, 'll'))
  lu.assertTrue(not not string.match(s, xstring.ipat('ll')))
end

function M.test_escapefile()
  local s = 'http://example.com/x?a=1'
  local got = xstring.escapefile(s)
  lu.assertEquals(got, 'http_example.com_x_a_1')
end

function M.test_trim()
  local cases = {
    {from = '', out = ''},
    {from = 'abc', out = 'abc'},
    {from = ' abc', out = 'abc'},
    {from = 'a b c', out = 'a b c'},
    {from = 'abc ', out = 'abc'},
    {from = ' \tabc \n', out = 'abc'},
  }
  for _, c in pairs(cases) do
    local got = xstring.trim(c.from)
    lu.assertEquals(got, c.out)
  end
end

function M.test_normalizews()
  local cases = {
    {from = '', out = ''},
    {from = 'abc', out = 'abc'},
    {from = ' abc', out = ' abc'},
    {from = 'a b c', out = 'a b c'},
    {from = 'abc ', out = 'abc '},
    {from = ' \tabc \n', out = ' abc '},
    {from = ' \ta  b     c \n', out = ' a b c '},
  }
  for _, c in pairs(cases) do
    local got = xstring.normalizews(c.from)
    lu.assertEquals(got, c.out)
  end
end

function M.test_capitalize()
  local cases = {
    {from = '', out = ''},
    {from = 'abc', out = 'Abc'},
    {from = 'a bc', out = 'A Bc'},
    {from = 'a b c', out = 'A B C'},
    {from = 'ab-cd ef:gh ij.kl', out = 'Ab-cd Ef:gh Ij.kl'},
  }
  for _, c in pairs(cases) do
    local got = xstring.capitalize(c.from)
    lu.assertEquals(got, c.out)
  end
end

function M.test_totime()
  for _ = 1, 10000 do
    local y = math.random(1900, 2100)
    local mo = math.random(1, 12)
    local d = math.random(1, 31)
    local h = math.random(0, 23)
    local mi = math.random(0, 59)
    local s = math.random(0, 59)

    if d > 28 and mo == 2 then
      d = 28
    elseif d == 31 and mo == 2 or mo == 4 or mo == 6 or mo == 9 or mo == 11 then
      d = 30
    end

    local input = string.format('%04d-%02d-%02d %02d:%02d:%02d', y, mo, d, h, mi, s)
    local t, err = xstring.totime(input)
    lu.assertNil(err)
    lu.assertIsNumber(t)
  end
end

return M
