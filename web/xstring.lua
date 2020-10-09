local M = {}

-- turn pat into a case-insensitive pattern.
function M.ipat(pat)
  -- restriction: pat must not contain a [..] range.
  assert(not string.find(pat, '[', 1, true), 'pattern cannot contain a [set]')

  -- find an optional '%' (group 1) followed by any character (group 2)
  -- NOTE: must be in parens to return only the first value.
  return (string.gsub(pat, '(%%?)(.)', function(percent, letter)
    if percent ~= "" or not string.match(letter, '%a') then
      -- if the '%' matched, or `letter` is not a letter, return "as is"
      return percent .. letter
    else
      -- else, return a case-insensitive character class of the matched letter
      return string.format('[%s%s]', string.lower(letter), string.upper(letter))
    end
  end))
end

-- escape s to return a valid file name.
function M.escapefile(s)
  return string.gsub(s, '([^%w%.]+)', '_')
end

-- trim leading and trailing whitespace from s.
function M.trim(s)
  return string.gsub(s, '^%s*(.-)%s*$', '%1')
end

-- ensures all whitespace in s is normalized to a single
-- space character.
function M.normalizews(s)
  return string.gsub(s, '%s+', ' ')
end

-- makes each first letter of each word in s uppercase, the rest
-- lowercase.
function M.capitalize(s)
  s = string.lower(s)
  return string.gsub(s, '%f[%g](%g)', function(c)
    return string.upper(c)
  end)
end

return M
