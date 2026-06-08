# Builder image
FROM --platform=linux/amd64 ubuntu:22.04 AS builder

# Install GCC 13
RUN apt update && apt install -y software-properties-common
RUN add-apt-repository -y ppa:ubuntu-toolchain-r/test && apt update
RUN apt install -y gcc-13 g++-13

# Install remaning dependencies
RUN apt update && apt install -y \
    git jq curl wget time file \
    ca-certificates \
    libc++1 zlib1g coreutils \
    build-essential ninja-build parallel \
    libssl-dev \
    gawk bison \
    libgmp-dev libmpfr-dev libmpc-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 20 and npm
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt update && \
    apt install -y nodejs && \
    corepack enable --install-directory /usr/bin/ && \
    rm -rf /var/lib/apt/lists/*

# Install CMake 3.29.2
RUN cd /tmp && \
    wget https://github.com/Kitware/CMake/releases/download/v3.29.2/cmake-3.29.2.tar.gz && \
    tar -xvzf cmake-3.29.2.tar.gz && \
    cd cmake-3.29.2 && \
    ./configure && \
    make -j$(nproc) && \
    make install && \
    cd / && \
    rm -rf /tmp/cmake-3.29.2*

ENV LD_LIBRARY_PATH=/opt/glibc-2.38/lib:/opt/gcc-13.2/lib64

RUN apt-key adv --fetch-keys https://apt.kitware.com/keys/kitware-archive-latest.asc
RUN apt update && apt install -y libssl-dev && rm -rf /var/lib/apt/lists/*

# Install LLVM 16 (clang 16) and LLVM 20 (clang 20)
RUN cd ~ && wget https://apt.llvm.org/llvm.sh && chmod +x llvm.sh && ./llvm.sh 16 && ./llvm.sh 20

# Install Rust (needed to build avm-transpiler for bb v4)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
ENV PATH=/root/.cargo/bin:$PATH

# Download bb crs
COPY scripts/download_bb_crs.sh /scripts/download_bb_crs.sh
RUN chmod +x /scripts/download_bb_crs.sh
RUN cd ~ && /scripts/download_bb_crs.sh 23

# Build bb v4.2.0-aztecnr-rc.2
RUN cd ~ && git clone --depth 1 --branch v4.2.0-aztecnr-rc.2 --recurse-submodules --shallow-submodules https://github.com/aztecprotocol/aztec-packages aztec-packages-v4.2.0-aztecnr-rc.2

RUN cd ~/aztec-packages-v4.2.0-aztecnr-rc.2/avm-transpiler && cargo build --release
RUN cd ~/aztec-packages-v4.2.0-aztecnr-rc.2/barretenberg/cpp && cmake --preset clang20-no-avm \
    -DCMAKE_BUILD_TYPE=Release \
    -DTARGET_ARCH=x86-64-v3 \
    -DENABLE_PAR_ALGOS=ON \
    -DMULTITHREADING=ON \
    -DCMAKE_CXX_FLAGS="-O3 -march=x86-64-v3 -mtune=generic" && \
    cmake --build build --target bb
RUN cp ~/aztec-packages-v4.2.0-aztecnr-rc.2/barretenberg/cpp/build/bin/bb /bb_v4.2.0-aztecnr-rc.2

# Build bb v2.0.3
RUN cd ~ && git clone --depth 1 --branch v2.0.3 https://github.com/zkpassport/aztec-packages aztec-packages-v2.0.3
# msgpack-c pin SHA isn't on any branch tip in AztecProtocol/msgpack-c, so default git fetch can't see it; switch to tarball-by-SHA
RUN sed -i \
    -e 's|GIT_REPOSITORY "https://github.com/AztecProtocol/msgpack-c.git"|URL "https://github.com/AztecProtocol/msgpack-c/archive/5ee9a1c8c325658b29867829677c7eb79c433a98.tar.gz"|' \
    -e '/GIT_TAG 5ee9a1c8c325658b29867829677c7eb79c433a98/d' \
    ~/aztec-packages-v2.0.3/barretenberg/cpp/cmake/msgpack.cmake
RUN cd ~/aztec-packages-v2.0.3/barretenberg/cpp && cmake --preset clang20 \
    -DCMAKE_BUILD_TYPE=Release \
    -DTARGET_ARCH=x86-64-v3 \
    -DENABLE_PAR_ALGOS=ON \
    -DMULTITHREADING=ON \
    -DDISABLE_AZTEC_VM=ON \
    -DCMAKE_CXX_FLAGS="-O3 -march=x86-64-v3 -mtune=generic" && \
    cmake --build build --target bb
RUN cp ~/aztec-packages-v2.0.3/barretenberg/cpp/build/bin/bb /bb_v2.0.3

# Install npm dependencies and build nodejs app
WORKDIR /app
COPY package.json package-lock.json tsconfig.json ./
COPY src ./src
RUN npm install
RUN npm run build

# ---

# Final minimal runtime image using Distroless
FROM --platform=linux/amd64 gcr.io/distroless/nodejs20

# Copy bb binaries from builder (versioned names match BB_VERSIONS in handler.ts)
COPY --from=builder /bb_v4.2.0-aztecnr-rc.2 /usr/bin/bb_v4.2.0-aztecnr-rc.2
COPY --from=builder /bb_v2.0.3 /usr/bin/bb_v2.0.3

# Copy crs from builder
COPY --from=builder /root/bn254_g1.dat /root/.bb-crs/
COPY --from=builder /root/bn254_g2.dat /root/.bb-crs/
COPY --from=builder /root/grumpkin_g1.dat /root/.bb-crs/
COPY --from=builder /root/grumpkin_size /root/.bb-crs/

# Copy GCC 13 libraries
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
