FROM nginx:1.27-alpine

COPY website/nginx.conf /etc/nginx/conf.d/default.conf
COPY website/index.html /usr/share/nginx/html/index.html
COPY website/index.md /usr/share/nginx/html/index.md
COPY website/app.js /usr/share/nginx/html/app.js
COPY website/styles.css /usr/share/nginx/html/styles.css
COPY website/assets /usr/share/nginx/html/assets
COPY docs /docs

EXPOSE 80
