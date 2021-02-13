local lu = require 'luaunit'
local xstring = require 'tulip.xstring'

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

function M.test_decode_header()
  local cases = {
    {from = '', out = {}},
    {from = 'a', out = {{value = 'a'}}},
    {from = '  b  ', out = {{value = 'b'}}},
    {from = 'b, c  , d  ', out = {{value = 'b'}, {value = 'c'}, {value = 'd'}}},
    {from = 'x;a=1', out = {{value = 'x', a = '1'}}},
    {from = ' x ; a = 2 ', out = {{value = 'x', a = '2'}}},
    {from = ' x ; a = 1;b=2 ', out = {{value = 'x', a = '1', b = '2'}}},
    {from = ' x ; a = 1;b=2 ;c ', out = {{value = 'x', a = '1', b = '2', c = true}}},
    {from = 'x;a=1;b=2,y;c=3,z', out = {{value = 'x', a = '1', b = '2'}, {value = 'y', c = '3'}, {value = 'z'}}},
    {from = 'form-data; name="myFile"; filename="foo.txt"',
      out = {{value = 'form-data', name = '"myFile"', filename = '"foo.txt"'}}},
  }
  for _, c in pairs(cases) do
    local got = xstring.decode_header(c.from)
    lu.assertEquals(got, c.out)
  end
end

function M.test_header_value_matches()
  local cases = {
    {h = '', v = '', out = nil},
    {h = 'x', v = '', out = {1}},
    {h = 'x', v = 'y', out = nil},
    {h = 'x', v = 'x', out = {1}},
    {h = 'abc, def, ghi', v = 'e', out = {2}},
    {h = 'abcd, defg, ghij', v = 'g', out = {2,3}},
    {h = 'abcd, defg, ghij', v = 'z', out = nil},
    {h = 'abcd, de1g, ghij', v = '%d', out = {2}},
    {h = 'abcd, de1g, ghij', v = '%p', out = nil},
    {h = 'abcd, de1g, ghij', v = 'g', plain = true, out = {2, 3}},
    {h = 'abc, def, ghi', v = {'a', 'b', 'e'}, out = {1, 2}},
  }
  for _, c in pairs(cases) do
    local got = xstring.header_value_matches(c.h, c.v, c.plain)
    lu.assertEquals(got, c.out)
  end
end

function M.test_header_directive_matches()
  local dir = 'x'
  local cases = {
    {h = '', v = '', out = nil},
    {h = 'a; x', v = '', out = nil},
    {h = 'a; x=z', v = '', out = {1}},
    {h = 'a; x=z', v = 'y', out = nil},
    {h = 'a; x=z', v = 'z', out = {1}},
    {h = 'a; x=abc, b; x=def, c; y=def', v = 'e', out = {2}},
    {h = 'a; x=abc, b; x=def, c; y=def', v = {'a', 'b', 'e'}, out = {1, 2}},
    {h = 'a; x=abc, b; x=def, c; y=def', v = 'DEF', out = nil},
    {h = 'a; x=abc, b; x=def, c; y=def', v = xstring.ipat('DEF'), out = {2}},
  }
  for _, c in pairs(cases) do
    local got = xstring.header_directive_matches(c.h, dir, c.v, c.plain)
    lu.assertEquals(got, c.out)
  end
end

return M
