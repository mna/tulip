local lu = require 'luaunit'
local xtable = require 'web.xtable'

local M = {}

function M.test_merge_noarg()
  local v = xtable.merge()
  lu.assertNil(v)

  v = xtable.merge(function()
    return true
  end)
  lu.assertNil(v)
end

function M.test_merge_single()
  local t = {a=1}
  local v = xtable.merge(t)
  lu.assertEquals(v, t)

  v = xtable.merge(t, function()
    return false
  end)
  lu.assertEquals(v, t)
end

function M.test_merge_two()
  local t1 = {a=1, b=2}
  local t2 = {a=3, c=4}

  local v = xtable.merge(t1, t2)
  lu.assertEquals(v, {a=3, b=2, c=4})
  lu.assertEquals(v, t1)
end

function M.test_merge_many()
  local t1 = {a=1, b=2}
  local t2 = {a=3, c=4, d=5}
  local t3 = {a=6, b=7, d=8, e=9}

  local v = xtable.merge({}, t1, t2, t3)
  lu.assertEquals(v, {a=6, b=7, c=4, d=8, e=9})
  lu.assertNotEquals(v, t1)
end

function M.test_merge_many_filtered()
  local t1 = {a=1, b=2}
  local t2 = {a=3, c=4, d=5}
  local t3 = {a=6, b=7, d=8, e=9}

  local v = xtable.merge(t1, t2, t3, function(_, _, k)
    return k ~= 'd'
  end)
  lu.assertEquals(v, {a=6, b=7, c=4, e=9})
  lu.assertEquals(v, t1)
end

return M
