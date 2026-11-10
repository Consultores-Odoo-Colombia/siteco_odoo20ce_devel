#!/bin/sh
set -e

# Permite `docker run imagen --workers=4` ademas de `docker run imagen odoo ...`
if [ "${1#-}" != "$1" ]; then
    set -- odoo "$@"
fi

if [ "$1" = "odoo" ] && [ -n "${PGHOST}" ]; then
    tries=0
    until pg_isready -q -h "${PGHOST}" -p "${PGPORT:-5432}"; do
        tries=$((tries + 1))
        if [ "${tries}" -ge 60 ]; then
            echo "entrypoint: PostgreSQL no responde en ${PGHOST}:${PGPORT:-5432}" >&2
            exit 1
        fi
        sleep 1
    done
fi

exec "$@"
