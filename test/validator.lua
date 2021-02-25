local lu = require 'luaunit'
local xerror = require 'tulip.xerror'
local App = require 'tulip.App'

local M = {}

function M.test_validate_integer()
  local app = App{
    validator = {}
  }
  app.main = function()
    local ok, ev = app:validate(nil, {})
    lu.assertEquals(ev, {})
    lu.assertTrue(ok)

    ok, ev = app:validate({}, {})
    lu.assertEquals(ev, {})
    lu.assertTrue(ok)

    ok, ev = app:validate({x=1}, {})
    lu.assertEquals(ev, {})
    lu.assertTrue(ok)

    ok, ev = app:validate({x=1}, {x = {type = 'integer'}})
    lu.assertEquals(ev, {x=1})
    lu.assertTrue(ok)

    ok, ev = app:validate({x=1, y='a'}, {x = {type = 'integer', min = 2}})
    lu.assertNil(ok)
    lu.assertTrue(xerror.is(ev, 'EINVAL'))
    lu.assertEquals(ev.field, 'x')
    lu.assertEquals(ev.value, 1)

    ok, ev = app:validate({x=10, y='a'}, {x = {type = 'integer', min = 2, max = 5}})
    lu.assertNil(ok)
    lu.assertTrue(xerror.is(ev, 'EINVAL'))

    ok, ev = app:validate({x=10, y='a'}, {x = {type = 'integer', min = 2, max = 50}})
    lu.assertEquals(ev, {x=10})
    lu.assertTrue(ok)

    ok, ev = app:validate({x=10}, {x = {type = 'integer', required = true}})
    lu.assertEquals(ev, {x=10})
    lu.assertTrue(ok)

    ok, ev = app:validate({x=nil}, {x = {type = 'integer', required = true}})
    lu.assertNil(ok)
    lu.assertTrue(xerror.is(ev, 'EINVAL'))

    ok, ev = app:validate({x=7}, {x = {type = 'integer', enum = {1, 3, 5}}})
    lu.assertNil(ok)
    lu.assertTrue(xerror.is(ev, 'EINVAL'))

    ok, ev = app:validate({x=3}, {x = {type = 'integer', enum = {1, 3, 5}}})
    lu.assertEquals(ev, {x=3})
    lu.assertTrue(ok)

    ok, ev = app:validate({x='3'}, {x = {type = 'integer'}})
    lu.assertEquals(ev, {x=3})
    lu.assertTrue(ok)

    ok, ev = app:validate({x=''}, {x = {type = 'integer'}})
    lu.assertNil(ok)
    lu.assertTrue(xerror.is(ev, 'EINVAL'))

    return true
  end
  assert(app:run())
end

