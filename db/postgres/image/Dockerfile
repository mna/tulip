FROM postgres:12

RUN set -ex                      \
      && apt-get --yes update    \
      && apt-get --yes install   \
        build-essential          \
        git                      \
        liblua5.3-dev            \
        lua5.3                   \
        postgresql-server-dev-12 \
      && cd /tmp                 \
      && git clone https://github.com/citusdata/pg_cron.git \
      && cd pg_cron              \
      && make                    \
      && make install            \
      && cd /tmp                 \
      && git clone https://github.com/pllua/pllua-ng.git    \
      && cd pllua-ng             \
      && make                    \
        PG_CONFIG=pg_config      \
        LUA_INCDIR=/usr/include/lua5.3 \
        LUALIB=-llua5.3          \
        LUAC=luac5.3             \
        LUA=lua5.3               \
        install                  \
      && make                    \
        -C hstore                \
        PG_CONFIG=pg_config      \
        LUA_INCDIR=/usr/include/lua5.3 \
        LUALIB=-llua5.3          \
        LUAC=luac5.3             \
        LUA=lua5.3               \
        install

COPY ./install_pg_cron.sql /docker-entrypoint-initdb.d/install_pg_cron.sql
COPY ./install_pllua.sql   /docker-entrypoint-initdb.d/install_pllua.sql
COPY ./install_hstore.sql   /docker-entrypoint-initdb.d/install_hstore.sql
