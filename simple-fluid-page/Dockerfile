# Steg 1: Bygg React-appen
FROM node:20 AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Steg 2: Servera med nginx
FROM nginx:stable-alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

RUN mkdir -p /var/cache/nginx /var/run /etc/nginx/conf.d \
    && sed -E -i 's#^[[:space:]]*pid[[:space:]]+/run/nginx.pid;#pid /tmp/nginx.pid;#' /etc/nginx/nginx.conf \
    && chown -R 101:101 /var/cache/nginx /var/run /etc/nginx/conf.d /usr/share/nginx/html

USER 101

EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
