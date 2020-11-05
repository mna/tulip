local cqueues = require 'cqueues'
local tcheck = require 'tcheck'
local Semaphore = require 'web.Semaphore'

local function make_main(cfg)
  local min_sleep, max_sleep = (cfg.idle_sleep or 1), (cfg.max_idle_sleep or 60)
  local sema = Semaphore.new(cfg.max_concurrency or 1)
  local batch = cfg.dequeue_batch or 1
  local queues = cfg.queues or {}
  assert(#queues > 0, 'no queue specified')

  return function(app, cq)
    local sleep
    local t = {max_receive = batch}

    while true do
      for _, q in ipairs(queues) do
        t.queue = q
        local msgs, err = app:mqueue(t)
        if not msgs then
          -- log error (or error handler?) and treat as #msgs == 0?
        end

        if #msgs == 0 then
          sleep = sleep or min_sleep
          cqueues.sleep(sleep)
          sleep = sleep * 2
          if sleep > max_sleep then sleep = max_sleep end
        else
          sleep = nil
          -- TODO: handler... then mark as done on success
        end
      end
    end
  end
end

local M = {}

-- The worker package registers an App:main method that processes
-- messages from the message queue (which may include messages
-- scheduled with cron).
--
-- Requires: database and mqueue packages
-- Config:
--   * idle_sleep: number = seconds to sleep when there are no
--     messages to process. The first time no messages are available,
--     it will sleep for idle_sleep, and double this sleep time on
--     each loop without message, up to max_idle_sleep, until there
--     are messages to process. Defaults to 1.
--   * max_idle_sleep: number = maximum number of seconds to sleep
--     when there are no messages to process. Defaults to 60.
--   * queues: array of strings = name of queues to process, which
--     can include name of cron jobs, which are essentially queues.
--   * max_concurrency: number = maximum number of concurrent processing
--     of messages. Defaults to 1 (for maximum control over TTL).
--   * dequeue_batch: number = maximum number of messages to dequeue at
--     once from a queue. Keep in mind that this is per queue that the
--     worker will process, and the time-to-live of the message starts
--     at the moment it is dequeued. Defaults to 1.
--
-- It registers an App:main function and takes control of the process,
-- running until explicitly stopped.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)

  if not app.config.database then
    error('no database registered')
  end
  if not app.config.mqueue then
    error('no message queue registered')
  end
  app.main = make_main(cfg)
end

return M
