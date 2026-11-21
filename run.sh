#!/bin/bash
# Runs as the wger user. Sets Railway defaults, prepares the database, then runs
# gunicorn + Celery (worker with embedded beat, threads pool) + Caddy. If any of them stops,
# the container exits non-zero so Railway's ON_FAILURE policy restarts it.
set -euo pipefail
cd /home/wger/src
DATA=${WGER_DATA_DIR:-/data}

die() { echo "wger-railway: $*" >&2; exit 1; }
[ -n "${DATABASE_URL:-}" ] || die "DATABASE_URL is not set (reference your Postgres service)"
[ -n "${REDIS_URL:-}" ] || die "REDIS_URL is not set (reference your Redis service)"
[ -n "${SECRET_KEY:-}" ] || die "SECRET_KEY is not set"
[ -n "${WGER_ADMIN_PASSWORD:-}" ] || die "WGER_ADMIN_PASSWORD is not set"

# --- Wiring (Railway references) ---------------------------------------------
export PS_DATABASE_URI="$DATABASE_URL"
REDIS_BASE=${REDIS_URL%/}
export DJANGO_CACHE_BACKEND=${DJANGO_CACHE_BACKEND:-django_redis.cache.RedisCache}
export DJANGO_CACHE_CLIENT_CLASS=${DJANGO_CACHE_CLIENT_CLASS:-django_redis.client.DefaultClient}
export DJANGO_CACHE_LOCATION=${DJANGO_CACHE_LOCATION:-$REDIS_BASE/1}
export DJANGO_CACHE_TIMEOUT=${DJANGO_CACHE_TIMEOUT:-1296000}
export CELERY_BROKER=${CELERY_BROKER:-$REDIS_BASE/2}
export CELERY_BACKEND=${CELERY_BACKEND:-$REDIS_BASE/2}

# --- Public URL and proxy ----------------------------------------------------
if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
  export SITE_URL=${SITE_URL:-https://$RAILWAY_PUBLIC_DOMAIN}
  export CSRF_TRUSTED_ORIGINS=${CSRF_TRUSTED_ORIGINS:-https://$RAILWAY_PUBLIC_DOMAIN}
fi
export SITE_URL=${SITE_URL:-http://localhost:${PORT:-8080}}
export CSRF_TRUSTED_ORIGINS=${CSRF_TRUSTED_ORIGINS:-$SITE_URL}
export X_FORWARDED_PROTO_HEADER_SET=${X_FORWARDED_PROTO_HEADER_SET:-True}
export NUMBER_OF_PROXIES=${NUMBER_OF_PROXIES:-1}
# Login lockouts (django-axes) per real visitor: Railway's edge sets X-Real-IP.
export AXES_IPWARE_META_PRECEDENCE_ORDER=${AXES_IPWARE_META_PRECEDENCE_ORDER:-HTTP_X_REAL_IP,REMOTE_ADDR}

# --- App settings (override any of them with a service variable) ------------
export DJANGO_DEBUG=False
export TIME_ZONE=${TIME_ZONE:-UTC}
export ALLOW_REGISTRATION=${ALLOW_REGISTRATION:-False}
export ALLOW_GUEST_USERS=${ALLOW_GUEST_USERS:-False}
export ALLOW_UPLOAD_VIDEOS=${ALLOW_UPLOAD_VIDEOS:-True}
export WGER_INSTANCE=${WGER_INSTANCE:-https://wger.de}
export USE_CELERY=${USE_CELERY:-True}
export SYNC_EXERCISES_CELERY=${SYNC_EXERCISES_CELERY:-True}
export SYNC_EXERCISE_IMAGES_CELERY=${SYNC_EXERCISE_IMAGES_CELERY:-True}
export SYNC_EXERCISE_VIDEOS_CELERY=${SYNC_EXERCISE_VIDEOS_CELERY:-False}
export SYNC_INGREDIENTS_CELERY=${SYNC_INGREDIENTS_CELERY:-False}
export DOWNLOAD_INGREDIENTS_FROM=${DOWNLOAD_INGREDIENTS_FROM:-WGER}
export CACHE_API_EXERCISES_CELERY=${CACHE_API_EXERCISES_CELERY:-True}
export CACHE_API_EXERCISES_CELERY_FORCE_UPDATE=${CACHE_API_EXERCISES_CELERY_FORCE_UPDATE:-True}
export DJANGO_MEDIA_ROOT=${DJANGO_MEDIA_ROOT:-$DATA/media}
export WGER_SHOW_APP_STORE_LINKS=${WGER_SHOW_APP_STORE_LINKS:-True}

# Small footprint by default (Railway Free/Trial: 0.5 GB RAM per service).
export GUNICORN_CMD_ARGS=${GUNICORN_CMD_ARGS:---workers 1 --threads 4 --worker-class gthread --timeout 120 --graceful-timeout 30}
export CELERY_WORKER_CONCURRENCY=${CELERY_WORKER_CONCURRENCY:-2}
export MALLOC_ARENA_MAX=${MALLOC_ARENA_MAX:-2}

# --- JWT signing keys (mobile app and API tokens), generated once -------------
JWT_FILE="$DATA/secrets/jwt.env"
if [ -z "${JWT_PRIVATE_KEY:-}" ]; then
  if [ ! -s "$JWT_FILE" ]; then
    echo "wger-railway: generating JWT signing keys in $JWT_FILE"
    python3 manage.py generate-jwt-keys --no-color 2>/dev/null | grep '^JWT_' > "$JWT_FILE.tmp"
    mv "$JWT_FILE.tmp" "$JWT_FILE"
    chmod 600 "$JWT_FILE"
  fi
  set -a; . "$JWT_FILE"; set +a
fi

# --- Database: first-run setup and migrations, under a Postgres advisory lock ----
python3 /usr/local/bin/wger-railway-setup

# Queue an exercise image sync on every start (Celery runs it in the background). It only
# downloads images that are missing, so it finishes a first download a redeploy interrupted.
if [ "$USE_CELERY" = "True" ] && [ "${SYNC_EXERCISE_IMAGES_ON_START:-True}" = "True" ]; then
  python3 manage.py shell -c "from wger.exercises.tasks import sync_images_task; sync_images_task.delay()" >/dev/null \
    && echo "wger-railway: queued the exercise image sync" \
    || echo "wger-railway: could not queue the image sync (retries on the next start)"
fi

# --- Run ----------------------------------------------------------------------
pids=()
gunicorn wger.wsgi:application --preload --bind 127.0.0.1:8000 & pids+=($!)
if [ "$USE_CELERY" = "True" ]; then
  rm -f "$DATA/beat/celerybeat.pid"
  celery --app wger worker --beat --pool=threads --concurrency="$CELERY_WORKER_CONCURRENCY" \
    --schedule "$DATA/beat/celerybeat-schedule" --loglevel INFO & pids+=($!)
fi
caddy run --config /etc/caddy/Caddyfile --adapter caddyfile & pids+=($!)

term() { kill -TERM "${pids[@]}" 2>/dev/null || true; wait || true; exit 0; }
trap term TERM INT
set +e
wait -n "${pids[@]}"
status=$?
echo "wger-railway: a process exited (status $status); stopping the container" >&2
kill -TERM "${pids[@]}" 2>/dev/null
wait
[ "$status" -eq 0 ] && status=1
exit "$status"
