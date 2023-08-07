FROM postgres:15

RUN set -ex                      \
      && apt-get --yes update    \
      && apt-get --yes install   \
        build-essential          \
        git                      \
        liblua5.4-dev            \
        lua5.4                   \
        postgresql-server-dev-15 \
      && cd /tmp                 \
      && git clone https://github.com/citusdata/pg_cron.git \
      && cd pg_cron              \
      && make                    \
      && make install

COPY ./install_pg_cron.sql /docker-entrypoint-initdb.d/install_pg_cron.sql
