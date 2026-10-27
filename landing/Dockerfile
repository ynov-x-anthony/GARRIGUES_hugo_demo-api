# syntax=docker/dockerfile:1

# Étape 1 — build : prépare le site statique avec Node, sans dépendance npm.
# Les éléments sensibles (secrets/) et le code API ne sont jamais copiés ici :
# ils sont exclus par .dockerignore, ils ne peuvent donc pas finir dans l'image.
FROM node:22-alpine AS build
WORKDIR /src
COPY assets/ ./assets/
COPY landing/site/ ./site/
COPY landing/build.mjs ./
ARG LAND_VERSION=dev
ENV BUILD_VERSION=${LAND_VERSION}
RUN node build.mjs

# Étape 2 — runtime : nginx Alpine non-root uniquement.
# nginxinc/nginx-unprivileged démarre en uid 101, pas de root pour nginx.
FROM nginxinc/nginx-unprivileged:1.27-alpine

COPY --from=build /src/build /usr/share/nginx/html
COPY landing/nginx.conf /etc/nginx/conf.d/default.conf

# Remédiation : le scan Trivy de la version initiale signalait 58 failles avec
# correctifs (pcre2, tiff, zlib…) dans les paquets alpine de la base. On met à
# jour ces paquets, en root de façon temporaire, avant de retomber en non-root.
USER root
RUN apk update && apk upgrade --no-cache && rm -rf /var/cache/apk/*
USER 101

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -q --spider http://127.0.0.1:8080/healthz || exit 1

LABEL org.opencontainers.image.title="landing-clouds" \
      org.opencontainers.image.description="Landing page clouds conteneurisée (multi-stage, non-root)" \
      org.opencontainers.image.source="https://github.com/ynov-x-anthony/GARRIGUES_hugo_demo-api"
