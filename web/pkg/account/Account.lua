local Account = {__name = 'web.pkg.account.Account'}
Account.__index = Account

function Account:create()

end

function Account:login()

end

function Account:logout()

end

function Account:delete()

end

function Account:verify_email()

end

function Account:change_pwd()

end

function Account:reset_pwd()

end

function Account:change_email()

end

function Account:membership()

end

function Account.new()
  return setmetatable({}, Account)
end

return Account
