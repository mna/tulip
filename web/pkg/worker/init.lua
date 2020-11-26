local cqueues = require 'cqueues'
local tcheck = require 'tcheck'
local xerror = require 'web.xerror'
local Semaphore = require 'web.Semaphore'

local MAX_ERRORS = 5

local function make_main(cfg)
  local min_sleep, max_sleep = (cfg.idle_sleep or 1), (cfg.max_idle_sleep or 60)
  local sema = Semaphore.new(cfg.max_concurrency or 1)
  local batch = cfg.dequeue_batch or 1
  local queues = cfg.queues or {}
  local errh = cfg.error_handler
  xerror.must(#queues > 0, 'no queue specified')

  return function(app, cq)
    local sleep
    local t = {max_receive = batch, errcount = 0}

    while true do
      for _, q in ipairs(queues) do
        t.queue = q
        local msgs, err = app:mqueue(t)
        if not msgs then
          t.errcount = t.errcount + 1
          if errh then
            if not errh(t, err) then return nil, err end
          else
            app:log('e', {pkg = 'worker', queue = q, error = err})
            if t.errcount >= MAX_ERRORS then
              xerror.throw(err)
            end
          end
        else
          t.errcount = 0
        end

        if (not msgs) or (#msgs == 0) then
          sleep = sleep or min_sleep
          cqueues.sleep(sleep)
          sleep = sleep * 2
          if sleep > max_sleep then sleep = max_sleep end
        else
          sleep = nil
          for _, msg in ipairs(msgs) do
            -- TODO: configure a semaphore timeout
            sema:acquire()
            cq:wrap(function()
              msg.app = app
              app(msg)
              sema:release()
            end)
          end
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
-- Requires: database, mqueue and wmiddleware packages
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
--   * error_handler: function = if set, called when an error occurs in
--     the worker look (e.g. when trying to dequeue a batch of messages).
--     The first argument is the t table used to call the dequeue App:mqueue
--     function, with an added field errcount that counts the number
--     of successive errors, and the second argument is the error itself.
--     If the handler returns true-ish, processing continues, otherwise
--     the main function returns. By default an error is raised after
--     5 consecutive errors, sleeping as when no message is received
--     in-between.
--     Errors that happen while processing a message are not handled
--     with this, use a handler.wrecover middleware for that.
--
-- It registers an App:main function and takes control of the process,
-- running until explicitly stopped.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)

  if not app.config.database then
    xerror.throw('no database registered')
  end
  if not app.config.mqueue then
    xerror.throw('no message queue registered')
  end
  if not app.config.wmiddleware then
    xerror.throw('no wmiddleware package registered')
  end
  app.main = make_main(cfg)
end

return M
