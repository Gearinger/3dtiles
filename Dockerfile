# ==================== Build stage ====================
# 去掉原有的 --platform=linux/amd64 限制，让构建器根据当前系统架构自动拉取对应的 rust 镜像
FROM rust:1.90.0-bookworm as builder

# 移除之前锁死 amd64 的 DOCKER_DEFAULT_PLATFORM 环境变量

# 替换 Debian 软件源为更快的国内镜像（如果你在 GitHub Actions 构建，可以保留，国内拉取也很快）
RUN sed -i 's|http://deb.debian.org|http://mirrors.ustc.edu.cn|g' /etc/apt/sources.list.d/debian.sources && \
    sed -i 's|http://security.debian.org|http://mirrors.ustc.edu.cn|g' /etc/apt/sources.list.d/debian.sources

# 安装 vcpkg 依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    git build-essential cmake make zip unzip tar curl \
    pkg-config autoconf automake libtool linux-libc-dev libgl1-mesa-dev \
 && rm -rf /var/lib/apt/lists/*

# 安装 vcpkg（原仓库使用 gitee 镜像极速克隆，在 ARM 下依然适用）
WORKDIR /opt
RUN git clone https://gitee.com/Wallance/vcpkg.git && \
    ./vcpkg/bootstrap-vcpkg.sh

# 安装 OpenGL 相关依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1-mesa-dev libglu1-mesa-dev \
    libx11-dev libxrandr-dev libxi-dev libxxf86vm-dev \
 && rm -rf /var/lib/apt/lists/*

# 设置 vcpkg 环境变量
ENV VCPKG_ROOT=/opt/vcpkg
ENV PATH=$VCPKG_ROOT:$PATH

# 复制源码
WORKDIR /app
COPY . .

# 编译项目（自动根据当前运行环境编译成对应的 arm64 或 amd64）
ENV CARGO_TERM_COLOR=always
RUN cargo build --release -vv

# ==================== Runtime stage ====================
# 运行时同样去掉平台限制，会自动匹配
FROM debian:bookworm-slim

RUN sed -i 's|http://deb.debian.org|http://mirrors.ustc.edu.cn|g' /etc/apt/sources.list.d/debian.sources && \
    sed -i 's|http://security.debian.org|http://mirrors.ustc.edu.cn|g' /etc/apt/sources.list.d/debian.sources

RUN mkdir -p /3dtiles
WORKDIR /3dtiles

# 复制编译好的可执行文件和库
COPY --from=builder /app/target/release/_3dtile /3dtiles/_3dtile
COPY --from=builder /app/target/release/gdal /3dtiles/gdal
COPY --from=builder /app/target/release/proj /3dtiles/proj
# 复制运行时的 OSG 插件
COPY --from=builder /app/target/release/osgPlugins-3.6.5 /3dtiles/osgPlugins-3.6.5

# 设置运行时的环境变量
ENV OSG_LIBRARY_PATH=/3dtiles/osgPlugins-3.6.5
ENV GDAL_DATA=/3dtiles/gdal
ENV PROJ_DATA=/3dtiles/proj

WORKDIR /data
ENTRYPOINT ["/3dtiles/_3dtile", "--help"]
