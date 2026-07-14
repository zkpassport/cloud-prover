FROM --platform=linux/amd64 ubuntu:24.04

# Node 20 + the few tools needed to fetch bb and the CRS.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl time && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

ARG BB_VERSION=4.2.0-aztecnr-rc.2
RUN curl -fsSL "https://github.com/AztecProtocol/aztec-packages/releases/download/v${BB_VERSION}/barretenberg-amd64-linux.tar.gz" -o /tmp/bb.tar.gz && \
    tar -xzf /tmp/bb.tar.gz -C /tmp && \
    mv /tmp/bb /usr/bin/bb_v4.2.0-aztecnr-rc.2 && \
    rm /tmp/bb.tar.gz

ARG BB_VERSION_V5=5.0.0
RUN curl -fsSL "https://github.com/AztecProtocol/aztec-packages/releases/download/v${BB_VERSION_V5}/barretenberg-amd64-linux.tar.gz" -o /tmp/bb.tar.gz && \
    tar -xzf /tmp/bb.tar.gz -C /tmp && \
    mv /tmp/bb /usr/bin/bb_v5.0.0 && \
    rm /tmp/bb.tar.gz

# Pre-download the CRS so the first proof doesn't pay the fetch.
COPY scripts/download_bb_crs.sh /tmp/download_bb_crs.sh
RUN mkdir -p /root/.bb-crs && cd /root/.bb-crs && bash /tmp/download_bb_crs.sh 23

# Build the app.
WORKDIR /app
COPY package.json package-lock.json tsconfig.json ./
COPY src ./src
RUN npm install && npm run build && npm prune --omit=dev

EXPOSE 3000
CMD ["node", "dist/server.js"]
