-- adapted from https://github.com/wahern/cqueues/issues/214

local condition = require 'cqueues.condition'

local Semaphore = {__name = 'tulip.xsemaphore.Semaphore'}
Semaphore.__index = Semaphore

-- Returns a new Semaphore instance with a count of n, which
-- must be positive.
function Semaphore.new(n)
  n = n or 1
  assert(n > 0)
  local o = {cond = condition.new(), count = n, max = n}
  return setmetatable(o, Semaphore)
end

-- Acquires access from the semaphore. If timeout is set, waits
-- at most that time to acquire access, otherwise return nil and
-- an error message. Returns true on success.
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

-- Releases a previously acquired access, possibly unblocking processes
-- waiting on acquire. Returns true.
function Semaphore:release()
  assert(self.count < self.max)
  self.count = self.count + 1
  self.cond:signal()
  return true
end

return Semaphore
