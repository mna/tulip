local inspect = require 'inspect'

return function(cmd, args, opts)
  print(cmd)
  print(inspect(args))
  print(inspect(opts))
end
