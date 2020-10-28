local function bash()
  return [[#!/usr/bin/env bash

# This is the cloud-init user data script used to setup a new image
# in a consistent way.

set -euo pipefail
]]
end

local function dnf()
  return [[
# upgrade all packages
dnf --assumeyes upgrade

# install required packages
dnf --assumeyes install   \
  certbot                 \
  fail2ban                \
  gcc                     \
  git                     \
  libpq-devel             \
  lsof                    \
  lua-devel               \
  luarocks                \
  make                    \
  openssl-devel           \
  postgresql              \
  postgresql-server       \
  postgresql-server-devel \
  redhat-rpm-config       \
  sendmail                \
  the_silver_searcher     \
  vim
]]
end

local function secrets()
  return [[
mkdir -p /opt/secrets

# postgresql root password
openssl rand -base64 32 | tr '+/=' '._-' > /opt/secrets/pgroot_pwd
chmod 0600 /opt/secrets/pgroot_pwd

# postgresql pgpass file
echo -n 'localhost:*:*:postgres:' > /opt/secrets/pgpass
cat /opt/secrets/pgroot_pwd >> /opt/secrets/pgpass
chmod 0600 /opt/secrets/pgpass

# CSRF secret key
openssl rand -base64 32 | tr '+/=' '._-' > /opt/secrets/csrf_key
chmod 0600 /opt/secrets/csrf_key
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
postgresql-setup --initdb  \
  --unit postgresql        \
  --auth=scram-sha-256     \
  --locale=en_US           \
  --encoding=UTF8          \
  --pwfile=/opt/secrets/pgroot_pwd

cat >> /var/lib/pgsql/data/postgresql.conf <<EOF
shared_preload_libraries = 'pg_cron'
cron.database_name = 'postgres'
EOF

systemctl enable --now postgresql

PGPASSFILE=/opt/secrets/pgpass \
  psql --username postgres     \
       --command 'CREATE EXTENSION pg_cron;'
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
  secrets(),
  firewalld(),
  -- TODO: configure certbot
  fail2ban(),
  postgres(),
  luadeps(),
}
