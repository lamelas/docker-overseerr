FROM ghcr.io/linuxserver/baseimage-alpine:3.15

# set version label
ARG BUILD_DATE
ARG VERSION
ARG OVERSEERR_VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="nemchik"

# set environment variables
ENV HOME="/config"

RUN \
  echo "**** install build packages ****" && \
  apk add --no-cache --virtual=build-dependencies \
    curl \
    g++ \
    make \
    python3 && \
  echo "**** symlink python3 for compatibility ****" && \
  ln -s /usr/bin/python3 /usr/bin/python && \
  echo "**** install runtime packages ****" && \
  apk add --no-cache \
    yarn && \
  if [ -z ${OVERSEERR_VERSION+x} ]; then \
    OVERSEERR_VERSION=$(curl -sX GET "https://api.github.com/repos/sct/overseerr/releases/latest" \
    | awk '/tag_name/{print $4;exit}' FS='[""]'); \
  fi && \
  export COMMIT_TAG="${OVERSEERR_VERSION}" && \
  curl -o \
    /tmp/overseerr.tar.gz -L \
    "https://github.com/sct/overseerr/archive/${OVERSEERR_VERSION}.tar.gz" && \
  mkdir -p /app/overseerr && \
  tar xzf \
    /tmp/overseerr.tar.gz -C \
    /app/overseerr/ --strip-components=1 && \
  cd /app/overseerr && \
  export NODE_OPTIONS=--max_old_space_size=2048 && \
  yarn --frozen-lockfile --network-timeout 1000000 && \
  yarn build && \
  yarn install --production --ignore-scripts --prefer-offline && \
  yarn cache clean && \
  rm -rf \
    /app/overseerr/src \
    /app/overseerr/server && \
  echo "{\"commitTag\": \"${COMMIT_TAG}\"}" > committag.json && \
  rm -rf /app/overseerr/config && \
  ln -s /config /app/overseerr/config && \
  touch /config/DOCKER && \
  echo "**** cleanup ****" && \
  apk del --purge \
    build-dependencies && \
  rm -rf \
    /root/.cache \
    /tmp/* \
    /app/overseerr/.next/cache/*

# copy local files
COPY root/ /

# ports and volumes
EXPOSE 5055
VOLUME /config

# TAILSCALE STUFF

FROM golang:1.16.2-alpine3.13 as builder
WORKDIR /app
COPY . ./
# This is where one could build the application code as well.


FROM alpine:latest as tailscale
WORKDIR /app
COPY . ./
ENV TSFILE=tailscale_1.24.2_amd64.tgz
RUN wget https://pkgs.tailscale.com/stable/${TSFILE} && \
  tar xzf ${TSFILE} --strip-components=1
COPY . ./


FROM alpine:latest
RUN apk update && apk add ca-certificates && rm -rf /var/cache/apk/*

# Copy binary to production image
COPY --from=builder /app/start.sh /app/start.sh
COPY --from=tailscale /app/tailscaled /app/tailscaled
COPY --from=tailscale /app/tailscale /app/tailscale
RUN mkdir -p /var/run/tailscale /var/cache/tailscale /var/lib/tailscale

# Run on container startup.
CMD ["/app/start.sh"]
