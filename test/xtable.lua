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

function M.test_toset()
  lu.assertNil(xtable.toset())
  lu.assertEquals(xtable.toset{'a', 'b', 'a', 'c'}, {a=2, b=1, c=1})
  lu.assertEquals(xtable.toset({'a'}, {'b'}, nil, {'a'}), {a=2, b=1})
end

function M.test_toarray()
  lu.assertNil(xtable.toarray())
  lu.assertItemsEquals(xtable.toarray{a=2, b=1, c=1}, {'a', 'b', 'c'})
  lu.assertItemsEquals(xtable.toarray({a=2}, {b=1}, nil, {a=3}), {'a', 'b', 'a'})
end

function M.test_setunion()
  lu.assertNil(xtable.setunion())
  lu.assertEquals(xtable.setunion({a=1}), {a=1})
  lu.assertEquals(xtable.setunion({a=1}, {b=2, c=3}, nil, {a=4}), {a=2, b=1, c=1})
end

function M.test_setdiff()
  lu.assertNil(xtable.setdiff())
  lu.assertEquals(xtable.setdiff(nil, {a=1}), {})
  lu.assertEquals(xtable.setdiff({}, {a=1}), {})
  lu.assertEquals(xtable.setdiff({a=1, b=2}, {a=1}), {b=true})
  lu.assertEquals(xtable.setdiff({a=1, b=2, c=3}, {a=1}, nil, {c=1}), {b=true})
end

return M
