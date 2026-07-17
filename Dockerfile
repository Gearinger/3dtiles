#==================== Build stage ====================
FROM rust:1.90.0-bookworm as builder

ARG TARGETARCH

# Replace Debian package sources with faster mirrors
RUN sed -i 's|http://deb.debian.org|http://mirrors.ustc.edu.cn|g' /etc/apt/sources.list.d/debian.sources && \
    sed -i 's|http://security.debian.org|http://mirrors.ustc.edu.cn|g' /etc/apt/sources.list.d/debian.sources

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git build-essential cmake make zip unzip tar curl \
    pkg-config autoconf autoconf-archive automake libtool linux-libc-dev \
 && rm -rf /var/lib/apt/lists/*

# Install architecture-specific dependencies
RUN if [ "$TARGETARCH" = "arm64" ]; then \
    apt-get update && apt-get install -y --no-install-recommends \
        libgl1-mesa-dev libglu1-mesa-dev \
        libx11-dev libxrandr-dev libxi-dev; \
    else \
    apt-get update && apt-get install -y --no-install-recommends \
        libgl1-mesa-dev libglu1-mesa-dev \
        libx11-dev libxrandr-dev libxi-dev libxxf86vm-dev; \
    fi && rm -rf /var/lib/apt/lists/*

# Install vcpkg
WORKDIR /opt
RUN git clone https://github.com/Microsoft/vcpkg.git && \
    ./vcpkg/bootstrap-vcpkg.sh

# Set environment variables for vcpkg
ENV VCPKG_ROOT=/opt/vcpkg
ENV PATH=$VCPKG_ROOT:$PATH

# Copy source code
WORKDIR /app
COPY . .

# Install Rust toolchain
RUN rustup update stable

# Build the project with vcpkg
ENV CARGO_TERM_COLOR=always
ENV VCPKG_HAS_BEEN_INSTALLED=1
ENV VCPKG_INSTALLED_DIR=/app/vcpkg_installed
ENV VCPKG_DEFAULT_TRIPLET=$( \
    if [ "$TARGETARCH" = "arm64" ]; then \
        echo "arm64-linux"; \
    else \
        echo "x64-linux"; \
    fi)

RUN $VCPKG_ROOT/vcpkg install \
    --recurse \
    --clean-after-build \
    --x-install-root=$VCPKG_INSTALLED_DIR \
    --triplet=$VCPKG_DEFAULT_TRIPLET \
    --allow-unsupported

RUN cargo build --release -vv

#==================== Runtime stage ====================
FROM debian:bookworm-slim

# Replace Debian package sources with faster mirrors
RUN sed -i 's|http://deb.debian.org|http://mirrors.ustc.edu.cn|g' /etc/apt/sources.list.d/debian.sources && \
    sed -i 's|http://security.debian.org|http://mirrors.ustc.edu.cn|g' /etc/apt/sources.list.d/debian.sources

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1-mesa-dev libglu1-mesa-dev libx11-6 libxrandr2 libxi6 \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /3dtiles
WORKDIR /3dtiles

# Copy executables
COPY --from=builder /app/target/release/_3dtile /3dtiles/_3dtile
COPY --from=builder /app/target/release/gdal /3dtiles/gdal
COPY --from=builder /app/target/release/proj /3dtiles/proj
# Copy OSG plugins for runtime loading
COPY --from=builder /app/target/release/osgPlugins-3.6.5 /3dtiles/osgPlugins-3.6.5

# Set environment variables for runtime
ENV OSG_LIBRARY_PATH=/3dtiles/osgPlugins-3.6.5
ENV GDAL_DATA=/3dtiles/gdal
ENV PROJ_DATA=/3dtiles/proj

WORKDIR /data
ENTRYPOINT ["/3dtiles/_3dtile", "--help"]
