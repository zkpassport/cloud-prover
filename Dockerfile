# Builder image: fetch the prebuilt bb binary + CRS and build the Node app.
FROM --platform=linux/amd64 ubuntu:22.04 AS builder

# Dependencies. Also the source of the shared libs / tools copied into the
# runtime image below.
RUN apt update && apt install -y \
    git jq curl wget time file \
    ca-certificates \
    libc++1 zlib1g coreutils \
    build-essential \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 20 and npm
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt update && \
    apt install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Download bb crs
COPY scripts/download_bb_crs.sh /scripts/download_bb_crs.sh
RUN chmod +x /scripts/download_bb_crs.sh
RUN cd ~ && /scripts/download_bb_crs.sh 23

# Download the prebuilt bb binary (linux/amd64) instead of compiling from source.
# The release binary is built -march=skylake (AVX2, no AVX-512), so it runs on
# x86-64-v3 / AMD Zen3 (t2d) nodes. To add another version (e.g. v5), download
# its tarball to a matching /bb_<version> path and add it to BB_VERSIONS + the
# runtime COPY below.
ARG BB_VERSION=4.2.0-aztecnr-rc.2
RUN curl -fsSL "https://github.com/AztecProtocol/aztec-packages/releases/download/v${BB_VERSION}/barretenberg-amd64-linux.tar.gz" -o /tmp/bb.tar.gz && \
    tar -xzf /tmp/bb.tar.gz -C /tmp && \
    mv /tmp/bb /bb_v4.2.0-aztecnr-rc.2 && \
    chmod +x /bb_v4.2.0-aztecnr-rc.2 && \
    rm /tmp/bb.tar.gz

# Install npm dependencies and build nodejs app
WORKDIR /app
COPY package.json package-lock.json tsconfig.json ./
COPY src ./src
RUN npm install
RUN npm run build

# ---

# Final minimal runtime image using Distroless
FROM --platform=linux/amd64 gcr.io/distroless/nodejs20

# Copy bb binary from builder (versioned name matches BB_VERSIONS in handler.ts)
COPY --from=builder /bb_v4.2.0-aztecnr-rc.2 /usr/bin/bb_v4.2.0-aztecnr-rc.2

# Copy crs from builder
COPY --from=builder /root/bn254_g1.dat /root/.bb-crs/
COPY --from=builder /root/bn254_g2.dat /root/.bb-crs/
COPY --from=builder /root/grumpkin_g1.dat /root/.bb-crs/
COPY --from=builder /root/grumpkin_size /root/.bb-crs/

# Copy GCC libraries bb links against (libstdc++ / libgcc_s)
COPY --from=builder /usr/lib/x86_64-linux-gnu/libstdc++.so.6 /usr/lib/x86_64-linux-gnu/
COPY --from=builder /usr/lib/x86_64-linux-gnu/libgcc_s.so.1 /usr/lib/x86_64-linux-gnu/

# Copy required shared libraries
COPY --from=builder /usr/lib/x86_64-linux-gnu/libtinfo.so.6 /usr/lib/x86_64-linux-gnu/
COPY --from=builder /usr/lib/x86_64-linux-gnu/libjq.so.1 /usr/lib/x86_64-linux-gnu/
COPY --from=builder /usr/lib/x86_64-linux-gnu/libonig.so.5 /usr/lib/x86_64-linux-gnu/
COPY --from=builder /usr/lib/x86_64-linux-gnu/libcurl.so.4 /usr/lib/x86_64-linux-gnu/
COPY --from=builder /usr/lib/x86_64-linux-gnu/libnghttp2.so.14 /usr/lib/x86_64-linux-gnu/
COPY --from=builder /usr/lib/x86_64-linux-gnu/libidn2.so.0 /usr/lib/x86_64-linux-gnu/
COPY --from=builder /usr/lib/x86_64-linux-gnu/librtmp.so.1 /usr/lib/x86_64-linux-gnu/
COPY --from=builder /usr/lib/x86_64-linux-gnu/libssh.so.4 /usr/lib/x86_64-linux-gnu/
COPY --from=builder /usr/lib/x86_64-linux-gnu/libpsl.so.5 /usr/lib/x86_64-linux-gnu/
COPY --from=builder /usr/lib/x86_64-linux-gnu/libssl.so.3 /usr/lib/x86_64-linux-gnu/
COPY --from=builder /usr/lib/x86_64-linux-gnu/libcrypto.so.3 /usr/lib/x86_64-linux-gnu/
COPY --from=builder /usr/lib/x86_64-linux-gnu/libz.so.1 /usr/lib/x86_64-linux-gnu/
COPY --from=builder /usr/lib/x86_64-linux-gnu/libunistring.so.2 /usr/lib/x86_64-linux-gnu/

COPY --from=builder /usr/lib/x86_64-linux-gnu/*.* /usr/lib/x86_64-linux-gnu/

# Copy binary dependencies from builder
COPY --from=builder /usr/bin/time /bin/time
COPY --from=builder /bin/tar /bin/tar
COPY --from=builder /bin/gzip /bin/gzip
COPY --from=builder /bin/gunzip /bin/gunzip
COPY --from=builder /usr/bin/curl /bin/curl
COPY --from=builder /usr/bin/base64 /bin/base64
COPY --from=builder /usr/bin/jq /usr/bin/jq
COPY --from=builder /bin/sh /bin/sh
COPY --from=builder /bin/bash /bin/bash

# Copy built app from builder stage
WORKDIR /app
COPY --from=builder /app /app

# Expose the necessary port
EXPOSE 3000

# Start the application
CMD ["dist/server.js"]
