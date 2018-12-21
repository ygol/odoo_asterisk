#!/bin/bash
set -e

# allow to customize the UID of the odoo user,
# so we can share the same than the host's.
# If no user id is set, we use 999
USER_ID=${LOCAL_USER_ID:-999}

echo "Starting with UID : $USER_ID"
id -u odoo &> /dev/null || useradd --shell /bin/bash -u $USER_ID -o -c "" -m odoo

BINDIR=$(dirname $0)
BASEDIR=$(readlink -f $BINDIR/..)

export PGHOST=${DB_HOST}
export PGPORT=${DB_PORT}
export PGUSER=${DB_USER}
export PGPASSWORD=${DB_PASSWORD}
export PGDATABASE=${DB_NAME}

# Accepted values for DEMO: True / False
# Odoo use a reverse boolean for the demo, which is not handy,
# that's why we propose DEMO which exports WITHOUT_DEMO used in
# openerp.cfg.tmpl
if [ -z "$DEMO" ]; then
  DEMO=False
fi
case "$(echo "${DEMO}" | tr '[:upper:]' '[:lower:]' )" in
  "false")
    echo "Running without demo data"
    export WITHOUT_DEMO=all
    ;;
  "true")
    echo "Running with demo data"
    export WITHOUT_DEMO=
    ;;
  # deprecated options:
  "odoo")
    echo "Running with demo data"
    echo "DEMO=odoo is deprecated, use DEMO=True"
    export WITHOUT_DEMO=
    ;;
  "none")
    echo "Running without demo data"
    echo "DEMO=none is deprecated, use DEMO=False"
    export WITHOUT_DEMO=all
    ;;
  "scenario")
    echo "DEMO=scenario is deprecated, use DEMO=False and MARABUNTA_MODE=demo with a demo mode in migration.yml"
    exit 1
    ;;
  "all")
    echo "DEMO=all is deprecated, use DEMO=True and MARABUNTA_MODE=demo with a demo mode in migration.yml"
    exit 1
    ;;
  *)
    echo "Value '${DEMO}' for DEMO is not a valid value in 'False', 'True'"
    exit 1
    ;;
esac

# Create configuration file from the template
CONFIGDIR=$BASEDIR/etc
if [ -e $CONFIGDIR/openerp.cfg.tmpl ]; then
  dockerize -template $CONFIGDIR/openerp.cfg.tmpl:$CONFIGDIR/odoo.cfg
fi
if [ -e $CONFIGDIR/odoo.cfg.tmpl ]; then
  dockerize -template $CONFIGDIR/odoo.cfg.tmpl:$CONFIGDIR/odoo.cfg
fi

if [ ! -f "$CONFIGDIR/odoo.cfg" ]; then
  echo "Error: one of etc/openerp.cfg.tmpl, etc/odoo.cfg.tmpl, etc/odoo.cfg is required"
  exit 1
fi

# Wait until postgres is up
$BINDIR/wait_postgres.sh

mkdir -p /data/odoo/{addons,filestore,sessions}
if [ ! "$(stat -c '%U' /data/odoo)" = "odoo" ]; then
  chown -R odoo: /data/odoo
fi
if [ ! "$(stat -c '%U' /var/log/odoo)" = "odoo" ]; then
  chown -R odoo: /var/log/odoo
fi

BASE_CMD=$(basename $1)
if [ "$BASE_CMD" = "odoo" ] || [ "$BASE_CMD" = "odoo.py" ] ; then

  BEFORE_MIGRATE_ENTRYPOINT_DIR=/opt/odoo/before-migrate-entrypoint.d
  if [ -d "$BEFORE_MIGRATE_ENTRYPOINT_DIR" ]; then
    /bin/run-parts --verbose "$BEFORE_MIGRATE_ENTRYPOINT_DIR"
  fi

  if [ -z "$MIGRATE" -o "$MIGRATE" = True ]; then
      gosu odoo migrate
  fi

  START_ENTRYPOINT_DIR=/opt/odoo/start-entrypoint.d
  if [ -d "$START_ENTRYPOINT_DIR" ]; then
    /bin/run-parts --verbose "$START_ENTRYPOINT_DIR"
  fi

  exec gosu odoo "$@"
fi

exec "$@"