function M.test_validate_string()
  local app = App{
    validator = {}
  }
  app.main = function()
    local ok, ev = app:validate({x=1}, {x = {type = 'string'}})
    lu.assertEquals(ev, {x='1'})
    lu.assertTrue(ok)

    ok, ev = app:validate({x='abc'}, {x = {type = 'string', min=5}})
    lu.assertTrue(xerror.is(ev, 'EINVAL'))
    lu.assertNil(ok)
    lu.assertEquals(ev.field, 'x')
    lu.assertEquals(ev.value, 'abc')

    ok, ev = app:validate({x='abc'}, {x = {type = 'string', min=1, max=2}})
    lu.assertTrue(xerror.is(ev, 'EINVAL'))
    lu.assertNil(ok)

    ok, ev = app:validate({x='abcd'}, {x = {type = 'string', min=1, max=5}})
    lu.assertEquals(ev, {x='abcd'})
    lu.assertTrue(ok)

    ok, ev = app:validate({x='😼🌊🤡'}, {x = {type = 'string', min=1, max=5}})
    lu.assertTrue(xerror.is(ev, 'EINVAL'))
    lu.assertNil(ok)

    ok, ev = app:validate({x='😼🌊🤡'}, {x = {type = 'string', min=1, max=20, mincp=4}})
    lu.assertTrue(xerror.is(ev, 'EINVAL'))
    lu.assertNil(ok)

    ok, ev = app:validate({x='😼🌊🤡'}, {x = {type = 'string', min=1, max=20, mincp=2, maxcp=5}})
    lu.assertEquals(ev, {x='😼🌊🤡'})
    lu.assertTrue(ok)

    ok, ev = app:validate({x=' \t\n a \t\n'}, {x = {type = 'string', min=1, max=10, mincp=2, maxcp=10}})
    lu.assertTrue(xerror.is(ev, 'EINVAL'))
    lu.assertNil(ok)

    ok, ev = app:validate({x=' \t\n a \t\n'}, {x = {type = 'string', min=1, max=10, mincp=2, maxcp=10, allow_cc=true}})
    lu.assertEquals(ev, {x=' \t\n a \t\n'})
    lu.assertTrue(ok)

    ok, ev = app:validate({x=' \t\n a \t\n'}, {x = {type = 'string', min=1, max=10, mincp=2, maxcp=10, trim_ws=true}})
    lu.assertTrue(xerror.is(ev, 'EINVAL'))
    lu.assertNil(ok)

    ok, ev = app:validate({x=' \t\n ab \t\n'}, {x = {type = 'string', min=1, max=10, mincp=2, maxcp=10, trim_ws=true}})
    lu.assertEquals(ev, {x='ab'})
    lu.assertTrue(ok)

    ok, ev = app:validate({x='a   b    c '}, {x = {type = 'string', maxcp=3, trim_ws=true}})
    lu.assertTrue(xerror.is(ev, 'EINVAL'))
    lu.assertNil(ok)

    ok, ev = app:validate({x='a   b    c '}, {x = {type = 'string', maxcp=8, normalize_ws=true}})
    lu.assertEquals(ev, {x='a b c '})
    lu.assertTrue(ok)

    ok, ev = app:validate({x='a   b    c '}, {x = {type = 'string', maxcp=8, normalize_ws=true, trim_ws=true}})
    lu.assertEquals(ev, {x='a b c'})
    lu.assertTrue(ok)

    ok, ev = app:validate({x='with1number'}, {x = {type = 'string', pattern='%d'}})
    lu.assertEquals(ev, {x='with1number'})
    lu.assertTrue(ok)

    ok, ev = app:validate({x='withoutnumber'}, {x = {type = 'string', pattern='%d'}})
    lu.assertTrue(xerror.is(ev, 'EINVAL'))
    lu.assertNil(ok)

    ok, ev = app:validate({x='a'}, {x = {type = 'string', enum={'a', 'b', 'c'}}})
    lu.assertEquals(ev, {x='a'})
    lu.assertTrue(ok)

    ok, ev = app:validate({x='d'}, {x = {type = 'string', enum={'a', 'b', 'c'}}})
    lu.assertTrue(xerror.is(ev, 'EINVAL'))
    lu.assertNil(ok)

    ok, ev = app:validate({x=nil}, {x = {type = 'string', required=true}})
    lu.assertTrue(xerror.is(ev, 'EINVAL'))
    lu.assertNil(ok)

    return true
  end
  assert(app:run())
end

function M.test_validate_boolean()
  local app = App{
    validator = {}
  }
  app.main = function()
    local ok, ev = app:validate({x=1}, {x = {type = 'boolean'}})
    lu.assertEquals(ev, {x=true})
    lu.assertTrue(ok)

    ok, ev = app:validate({x=nil}, {x = {type = 'boolean'}})
    lu.assertEquals(ev, {x=false})
    lu.assertTrue(ok)

    ok, ev = app:validate({x=1}, {x = {type = 'boolean', true_value='ok'}})
    lu.assertEquals(ev, {x=false})
    lu.assertTrue(ok)

    ok, ev = app:validate({x='ok'}, {x = {type = 'boolean', true_value='ok'}})
    lu.assertEquals(ev, {x=true})
    lu.assertTrue(ok)

    ok, ev = app:validate({x=1}, {x = {type = 'boolean', false_value='ko'}})
    lu.assertEquals(ev, {x=true})
    lu.assertTrue(ok)

    ok, ev = app:validate({x='ko'}, {x = {type = 'boolean', false_value='ko'}})
    lu.assertEquals(ev, {x=false})
    lu.assertTrue(ok)

    ok, ev = app:validate({x='ok'}, {x = {type = 'boolean', true_value = 'ok', false_value='ko'}})
    lu.assertEquals(ev, {x=true})
    lu.assertTrue(ok)

    ok, ev = app:validate({x='ko'}, {x = {type = 'boolean', true_value = 'ok', false_value='ko'}})
    lu.assertEquals(ev, {x=false})
    lu.assertTrue(ok)

    ok, ev = app:validate({x=nil}, {x = {type = 'boolean', true_value = 'ok', false_value='ko'}})
    lu.assertTrue(xerror.is(ev, 'EINVAL'))
    lu.assertNil(ok)
    lu.assertEquals(ev.field, 'x')

    ok, ev = app:validate({x=1}, {x = {type = 'boolean', true_value = 'ok', false_value='ko'}})
    lu.assertTrue(xerror.is(ev, 'EINVAL'))
    lu.assertNil(ok)
    lu.assertEquals(ev.field, 'x')
    lu.assertEquals(ev.value, 1)

    return true
  end
  assert(app:run())
end

return M
