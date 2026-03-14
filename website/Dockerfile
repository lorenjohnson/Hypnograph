FROM nginx:1.27-alpine

COPY website/nginx.conf /etc/nginx/conf.d/default.conf
COPY website/index.html /usr/share/nginx/html/index.html
COPY website/app.js /usr/share/nginx/html/app.js
COPY website/styles.css /usr/share/nginx/html/styles.css

EXPOSE 80
