local App = {__name = 'web.core.app.App'}
App.__index = App

function App:use(...)
  local n = select('#', ...)
  for i = 1, n do
    local pkg = select(i, ...)
    pkg.init(self)
  end
end

function App:run()

end

local M = {}

function M.new(config)

end

return M

