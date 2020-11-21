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
    if src then
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
  end
  return dst
end

-- Turns an array into a set, where each value in the array becomes a
-- key and the value is the number of times the key was found in the
-- array (which also behaves as a truthy value if the only goal is to
-- check if it was present). If multiple arrays are provided, the set
-- is the union of all arrays.
function M.toset(...)
  local n = select('#', ...)
  if n == 0 then return end

  local set = {}
  for i = 1, n do
    local ar = select(i, ...)
    if ar then
      for _, v in ipairs(ar) do
        set[v] = (set[v] or 0) + 1
      end
    end
  end
  return set
end

-- Turns a list of tables (most likely sets) into an array, adding
-- each key of each table in the resulting array. The order is undefined.
function M.toarray(...)
  local n = select('#', ...)
  if n == 0 then return end

  local ar = {}
  for i = 1, n do
    local set = select(i, ...)
    if set then
      for k in pairs(set) do
        table.insert(ar, k)
      end
    end
  end
  return ar
end

-- Returns the union of all the sets. The value is the number of sets
-- in which the key was found.
function M.setunion(...)
  local n = select('#', ...)
  if n == 0 then return end

  local dst = {}
  for i = 1, n do
    local set = select(i, ...)
    if set then
      for k in pairs(set) do
        dst[k] = (dst[k] or 0) + 1
      end
    end
  end
  return dst
end

-- Returns the difference of the first set with all other sets, i.e.
-- a set with only the keys found in the first but not in either of the
-- other sets. The values are set to true.
function M.setdiff(...)
  local n = select('#', ...)
  if n == 0 then return end

  local dst = {}
  local first = select(1, ...)
  if first then
    for k in pairs(first) do
      dst[k] = true
    end
  end

  for i = 2, n do
    local set = select(i, ...)
    if set then
      for k in pairs(set) do
        dst[k] = nil
      end
    end
  end
  return dst
end

return M
