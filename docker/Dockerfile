# syntax=docker/dockerfile:1.6
FROM debian:bookworm-slim

ARG APT_MIRROR=deb.debian.org
ARG BUILDER_UID=1000
ARG BUILDER_GID=1000

# 切换 apt 源到国内镜像（解决用户全局 CLAUDE.md 提到的 deb.debian.org 慢的问题）
RUN sed -i "s|deb.debian.org|${APT_MIRROR}|g; s|security.debian.org|${APT_MIRROR}|g" \
        /etc/apt/sources.list.d/debian.sources 2>/dev/null \
    || sed -i "s|deb.debian.org|${APT_MIRROR}|g; s|security.debian.org|${APT_MIRROR}|g" \
        /etc/apt/sources.list

# OpenWRT/ImmortalWrt 编译完整依赖
# 见 https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential \
        ccache \
        ecj \
        fastjar \
        file \
        g++ \
        gawk \
        gettext \
        git \
        java-propose-classpath \
        libelf-dev \
        libncurses-dev \
        libssl-dev \
        python3 \
        python3-distutils \
        python3-setuptools \
        rsync \
        subversion \
        swig \
        time \
        unzip \
        wget \
        xsltproc \
        zlib1g-dev \
        sudo \
        curl \
        ca-certificates \
        bash \
        bc \
        bison \
        flex \
        zstd \
    && rm -rf /var/lib/apt/lists/*

# 创建非 root 用户
RUN groupadd -g ${BUILDER_GID} builder \
    && useradd -m -l -u ${BUILDER_UID} -g ${BUILDER_GID} -s /bin/bash builder \
    && echo "builder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/builder

# 工作目录与卷挂载点
RUN mkdir -p /work /home/builder/.ccache && chown -R builder:builder /work /home/builder
WORKDIR /work
USER builder

ENV CCACHE_DIR=/home/builder/.ccache
ENV PATH=/usr/lib/ccache:${PATH}

CMD ["/bin/bash"]
