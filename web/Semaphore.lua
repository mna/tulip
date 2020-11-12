-- from https://github.com/wahern/cqueues/issues/214

local condition = require 'cqueues.condition'

local Semaphore = {__name = 'web.xsemaphore.Semaphore'}
Semaphore.__index = Semaphore

function Semaphore.new(n)
  n = n or 1
  assert(n > 0)
  local o = {cond = condition.new(), count = n}
  return setmetatable(o, Semaphore)
end

function Semaphore:acquire(timeout)
  while self.count == 0 do
    local ok = self.cond:wait(timeout)
    if not ok then
      return nil, 'timed out'
    end
  end
  assert(self.count > 0)
  self.count = self.count - 1
  return true
end

function Semaphore:release()
  self.count = self.count + 1
  self.cond:signal()
  return true
end

return Semaphore
