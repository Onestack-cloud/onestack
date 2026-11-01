FROM node:26.13.0-alpine

WORKDIR /app
COPY package.json server.js redaction.js ./

USER node
CMD ["node", "server.js"]

