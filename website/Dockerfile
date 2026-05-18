FROM node:22-alpine

WORKDIR /app

COPY website/package*.json ./website/
RUN cd website && npm ci

COPY docs ./docs
COPY website ./website

WORKDIR /app/website
RUN npm run build

ENV NODE_ENV=production
ENV PORT=80

EXPOSE 80

CMD ["npm", "run", "start"]
