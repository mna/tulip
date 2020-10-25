local function bash()
  return [[#!/usr/bin/env bash

# This is the cloud-init user data script used to setup a new machine
# in a consistent way.

set -euo pipefail
]]
end

local function dnf()
  return [[
# upgrade all packages
dnf --assumeyes upgrade

# TODO: actually better use postgres12 as bundled in fedora, too much
# trouble fixing unexpected paths and stuff with pg_cron

# install the postgres 13 yum repository
dnf --assumeyes install  \
  https://download.postgresql.org/pub/repos/yum/reporpms/F-32-x86_64/pgdg-fedora-repo-latest.noarch.rpm

# install required packages
dnf --assumeyes install  \
  certbot                \
  fail2ban               \
  gcc                    \
  git                    \
  libpq5-devel           \
  lsof                   \
  lua-devel              \
  luarocks               \
  make                   \
  openssl-devel          \
  postgresql13-devel     \
  postgresql13-server    \
  sendmail               \
  the_silver_searcher    \
  vim
]]
end

local function firewalld()
  return [[
# configure firewalld
systemctl enable firewalld --now
firewall-cmd --zone=public --add-service=http --add-service=https
firewall-cmd --zone=public --add-service=http --add-service=https --permanent
]]
end

local function fail2ban()
  return [[
# configure fail2ban
cp /etc/fail2ban/fail2ban.conf /etc/fail2ban/fail2ban.local
sed -i 's/^logtarget =.*/logtarget = sysout/g' /etc/fail2ban/fail2ban.local

cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1
# NOTE: setting action that sends email, but sendmail won't work without
# a valid MX and hostname.
action = %(action_mwl)s

[sshd]
enabled = true
EOF

# enabling sendmail, even though it won't work without valid MX/hostname.
systemctl enable sendmail
systemctl enable fail2ban

# TODO: custom log scanning for app abuse?
]]
end

local function postgres()
  return [[
# build and install pg_cron
pushd /tmp
git clone https://github.com/citusdata/pg_cron.git
cd pg_cron
make && make install
popd

# initialize the database and start the service
/usr/pgsql-13/bin/postgresql-13-setup initdb
systemctl enable --now postgresql-13
psql --username postgres --command 'CREATE EXTENSION pg_cron;'

# TODO: set postgres root password, update configuration as required
]]
end

local function luadeps()
  return [[
# install pre-required Lua dependencies (not handled by the rockspec
# application file).
luarocks install luarocks-fetch-gitrec
luarocks install luaossl 'CFLAGS=-DHAVE_EVP_KDF_CTX=1 -fPIC'
]]
end

return table.concat{
  bash(),
  dnf(),
  -- TODO: generate secrets
  firewalld(),
  -- TODO: configure certbot
  fail2ban(),
  postgres(),
  luadeps(),
}
