FROM node:24-alpine
WORKDIR /app/services/api
COPY services/api/package.json ./
COPY services/api/src ./src
COPY services/integrations/src ../integrations/src
RUN mkdir /app/data && chown node:node /app/data
USER node
ENV HOST=0.0.0.0 PORT=8787 DATA_DIR=/app/data
VOLUME ["/app/data"]
EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=3s CMD node -e "fetch('http://127.0.0.1:8787/health').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"
CMD ["node", "src/server.mjs"]
