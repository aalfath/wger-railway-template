[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/wger-1?utm_medium=integration&utm_source=button&utm_campaign=wger)

# wger on Railway

wger is a free, open-source workout, nutrition and weight tracker. You plan training routines from a shared exercise database with images, log your workouts, track body weight and measurements, and build nutrition plans with calorie and macro totals. It has a web interface, a REST API and official mobile apps that connect to your own server.

## About Hosting wger

This template runs wger 2.7.0 from the official `wger/server` image with Railway's PostgreSQL and Redis. One app service runs the Django web app (gunicorn), the Celery worker and scheduler, and Caddy, which serves static and uploaded files. On the first start it creates the database, loads the exercise catalogue and sets a generated password for the `admin` account. It then downloads the exercise images in the background. Uploads, images and the JWT signing keys are kept on a volume at `/data`. Migrations run on every start, so updates apply themselves. Public sign-up is off by default.

## Common Use Cases

* Plan and log your own workouts and track your body weight, privately
* Run a small server for a family, team or gym, with trainer and member accounts
* Back the wger Android and iOS apps with your own server and data

## Dependencies for wger Hosting

* PostgreSQL (Railway's managed Postgres): users, workouts, nutrition and exercise data
* Redis (Railway's managed Redis): cache, sessions and the Celery task queue

### Deployment Dependencies

* wger: https://github.com/wger-project/wger (AGPL-3.0)
* Docker setup and settings reference: https://github.com/wger-project/docker
* Template source: https://github.com/aalfath/wger-railway-template

### Implementation Details

Services:

* **wger** (public): gunicorn, a Celery worker with embedded beat (exercise sync, image download, cache warm-up), and Caddy on `PORT` 8080. Health check: `/healthz`, which serves the app's `/api/v2/version/`. Volume: `/data`.
* **Postgres** and **Redis**: Railway's own database services, each on its own volume, reached over the private network through `DATABASE_URL` and `REDIS_URL`.

After deploy:

1. Open the public URL and sign in as `admin`. The password is the `WGER_ADMIN_PASSWORD` variable on the wger service. You can change it in wger, and a restart won't reset it.
2. The exercise images arrive in the background within a few minutes. Ingredients for nutrition plans aren't loaded by default. To load the base set, run `wger load-online-fixtures` once in the service's shell (about 30 MB).
3. To let other people create accounts, set `ALLOW_REGISTRATION=True` on the wger service. Every other setting from upstream's `prod.env` also works as a service variable, for example `TIME_ZONE`, the email settings (`ENABLE_EMAIL`, `EMAIL_HOST`, …) and `SYNC_INGREDIENTS_CELERY`.

Variables: `DATABASE_URL` and `REDIS_URL` (references), `SECRET_KEY` and `WGER_ADMIN_PASSWORD` (generated), `PORT` (8080). The start script derives `SITE_URL` and `CSRF_TRUSTED_ORIGINS` from the Railway domain. If you add a custom domain, set `SITE_URL=https://YOUR-DOMAIN` and `CSRF_TRUSTED_ORIGINS=https://YOUR-DOMAIN`. Login lockouts (10 failed attempts per visitor) use Railway's `X-Real-IP` header.

Memory: the defaults (1 gunicorn worker with 4 threads, and 2 Celery threads) use about 300 MB, which fits Railway's 0.5 GB plans. If the app stops unexpectedly, the container exits with an error so Railway restarts it.

Updates: the app service builds from this template's GitHub repository, which pins the image by version and digest. When a new wger release is tested here, Railway shows you an update. Read `CHANGELOG.md` before you apply it. Database migrations run on the next start.

## Repository layout

* `Dockerfile`: `wger/server:2.7.0` pinned by digest, plus Caddy 2.11.9 (also pinned)
* `entrypoint.sh`: prepares the `/data` volume as root, then drops to the `wger` user
* `run.sh`: Railway defaults, JWT keys, then gunicorn + Celery + Caddy (exits non-zero if any of them stops)
* `setup.py`: first-run bootstrap, migrations and the admin password, under a Postgres advisory lock
* `Caddyfile`: static and media files, `/healthz`, and the proxy to gunicorn

## Why Deploy wger on Railway?

<!-- Recommended: Keep this section as shown below -->
Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying wger on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
<!-- End recommended section -->
