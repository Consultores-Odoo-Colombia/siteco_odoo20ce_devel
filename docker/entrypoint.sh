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

# Primer arranque: inicializa la base con "base". Solo con el comando por defecto
# (no con `odoo shell`, `odoo -u ...`, etc.). ODOO_SKIP_INIT=1 lo desactiva.
# Odoo 20 crea solo las tablas orm_signaling_*, por eso se mira ir_module_module.
DB="${PGDATABASE:-odoo}"
if [ "$1" = "odoo" ] && [ $# -eq 1 ] && [ "${ODOO_SKIP_INIT:-0}" != "1" ]; then
    # Base inexistente -> se inicializa; cualquier otro error de psql -> se aborta
    # (no lanzar -i base sobre una base poblada por un fallo de conexión).
    if ! ready=$(psql -d "$DB" -Atc "select to_regclass('public.ir_module_module') is not null" 2>&1); then
        case "$ready" in
            *"does not exist"*) ready=f ;;
            *) echo "entrypoint: no se pudo comprobar la base $DB: $ready" >&2; exit 1 ;;
        esac
    fi
    if [ "$ready" != "t" ]; then
        # -i base deja admin/admin: sin contraseña para admin no se inicializa
        INIT_ADMIN_PW="${ODOO_INIT_ADMIN_PASSWORD:-${ODOO_ADMIN_PASSWD:-}}"
        if [ -z "$INIT_ADMIN_PW" ]; then
            echo "entrypoint: define ODOO_INIT_ADMIN_PASSWORD u ODOO_ADMIN_PASSWD para inicializar $DB" >&2
            exit 1
        fi
        echo "entrypoint: inicializando la base $DB (-i base)"
        odoo -d "$DB" -i base --stop-after-init --workers=0 --max-cron-threads=0 \
            ${ODOO_INIT_LANG:+--load-language="$ODOO_INIT_LANG"} || {
            echo "entrypoint: falló la inicialización de la base $DB" >&2
            exit 1
        }
        # La contraseña va por entorno, nunca interpolada en el código Python
        out=$(echo "import os; u = env.ref('base.user_admin'); u.password = os.environ['INIT_ADMIN_PW']; env.cr.commit(); print('ADMIN_PW_OK')" \
            | INIT_ADMIN_PW="$INIT_ADMIN_PW" odoo shell -d "$DB" --workers=0 --max-cron-threads=0 2>&1) || true
        unset INIT_ADMIN_PW
        case "$out" in
            *ADMIN_PW_OK*) echo "entrypoint: contraseña de admin fijada en $DB" ;;
            *)
                echo "$out" >&2
                # Base recién inicializada por este script: se borra para no dejar admin/admin
                echo "entrypoint: no se pudo fijar la contraseña de admin; se borra $DB" >&2
                dropdb --if-exists "$DB" || true
                exit 1
                ;;
        esac
    fi
fi

exec "$@"
