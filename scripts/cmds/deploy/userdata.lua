return [[#!/usr/bin/env bash

# This is the cloud-init user data script used to setup a new machine
# in a consistent way.

set -euo pipefail

# upgrade all packages
dnf --assumeyes upgrade

# install the postgres 13 yum repository
dnf --assumeyes install  \
  https://download.postgresql.org/pub/repos/yum/reporpms/F-32-x86_64/pgdg-fedora-repo-latest.noarch.rpm

# install required packages
dnf --assumeyes install  \
  certbot                \
  fail2ban               \
  gcc                    \
  git                    \
  lsof                   \
  lua-devel              \
  luarocks               \
  openssl-devel          \
  postgresql13-devel     \
  postgresql13-server    \
  sendmail               \
  the_silver_searcher    \
  vim

# TODO: generate secrets

# configure firewalld
systemctl enable firewalld --now
firewall-cmd --zone=public --add-service=http --add-service=https
firewall-cmd --zone=public --add-service=http --add-service=https --permanent

# TODO: configure certbot

# initialize the database and start the service
/usr/pgsql-13/bin/postgresql-13-setup initdb
systemctl enable --now postgresql-13
# TODO: set postgres root password, update configuration as required
# TODO: install, build and enable the pg_cron extension

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

# install pre-required Lua dependencies (not handled by the rockspec
# application file).
luarocks install luarocks-fetch-gitrec
luarocks install luaossl 'CFLAGS=-DHAVE_EVP_KDF_CTX=1 -fPIC'
]]
