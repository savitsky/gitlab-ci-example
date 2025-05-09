ARG NODE_IMAGE_BUILD
ARG NODE_IMAGE_RUN

FROM ${NODE_IMAGE_BUILD} as builder

WORKDIR /app

COPY package*.json ./
RUN npm install --legacy-peer-deps

COPY patches ./patches
RUN npm run postinstall || true && npm cache clean --force

COPY app/ ./

COPY babel.config.js ./

RUN npx babel . -d ./dist --source-maps

FROM ${NODE_IMAGE_RUN} as api

WORKDIR /app

COPY package*.json ./
RUN npm install --omit=dev

COPY --from=builder /app/dist ./dist