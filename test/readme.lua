local lu = require 'luaunit'

local M = {}

function M.test_readme()
  local rm = assert(io.open('README.md'))

  local vars = {}
  for l in rm:lines() do
    local nm = string.match(l, '^%* `([^`]+)`:')
    if nm then
      vars[nm] = true
    end
  end
  rm:close()

  local env = assert(io.open('.envrc'))
  for l in env:lines() do
    local nm = string.match(l, '^export ([^=]+)=')
    if nm then
      if vars[nm] then
        vars[nm] = nil
      else
        vars[nm] = true
      end
    end
  end
  env:close()

  lu.assertNil(next(vars))
end

return M
