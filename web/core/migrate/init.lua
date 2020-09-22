local migrator = require 'web.core.migrate.migrator'

local M = {}

function M.init(app)
  app.migrator = migrator.new(app.config.database.connection_string)
  return true
end

return M
