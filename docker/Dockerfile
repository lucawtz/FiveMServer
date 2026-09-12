# FiveM FXServer (Linux-Artifacts) mit txAdmin.
#
# Build (aus dem Projektordner):
#   docker build -f docker/Dockerfile -t fivem-fxserver .
#   docker build -f docker/Dockerfile --build-arg FX_CHANNEL=latest -t fivem-fxserver .
#
# Die Artifacts werden beim Bauen ueber die offizielle Changelog-API geladen
# (gleicher Weg wie scripts/linux/lib.sh) und nach /opt/fxserver entpackt.
# server-data und txData kommen als Volumes von aussen (siehe docker-compose.yml).

FROM ubuntu:24.04

ARG FX_CHANNEL=recommended
ARG FX_CHANGELOG_API=https://changelogs-live.fivem.net/api/changelog/versions/linux/server

# Nur zur Bauzeit (ARG statt ENV), damit es nicht in jede "docker exec"-Shell leakt.
ARG DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# git und unzip braucht nur install-resources.sh, das laut docs/docker.md auf dem Host laeuft.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl xz-utils ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Artifacts laden: URL und Build-Nummer aus dem JSON der Changelog-API (ohne jq).
# Die Build-Nummer kann als String ("12345") oder nackte Zahl (12345) kommen, daher zwei Schritte.
RUN set -eu; \
    case "$FX_CHANNEL" in recommended|latest|optional) ;; *) echo "Ungueltiger FX_CHANNEL: $FX_CHANNEL" >&2; exit 1 ;; esac; \
    curl -fsSL --retry 3 -o /tmp/versions.json "$FX_CHANGELOG_API"; \
    url="$(sed -n 's/.*"'"$FX_CHANNEL"'_download"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' /tmp/versions.json | head -n 1 | sed 's#\\/#/#g')"; \
    ver="$(sed -n 's/.*"'"$FX_CHANNEL"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' /tmp/versions.json | head -n 1)"; \
    [ -n "$ver" ] || ver="$(sed -n 's/.*"'"$FX_CHANNEL"'"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' /tmp/versions.json | head -n 1)"; \
    if [ -z "$url" ]; then echo "Keine Download-URL fuer Channel $FX_CHANNEL gefunden" >&2; exit 1; fi; \
    echo "Lade FXServer Build ${ver:-unbekannt} ($FX_CHANNEL): $url"; \
    mkdir -p /opt/fxserver; \
    curl -fL --retry 3 -o /tmp/fx.tar.xz "$url"; \
    tar -xJf /tmp/fx.tar.xz -C /opt/fxserver; \
    test -f /opt/fxserver/run.sh; \
    chmod +x /opt/fxserver/run.sh; \
    printf 'channel=%s\nversion=%s\nurl=%s\ndownloaded_at=%s\nplatform=linux\n' \
        "$FX_CHANNEL" "${ver:-unbekannt}" "$url" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > /opt/fxserver/VERSION.txt; \
    rm -f /tmp/fx.tar.xz /tmp/versions.json

# Nicht-root-User mit uid/gid 1000. ubuntu:24.04 bringt bereits einen User "ubuntu"
# mit uid 1000 mit, der zuerst entfernt wird. Bind-Mounts von server-data muessen
# auf dem Host uid 1000 gehoeren (chown -R 1000:1000 server-data).
RUN if getent passwd 1000 >/dev/null; then userdel -r "$(getent passwd 1000 | cut -d: -f1)" || true; fi \
    && if getent group 1000 >/dev/null; then groupdel "$(getent group 1000 | cut -d: -f1)" || true; fi \
    && groupadd -g 1000 fivem \
    && useradd -u 1000 -g 1000 -m -s /bin/bash fivem \
    && mkdir -p /server-data /txData \
    && chown fivem:fivem /server-data /txData

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh

VOLUME ["/server-data", "/txData"]
EXPOSE 30120/tcp 30120/udp 40120/tcp

USER fivem
WORKDIR /server-data

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
