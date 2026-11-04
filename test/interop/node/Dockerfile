FROM node:22-alpine
WORKDIR /app
RUN npm install --no-audit --no-fund soap@1.14.0
COPY server.js doc.wsdl ./
CMD ["node", "server.js"]
