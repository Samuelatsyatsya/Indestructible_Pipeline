# syntax=docker/dockerfile:1.4
FROM node:20-alpine AS build
WORKDIR /app
# Upgrade Alpine packages to pick up latest security patches before Trivy scans.
RUN apk upgrade --no-cache
COPY package.json ./

# Registry to install from. Defaults to public npmjs so a plain `docker build`
# still works; the pipeline overrides this with the FinCorp CodeArtifact URL.
ARG NPM_REGISTRY=https://registry.npmjs.org/

# Install through the configured registry. The CodeArtifact auth token is passed
# as a BuildKit secret (never a build-arg) so it is NOT baked into any image
# layer or `docker history`. When no token is mounted (public registry build),
# the .npmrc auth line is simply omitted.
RUN --mount=type=secret,id=codeartifact_token,required=false \
    sh -euc '\
      reg="${NPM_REGISTRY#https:}"; \
      echo "registry=${NPM_REGISTRY}" > .npmrc; \
      if [ -f /run/secrets/codeartifact_token ]; then \
        echo "${reg}:_authToken=$(cat /run/secrets/codeartifact_token)" >> .npmrc; \
        echo "${reg}:always-auth=true" >> .npmrc; \
      fi; \
      npm install; \
      rm -f .npmrc'

COPY . .
ARG REACT_APP_API_URL
ENV REACT_APP_API_URL=$REACT_APP_API_URL
RUN npm run build

FROM nginx:alpine AS runtime
RUN apk upgrade --no-cache
COPY --from=build /app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

RUN addgroup -S fincorp && adduser -S fincorp -G fincorp

EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s \
  CMD wget -qO- http://localhost/index.html || exit 1

CMD ["nginx", "-g", "daemon off;"]
