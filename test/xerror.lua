local lu = require 'luaunit'
local xerror = require 'web.xerror'
local xpgsql = require 'xpgsql'

local M = {}

function M.test_io()
  local ok, err = xerror.io(io.open('does-not-exist'))
  lu.assertNil(ok)
  lu.assertTrue(xerror.is(err, 'EIO'))
  lu.assertFalse(xerror.is_sql_state(err, '.'))
  lu.assertEquals(tostring(err), 'does-not-exist: No such file or directory')

  err = xerror.ctx(err, 'test', {op = 'open', message = 'yy'})
  lu.assertEquals(tostring(err), 'test: does-not-exist: No such file or directory')
  err = xerror.ctx(err, 'again', {op = 'close', message = 'zz'})
  lu.assertEquals(tostring(err), 'again: test: does-not-exist: No such file or directory')

  lu.assertEquals(err.op, 'open')
end

function M.test_db()
  local conn = assert(xpgsql.connect())

  local ok, err = xerror.db(conn:query[[ SELECT 1 FROM does_not_exist ]])
  lu.assertNil(ok)
  lu.assertTrue(xerror.is(err, 'EDB', '^ESQ.$'))
  lu.assertTrue(xerror.is_sql_state(err, '42P.*'))
  lu.assertStrContains(tostring(err), '"does_not_exist" does not exist')

  conn:close()
end

function M.test_no_msg()
  local ok, err = xerror.db(nil)
  lu.assertNil(ok)
  lu.assertTrue(xerror.is(err, 'EDB'))
  lu.assertEquals(tostring(err), '<error>')

  err = xerror.ctx(err, 'test', {message = 'oops'})
  lu.assertEquals(tostring(err), 'test: oops')
end

function M.test_throw()
  lu.assertErrorMsgContains('nope', function() xerror.throw('nope') end)
  lu.assertErrorMsgContains('xyz', function() xerror.throw('nope %s', 'xyz') end)
end

function M.test_must()
  local f_ok = function() return 1, 2, 3 end
  local f_err = function() return nil, 'nope' end
  local f_err2 = function() return nil, 'nope %s', 'xyz' end
  local f_err3 = function() return xerror.io(io.open('does-not-exist')) end

  local v1, v2, v3 = xerror.must(f_ok())
  lu.assertEquals(v1, 1)
  lu.assertEquals(v2, 2)
  lu.assertEquals(v3, 3)

  lu.assertErrorMsgContains('nope', function() xerror.must(f_err()) end)
  lu.assertErrorMsgContains('xyz', function() xerror.must(f_err2()) end)
  lu.assertErrorMsgContains('does-not-exist', function() xerror.must(f_err3()) end)
end

return M
