FROM node:22.23.4-alpine

WORKDIR /app
COPY package.json server.js redaction.js ./

USER node
CMD ["node", "server.js"]

