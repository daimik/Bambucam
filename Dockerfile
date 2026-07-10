# syntax=docker/dockerfile:1
ARG BAMBU_STUDIO_VERSION=01.07.07

##############################
# Builder
##############################
FROM debian:bookworm AS builder

ARG BAMBU_STUDIO_VERSION
ARG BAMBU_PLUGIN_URL=""

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential pkg-config \
      libavcodec-dev libavformat-dev libavutil-dev \
      libjpeg-dev libmicrohttpd-dev \
      curl unzip ca-certificates jq \
 && rm -rf /var/lib/apt/lists/*

# Acquire the Bambu Linux camera plugin (.so set).
RUN set -eux; \
    plugin_dir="/root/.config/BambuStudio/plugins"; \
    mkdir -p "$plugin_dir" /tmp/plugin; \
    if [ -n "$BAMBU_PLUGIN_URL" ]; then \
      zip_url="$BAMBU_PLUGIN_URL"; \
    else \
      api="https://api.bambulab.com/v1/iot-service/api/slicer/resource?slicer/plugins/cloud=${BAMBU_STUDIO_VERSION}.00"; \
      win_url="$(curl -fsSL "$api" | jq -r '.resources[] | select(.type=="slicer/plugins/cloud") | .url')"; \
      if [ -z "$win_url" ] || [ "$win_url" = "null" ]; then \
        echo "ERROR: could not resolve plugin URL from Bambu API ($api)" >&2; exit 1; \
      fi; \
      zip_url="$(printf '%s' "$win_url" | sed 's#/win_#/linux_#')"; \
    fi; \
    echo "Downloading plugin: $zip_url"; \
    curl -fsSL -o /tmp/plugin/plugin.zip "$zip_url"; \
    unzip -o /tmp/plugin/plugin.zip -d /tmp/plugin; \
    find /tmp/plugin -name '*.so' -exec cp -v {} "$plugin_dir/" \; ; \
    if [ ! -f "$plugin_dir/libBambuSource.so" ]; then \
      echo "ERROR: libBambuSource.so not present in plugin zip" >&2; exit 1; \
    fi; \
    rm -rf /tmp/plugin

WORKDIR /src
COPY bambu.c bambu.h bambu_fake.c bambu_tunnel.h bambucam.c server.h \
     server_microhttpd.c server_ffmpeg_rtp.c Makefile ./

RUN set -eux; \
    make SERVER=HTTP               && mv bambucam bambucam-http       && make clean; \
    make SERVER=RTP                && mv bambucam bambucam-rtp        && make clean; \
    make SERVER=HTTP BAMBU_FAKE=1  && mv bambucam bambucam-http-fake  && make clean; \
    make SERVER=RTP  BAMBU_FAKE=1  && mv bambucam bambucam-rtp-fake   && make clean

# ldd gate: every dependency of the real plugin must resolve on this base.
RUN set -eux; \
    ldd /root/.config/BambuStudio/plugins/libBambuSource.so; \
    if ldd /root/.config/BambuStudio/plugins/libBambuSource.so | grep -q 'not found'; then \
      echo "ERROR: unresolved libBambuSource.so dependencies on this base image" >&2; exit 1; \
    fi

##############################
# Runtime
##############################
FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
      libavcodec59 libavformat59 libavutil57 \
      libjpeg62-turbo libmicrohttpd12 \
      ca-certificates netcat-openbsd \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /root/.config/BambuStudio/plugins/ /root/.config/BambuStudio/plugins/
COPY --from=builder \
     /src/bambucam-http /src/bambucam-rtp \
     /src/bambucam-http-fake /src/bambucam-rtp-fake \
     /usr/local/bin/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh \
 && chmod +x /usr/local/bin/entrypoint.sh \
      /usr/local/bin/bambucam-http /usr/local/bin/bambucam-rtp \
      /usr/local/bin/bambucam-http-fake /usr/local/bin/bambucam-rtp-fake

# libBambuSource.so has no dynamic NEEDED on its sibling plugin .so files
# (verified via readelf: it links only glibc/libstdc++/libgcc) but, being a
# closed-source blob, may dlopen them by bare name at runtime. Keep the plugin
# dir on the loader search path defensively.
ENV LD_LIBRARY_PATH=/root/.config/BambuStudio/plugins

# Runtime ldd gate: the actual shipped executables (not just the plugin .so)
# must have every dynamic dependency resolvable on this slim base. This is the
# artifact that runs, so it is what must be proven.
RUN set -eux; \
    for b in bambucam-http bambucam-rtp bambucam-http-fake bambucam-rtp-fake; do \
      ldd "/usr/local/bin/$b"; \
      if ldd "/usr/local/bin/$b" | grep -q 'not found'; then \
        echo "ERROR: unresolved dynamic dependencies in $b on runtime image" >&2; \
        exit 1; \
      fi; \
    done

ENV BAMBU_PORT=8080 SERVER=HTTP
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
