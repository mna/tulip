local cqueues = require 'cqueues'
local tcheck = require 'tcheck'
local xerror = require 'tulip.xerror'
local Semaphore = require 'tulip.Semaphore'

local function default_error(t, err, app)
  app:log('e', {pkg = 'worker', queue = t.queue, error = tostring(err)})
end

local function make_main(cfg)
  local min_sleep, max_sleep = (cfg.idle_sleep or 1), (cfg.max_idle_sleep or 60)
  local sema = Semaphore.new(cfg.max_concurrency or 1)
  local batch = cfg.dequeue_batch or 1
  local queues = cfg.queues or {}
  local errh = cfg.error_handler or default_error
  xerror.must(#queues > 0, 'no queue specified')

  return function(app, cq)
    cq:wrap(function()
      local sleep
      local t = {max_receive = batch}

      while true do
        local iter_count = 0

        for _, q in ipairs(queues) do
          t.queue = q
          local msgs, err = app:mqueue(t)
          if not msgs then
            errh(t, err, app)
          end

          -- log only if it got some messages
          if msgs and #msgs > 0 then
            app:log('i', {pkg = 'worker', queue = q, count = #msgs})
          end

          if msgs and #msgs > 0 then
            iter_count = iter_count + #msgs
            for _, msg in ipairs(msgs) do
              sema:acquire()
              cq:wrap(function()
                msg.app = app
                app(msg)
                sema:release()
              end)
            end
          end
        end

        -- if no queue yielded any message, sleep
        if iter_count == 0 then
          sleep = sleep or min_sleep
          cqueues.sleep(sleep)
          sleep = sleep * 2
          if sleep > max_sleep then sleep = max_sleep end
        else
          sleep = nil
        end
      end
    end)
    return xerror.io(cq:loop())
  end
end

local M = {
  requires = {
    'tulip.pkg.mqueue',
    'tulip.pkg.wmiddleware',
  },
}

-- The worker package registers an App:main method that processes
-- messages from the message queue (which may include messages
-- scheduled with cron).
--
-- Requires: mqueue and wmiddleware packages
--
-- Config:
--
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
--     function, the second argument is the error itself and the third is
--     the app instance.
--     By default, errors are logged and the main loop sleeps
--     as if there were no results to process.
--     Errors that happen while processing a message are not handled
--     with this, use a handler.wrecover middleware for that.
--
-- Methods and Fields:
--
-- App:main(cq)
--
--   Takes control of the main loop of the App. Starts the worker process,
--   calling the App instance with the Message instances for each message
--   to process. See the mqueue package's documentation for the Message
--   instance reference.
--
--   > cq: userdata = the cqueue to use for the loop
--
function M.register(cfg, app)
  tcheck({'table', 'tulip.App'}, cfg, app)
  app.main = make_main(cfg)
end

return M
