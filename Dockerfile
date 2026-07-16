# ==================== Build stage ====================
# 移除了 --platform=linux/amd64，使镜像能够根据当前编译的物理机架构自动适配
FROM rust:1.90.0-bookworm as builder

# 移除了原有的强制锁死平台的环境变量 ENV DOCKER_DEFAULT_PLATFORM

# 替换 Debian 软件源为中科大镜像以加速构建
RUN sed -i 's|http://deb.debian.org|http://mirrors.ustc.edu.cn|g' /etc/apt/sources.list.d/debian.sources && \
    sed -i 's|http://security.debian.org|http://mirrors.ustc.edu.cn|g' /etc/apt/sources.list.d/debian.sources

# 安装 vcpkg 编译阶段的必要依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    git build-essential cmake make zip unzip tar curl \
    pkg-config autoconf automake libtool linux-libc-dev libgl1-mesa-dev \
 && rm -rf /var/lib/apt/lists/*

# 安装 vcpkg（保持原仓库的镜像站以加速下载）
WORKDIR /opt
RUN git clone https://gitee.com/Wallance/vcpkg.git && \
    ./vcpkg/bootstrap-vcpkg.sh

# 安装 OpenGL 运行时相关的开发库
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1-mesa-dev libglu1-mesa-dev \
    libx11-dev libxrandr-dev libxi-dev libxxf86vm-dev \
 && rm -rf /var/lib/apt/lists/*

# 设置 vcpkg 环境变量
ENV VCPKG_ROOT=/opt/vcpkg
ENV PATH=$VCPKG_ROOT:$PATH

# 复制源码到工作目录
WORKDIR /app
COPY . .

# 执行编译（自动编译为对应的平台架构二进制文件）
ENV CARGO_TERM_COLOR=always
RUN cargo build --release -vv

# ==================== Runtime stage ====================
# 运行镜像同样移除了架构限制，拉取时会自动匹配 arm64 版本
FROM debian:bookworm-slim

RUN sed -i 's|http://deb.debian.org|http://mirrors.ustc.edu.cn|g' /etc/apt/sources.list.d/debian.sources && \
    sed -i 's|http://security.debian.org|http://mirrors.ustc.edu.cn|g' /etc/apt/sources.list.d/debian.sources

RUN mkdir -p /3dtiles
WORKDIR /3dtiles

# 复制编译产物（可执行文件和库路径在多架构下一致）
COPY --from=builder /app/target/release/_3dtile /3dtiles/_3dtile
COPY --from=builder /app/target/release/gdal /3dtiles/gdal
COPY --from=builder /app/target/release/proj /3dtiles/proj
COPY --from=builder /app/target/release/osgPlugins-3.6.5 /3dtiles/osgPlugins-3.6.5

# 设置运行时的三方库环境变量
ENV OSG_LIBRARY_PATH=/3dtiles/osgPlugins-3.6.5
ENV GDAL_DATA=/3dtiles/gdal
ENV PROJ_DATA=/3dtiles/proj

WORKDIR /data
ENTRYPOINT ["/3dtiles/_3dtile", "--help"]
