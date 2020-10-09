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

return M
