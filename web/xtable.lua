local M = {}

-- The merge function merges an arbitrary number of tables into
-- the first table, in the order provided (rightmost table wins).
-- To leave existing tables unchanged, pass a new
-- table as first value. If the last value is a function, it is used
-- as filter to select the fields to merge, and receives the destination
-- table, source table, key and value as arguments, and accepts the
-- key-value pair if it returns true.
--
-- It returns the destination table (the first provided table), or nil
-- if no table is provided.
function M.merge(...)
  local n = select('#', ...)
  if n == 0 then return end

  local filter
  local last = select(n, ...)
  if type(last) == 'function' then
    filter = last
    n = n - 1
  end
  if n == 0 then return end

  local dst = select(1, ...)
  for i = 2, n do
    local src = select(i, ...)
    for k, v in pairs(src) do
      local ok = true
      if filter then
        ok = filter(dst, src, k, v)
      end
      if ok then
        dst[k] = v
      end
    end
  end
  return dst
end

return M
