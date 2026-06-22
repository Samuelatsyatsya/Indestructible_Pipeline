FROM node:20-alpine AS build
WORKDIR /app
# Upgrade Alpine packages to pick up latest security patches before Trivy scans.
RUN apk upgrade --no-cache
COPY package.json ./
RUN npm install
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
