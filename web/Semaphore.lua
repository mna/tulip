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

function Semaphore:acquire()
  while self.count == 0 do
    self.cond:wait()
  end
  assert(self.count > 0)
  self.count = self.count - 1
end

function Semaphore:release()
  self.count = self.count + 1
  self.cond:signal()
end

return Semaphore
