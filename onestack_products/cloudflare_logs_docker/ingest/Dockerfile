FROM node:22-alpine

WORKDIR /app
COPY package.json server.js redaction.js ./

USER node
CMD ["node", "server.js"]

