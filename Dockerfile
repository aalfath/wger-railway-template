# wger on Railway: web (gunicorn) + Celery worker/beat + Caddy for static and media files.
# Upstream image pinned by version and digest. Bump both together (see CHANGELOG.md).
FROM docker.io/library/caddy:2.11.9-alpine@sha256:003a97808e781aa9f7e75cc2f43d34d461099031faf5e20faefb9f61126836f0 AS caddy

FROM docker.io/wger/server:2.7.0@sha256:1c5789b93bfe5eed0b7287255782d9177027b255de2b22b59f511a693a48db04

USER root
COPY --from=caddy /usr/bin/caddy /usr/bin/caddy
COPY Caddyfile /etc/caddy/Caddyfile
COPY entrypoint.sh /usr/local/bin/wger-railway-entrypoint
COPY run.sh /usr/local/bin/wger-railway-run
RUN chmod 755 /usr/local/bin/wger-railway-entrypoint /usr/local/bin/wger-railway-run

# Collect static files at build time, so a cold start only has to migrate the database.
USER wger
RUN cd /home/wger/src \
 && PS_DATABASE_URI=sqlite:////tmp/build.sqlite DJANGO_DEBUG=False SECRET_KEY=build-only \
    python3 manage.py collectstatic --no-input >/dev/null \
 && rm -f /tmp/build.sqlite
USER root

ENV HOME=/home/wger \
    PORT=8080 \
    DJANGO_DEBUG=False \
    DJANGO_MEDIA_ROOT=/data/media \
    DJANGO_STATIC_ROOT=/home/wger/static
WORKDIR /home/wger/src
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/wger-railway-entrypoint"]
