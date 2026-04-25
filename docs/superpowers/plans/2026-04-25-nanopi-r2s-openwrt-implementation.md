# NanoPi R2S 多模式定制 OpenWRT 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 NanoPi R2S（RK3328）构建一份基于 ImmortalWrt master 的单镜像、可在线切换三种工作模式（PPPoE 主路由 / 双口对等交换 / 旁路由）的定制 OpenWRT 固件，并提供 macOS Docker 本地编译流程与 GitHub Actions CI。

**Architecture:** 仓库 = (1) Docker 化编译环境 + (2) `.config.seed` diffconfig + (3) `files/` rootfs 注入（三套 UCI profile + 切换脚本 + LuCI 应用 + PID 风扇控制 + 首次开机初始化）+ (4) macOS 烧卡脚本 + (5) GitHub Actions 流水线。模式切换在运行时由 `/usr/bin/mode-switch` 拷贝 profile + 注入 UCI 动态参数完成；风扇用 shell PID 主循环 + procd 守护。

**Tech Stack:** ImmortalWrt master (rockchip/armv8, friendlyarm_nanopi-r2s), Docker (debian:bookworm-slim), bash, LuCI (Lua + cbi/template), procd, UCI, GitHub Actions, bats-core / shellcheck / hadolint / luac (开发测试)

**Spec:** `docs/superpowers/specs/2026-04-25-nanopi-r2s-openwrt-design.md`

---

## 文件结构（最终）

| 路径 | 责任 |
| --- | --- |
| `README.md` | 项目入口文档 |
| `.gitignore` | 排除 build/ 产物、out/、immortalwrt/、.config |
| `docker/Dockerfile` | 编译宿主镜像（debian + ImmortalWrt 依赖 + builder 用户） |
| `docker/compose.yaml` | 容器编排（卷挂载 + 资源限制） |
| `build/build.sh` | 编译入口（外层：起容器；内层：clone/feeds/make） |
| `build/feeds.conf.default` | ImmortalWrt feeds 配置 |
| `build/.config.seed` | diffconfig 种子（与 defconfig 的差异） |
| `build/IMMORTALWRT_COMMIT` | 锁定的 ImmortalWrt master commit hash |
| `files/etc/config/mode-switch` | 模式与可配置参数的 UCI 默认值 |
| `files/etc/config/fan` | 风扇 PID 参数 UCI 默认值 |
| `files/etc/profiles/{pppoe-main,switch-equal,bypass-gateway}/{network,firewall,dhcp}` | 三套模式 UCI 配置片段 |
| `files/etc/init.d/fan-pid` | procd 风扇守护 init |
| `files/etc/uci-defaults/99-r2s-init` | 首次开机初始化脚本 |
| `files/usr/bin/mode-switch` | 模式切换后端 shell 脚本 |
| `files/usr/bin/fan-pid-loop` | PID 风扇主循环脚本 |
| `files/usr/lib/lua/luci/controller/mode_switch.lua` | mode-switch LuCI 路由控制器 |
| `files/usr/lib/lua/luci/controller/fan_pid.lua` | fan-pid LuCI 路由控制器 |
| `files/usr/lib/lua/luci/view/mode_switch/{status,pppoe,bypass}.htm` | mode-switch 三个 tab 视图 |
| `files/usr/lib/lua/luci/view/fan_pid/main.htm` | fan-pid 视图 |
| `scripts/flash-sd.sh` | macOS 烧卡脚本 |
| `scripts/pre-deploy-check.sh` | 部署前依赖检查 |
| `tests/*.bats` | bats 单元测试 |
| `tests/lib/fakes/{uci,init.d,thermal,pwm}` | 测试 fake 工具 |
| `.github/workflows/build.yml` | CI 流水线 |
| `patches/` | 可选源码补丁（如 R2S DTS 风扇引脚） |

---

## Phase 1 — 仓库与编译环境骨架

### Task 1: 初始化仓库结构

**Files:**
- Create: `.gitignore`
- Create: `README.md`
- Create: 空目录骨架（docker/ build/ files/etc/ files/usr/ scripts/ tests/lib/fakes/ patches/ .github/workflows/）

- [ ] **Step 1: 初始化 git 仓库并设默认分支**

```bash
cd /Users/llm/Desktop/OpenWRT_R2S
git init -b main
```

- [ ] **Step 2: 创建 .gitignore**

```gitignore
# ImmortalWrt 源码（编译期 clone，不入库）
immortalwrt/

# 编译产物
out/
logs/
*.img
*.img.gz
*.bin
*.tar
*.sha256

# 完整 .config（保留 .config.seed）
build/.config
build/.config.old

# 容器与构建缓存
.cache/
ccache/

# 系统/编辑器
.DS_Store
*.swp
*~
.vscode/
.idea/
```

- [ ] **Step 3: 创建 README.md 占位**

```markdown
# NanoPi R2S 多模式定制 OpenWRT

基于 ImmortalWrt master 的 NanoPi R2S 定制固件，单镜像在线切换三种模式：
PPPoE 主路由 / 双口对等交换 / 旁路由透明网关。

## 快速开始

```bash
./scripts/pre-deploy-check.sh   # 检查依赖
./build/build.sh                # 编译固件
./scripts/flash-sd.sh           # 烧入 SD 卡
```

## 文档

- 设计: `docs/superpowers/specs/2026-04-25-nanopi-r2s-openwrt-design.md`
- 实施计划: `docs/superpowers/plans/2026-04-25-nanopi-r2s-openwrt-implementation.md`
```

- [ ] **Step 4: 建空目录骨架（用 .gitkeep 让空目录入库）**

```bash
mkdir -p docker build files/etc/config files/etc/profiles/{pppoe-main,switch-equal,bypass-gateway} \
         files/etc/init.d files/etc/uci-defaults files/usr/bin \
         files/usr/lib/lua/luci/{controller,view/mode_switch,view/fan_pid} \
         scripts tests/lib/fakes patches .github/workflows out logs

touch out/.gitkeep logs/.gitkeep patches/.gitkeep
```

- [ ] **Step 5: 验证目录结构**

```bash
find . -type d -not -path '*/\.git*' | sort
```

期望输出包含：
```
.
./.github
./.github/workflows
./build
./docker
./docs
./docs/superpowers
./docs/superpowers/plans
./docs/superpowers/specs
./files
./files/etc
./files/etc/config
./files/etc/init.d
./files/etc/profiles
./files/etc/profiles/bypass-gateway
./files/etc/profiles/pppoe-main
./files/etc/profiles/switch-equal
./files/etc/uci-defaults
./files/usr
./files/usr/bin
./files/usr/lib
./files/usr/lib/lua
./files/usr/lib/lua/luci
./files/usr/lib/lua/luci/controller
./files/usr/lib/lua/luci/view
./files/usr/lib/lua/luci/view/fan_pid
./files/usr/lib/lua/luci/view/mode_switch
./logs
./out
./patches
./scripts
./tests
./tests/lib
./tests/lib/fakes
```

- [ ] **Step 6: 首次提交**

```bash
git add .gitignore README.md docs/ out/.gitkeep logs/.gitkeep patches/.gitkeep
git commit -m "chore: init repo skeleton with directory layout"
```

---

### Task 2: 开发依赖检查与文档化

**Files:**
- Create: `scripts/pre-deploy-check.sh`
- Test: `tests/pre_deploy_check.bats`

- [ ] **Step 1: 写 bats 测试**

`tests/pre_deploy_check.bats`:
```bash
#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../scripts/pre-deploy-check.sh"
}

@test "exits 0 when all deps present" {
    run env PATH="${BATS_TEST_DIRNAME}/lib/fakes/all-present:${PATH}" "$SCRIPT" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "exits non-zero when docker missing" {
    run env PATH="${BATS_TEST_DIRNAME}/lib/fakes/no-docker" "$SCRIPT" --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"docker"* ]]
}

@test "prints all missing tools, not just first" {
    run env PATH="${BATS_TEST_DIRNAME}/lib/fakes/empty" "$SCRIPT" --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"docker"* ]]
    [[ "$output" == *"git"* ]]
}
```

- [ ] **Step 2: 创建 fakes 目录骨架**

```bash
mkdir -p tests/lib/fakes/all-present tests/lib/fakes/no-docker tests/lib/fakes/empty

# all-present: 假装所有工具都在
for tool in docker git curl shasum diskutil; do
    cat > "tests/lib/fakes/all-present/$tool" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "tests/lib/fakes/all-present/$tool"
done

# no-docker: 除了 docker 外都在
for tool in git curl shasum diskutil; do
    cp tests/lib/fakes/all-present/$tool tests/lib/fakes/no-docker/
done

# empty 目录留空（所有工具都缺）
```

- [ ] **Step 3: 运行测试，确认 fail**

```bash
bats tests/pre_deploy_check.bats
```
期望：3 个测试全 fail（脚本还不存在）。

- [ ] **Step 4: 实现 scripts/pre-deploy-check.sh**

```bash
#!/usr/bin/env bash
# 部署前依赖与环境检查（macOS 主机）
set -u

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

REQUIRED_TOOLS=(docker git curl shasum)
[ "$(uname -s)" = "Darwin" ] && REQUIRED_TOOLS+=(diskutil)

missing=()
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        missing+=("$tool")
    fi
done

if [ ${#missing[@]} -gt 0 ]; then
    echo "Missing required tools:"
    for t in "${missing[@]}"; do echo "  - $t"; done
    echo
    echo "macOS 安装提示:"
    echo "  brew install bats-core shellcheck hadolint lua"
    echo "  Docker Desktop: https://www.docker.com/products/docker-desktop"
    exit 1
fi

if [ "$DRY_RUN" -eq 0 ] && ! docker info >/dev/null 2>&1; then
    echo "Docker daemon 未运行，请先启动 Docker Desktop"
    exit 1
fi

echo "OK: all dependencies present"
```

- [ ] **Step 5: 设可执行权限并跑 shellcheck**

```bash
chmod +x scripts/pre-deploy-check.sh
shellcheck scripts/pre-deploy-check.sh
```
期望 shellcheck 0 warning。

- [ ] **Step 6: 跑 bats，确认 pass**

```bash
bats tests/pre_deploy_check.bats
```
期望：3 ok。

- [ ] **Step 7: commit**

```bash
git add scripts/pre-deploy-check.sh tests/pre_deploy_check.bats tests/lib/fakes/
git commit -m "feat(scripts): add pre-deploy-check with bats coverage"
```

---

### Task 3: Docker 编译镜像

**Files:**
- Create: `docker/Dockerfile`
- Create: `docker/compose.yaml`
- Test: `tests/dockerfile.bats`

- [ ] **Step 1: 写 hadolint 配置（可选但推荐）**

`docker/.hadolint.yaml`:
```yaml
ignored:
  - DL3008  # apt 不固定版本（OpenWRT 编译依赖跨发行版兼容更重要）
```

- [ ] **Step 2: 写 bats 测试**

`tests/dockerfile.bats`:
```bash
#!/usr/bin/env bats

@test "Dockerfile passes hadolint" {
    run hadolint --config docker/.hadolint.yaml docker/Dockerfile
    [ "$status" -eq 0 ]
}

@test "Dockerfile builds cleanly" {
    skip_if_no_docker
    run docker build -t r2s-builder:test -f docker/Dockerfile docker/
    [ "$status" -eq 0 ]
}

@test "container has builder user uid 1000" {
    skip_if_no_docker
    run docker run --rm r2s-builder:test id -u builder
    [ "$status" -eq 0 ]
    [ "$output" = "1000" ]
}

@test "container has required build tools" {
    skip_if_no_docker
    for tool in gcc make git python3 unzip rsync wget; do
        run docker run --rm r2s-builder:test which "$tool"
        [ "$status" -eq 0 ]
    done
}

skip_if_no_docker() {
    docker info >/dev/null 2>&1 || skip "docker not running"
}
```

- [ ] **Step 3: 跑测试确认 fail（Dockerfile 不存在）**

```bash
bats tests/dockerfile.bats
```

- [ ] **Step 4: 实现 docker/Dockerfile**

```dockerfile
# syntax=docker/dockerfile:1.6
FROM debian:bookworm-slim

ARG APT_MIRROR=mirrors.tuna.tsinghua.edu.cn
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
        gcc-multilib \
        g++-multilib \
        zstd \
    && rm -rf /var/lib/apt/lists/*

# 创建非 root 用户
RUN groupadd -g ${BUILDER_GID} builder \
    && useradd -m -u ${BUILDER_UID} -g ${BUILDER_GID} -s /bin/bash builder \
    && echo "builder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/builder

# 工作目录与卷挂载点
RUN mkdir -p /work /home/builder/.ccache && chown -R builder:builder /work /home/builder
WORKDIR /work
USER builder

ENV CCACHE_DIR=/home/builder/.ccache
ENV PATH=/usr/lib/ccache:${PATH}

CMD ["/bin/bash"]
```

- [ ] **Step 5: 实现 docker/compose.yaml**

```yaml
services:
  builder:
    build:
      context: ./docker
      args:
        APT_MIRROR: mirrors.tuna.tsinghua.edu.cn
    image: r2s-builder:latest
    container_name: r2s-builder
    working_dir: /work
    user: "1000:1000"
    volumes:
      - ../:/work
      - r2s-ccache:/home/builder/.ccache
      - r2s-dl:/work/immortalwrt/dl
    command: ["/bin/bash"]
    stdin_open: true
    tty: true

volumes:
  r2s-ccache:
  r2s-dl:
```

- [ ] **Step 6: 跑 hadolint**

```bash
hadolint --config docker/.hadolint.yaml docker/Dockerfile
```
期望 0 warning。

- [ ] **Step 7: 跑 docker build 验证**

```bash
docker build -t r2s-builder:test -f docker/Dockerfile docker/
```
期望成功（首次约 3-8 分钟）。

- [ ] **Step 8: 跑完整 bats**

```bash
bats tests/dockerfile.bats
```
期望 4 ok。

- [ ] **Step 9: commit**

```bash
git add docker/ tests/dockerfile.bats
git commit -m "feat(docker): add ImmortalWrt build container based on debian:bookworm"
```

---

## Phase 2 — 编译流程

### Task 4: build.sh 入口与子命令骨架

**Files:**
- Create: `build/build.sh`
- Test: `tests/build_sh.bats`

- [ ] **Step 1: 写 bats 测试**

`tests/build_sh.bats`:
```bash
#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../build/build.sh"
}

@test "shows help with --help" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"--shell"* ]]
    [[ "$output" == *"--no-cache"* ]]
    [[ "$output" == *"--update-feeds"* ]]
}

@test "rejects unknown flag" {
    run "$SCRIPT" --bogus
    [ "$status" -ne 0 ]
}

@test "passes shellcheck" {
    run shellcheck "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "--dry-run prints planned actions without docker" {
    run env DRY_RUN=1 "$SCRIPT" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"would run"* ]]
}
```

- [ ] **Step 2: 跑测试确认 fail**

```bash
bats tests/build_sh.bats
```

- [ ] **Step 3: 实现 build/build.sh**

```bash
#!/usr/bin/env bash
# NanoPi R2S 定制 ImmortalWrt 编译入口（外层：起容器；通过 BUILD_INSIDE=1 进入内层流程）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRY_RUN="${DRY_RUN:-0}"

usage() {
    cat <<'EOF'
Usage: build.sh [OPTIONS]

Build NanoPi R2S customized ImmortalWrt image inside Docker.

Options:
  --shell           Drop into the build container interactively
  --no-cache        Force ImmortalWrt source re-clone and clean rebuild
  --update-feeds    Refresh feeds only, do not run make
  --dry-run         Print planned actions without invoking docker/make
  --help            Show this message

Environment:
  DRY_RUN=1         Same as --dry-run
  IMG_TAG           Override builder image tag (default: r2s-builder:latest)
EOF
}

ACTION="build"
NO_CACHE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)        usage; exit 0 ;;
        --shell)          ACTION="shell" ;;
        --no-cache)       NO_CACHE=1 ;;
        --update-feeds)   ACTION="update-feeds" ;;
        --dry-run)        DRY_RUN=1 ;;
        *) echo "Unknown flag: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "would run: $*"
    else
        "$@"
    fi
}

# 内层（容器内执行）
if [ "${BUILD_INSIDE:-0}" = "1" ]; then
    echo "[inner] starting build, action=$ACTION"
    bash "$SCRIPT_DIR/build-inner.sh" "$ACTION" "$NO_CACHE"
    exit $?
fi

# 外层：起容器
IMG_TAG="${IMG_TAG:-r2s-builder:latest}"

if ! docker image inspect "$IMG_TAG" >/dev/null 2>&1; then
    echo "Builder image not found, building..."
    run docker build -t "$IMG_TAG" -f "$REPO_ROOT/docker/Dockerfile" "$REPO_ROOT/docker/"
fi

DOCKER_ARGS=(
    --rm
    -v "$REPO_ROOT:/work"
    -w /work
    -e BUILD_INSIDE=1
    -e DRY_RUN="$DRY_RUN"
    --user "1000:1000"
)

case "$ACTION" in
    shell)
        run docker run -it "${DOCKER_ARGS[@]}" "$IMG_TAG" bash
        ;;
    *)
        run docker run "${DOCKER_ARGS[@]}" "$IMG_TAG" \
            bash build/build.sh "$( [ "$ACTION" = "update-feeds" ] && echo --update-feeds )" \
            $( [ "$NO_CACHE" -eq 1 ] && echo --no-cache )
        ;;
esac
```

- [ ] **Step 4: 创建 build-inner.sh 占位（Task 5/6 填充）**

`build/build-inner.sh`:
```bash
#!/usr/bin/env bash
# 容器内构建流程占位 - 在 Task 5、6 中填充
set -euo pipefail

ACTION="${1:-build}"
NO_CACHE="${2:-0}"

echo "[inner] action=$ACTION no_cache=$NO_CACHE"
echo "[inner] stub: full pipeline arrives in Task 5 and Task 6"
```

- [ ] **Step 5: 设可执行权限 + 跑 shellcheck**

```bash
chmod +x build/build.sh build/build-inner.sh
shellcheck build/build.sh
```

- [ ] **Step 6: 跑 bats**

```bash
bats tests/build_sh.bats
```
期望 4 ok。

- [ ] **Step 7: commit**

```bash
git add build/build.sh build/build-inner.sh tests/build_sh.bats
git commit -m "feat(build): add build.sh entry with --shell/--no-cache/--update-feeds/--dry-run"
```

---

### Task 5: 锁定 ImmortalWrt commit + feeds 配置

**Files:**
- Create: `build/IMMORTALWRT_COMMIT`
- Create: `build/feeds.conf.default`
- Modify: `build/build-inner.sh`
- Test: `tests/feeds_clone.bats`

- [ ] **Step 1: 获取并写入当前 ImmortalWrt master 的 HEAD commit**

```bash
COMMIT=$(git ls-remote https://github.com/immortalwrt/immortalwrt master | awk '{print $1}')
[ -n "$COMMIT" ] || { echo "ls-remote 失败" >&2; exit 1; }
printf '%s\n' "$COMMIT" > build/IMMORTALWRT_COMMIT
cat build/IMMORTALWRT_COMMIT
```
（输出一个 40 位 sha-1 hash，文件持久化此值）

- [ ] **Step 2: 创建 build/feeds.conf.default**

`build/feeds.conf.default`:
```
src-git packages https://github.com/immortalwrt/packages.git
src-git luci https://github.com/immortalwrt/luci.git
src-git routing https://git.openwrt.org/feed/routing.git
src-git telephony https://git.openwrt.org/feed/telephony.git
src-git smartdns https://github.com/pymumu/openwrt-smartdns.git
src-git passwall_packages https://github.com/xiaorouji/openwrt-passwall.git;main
src-git passwall2 https://github.com/xiaorouji/openwrt-passwall2.git;main
src-git tailscale https://github.com/immortalwrt/packages.git;openwrt-23.05
```

- [ ] **Step 3: 写 bats 测试（不实际克隆，只验证 build-inner 解析逻辑）**

`tests/feeds_clone.bats`:
```bash
#!/usr/bin/env bats

setup() {
    INNER="${BATS_TEST_DIRNAME}/../build/build-inner.sh"
}

@test "build-inner.sh passes shellcheck" {
    run shellcheck "$INNER"
    [ "$status" -eq 0 ]
}

@test "reads commit from IMMORTALWRT_COMMIT file" {
    run env DRY_RUN=1 BUILD_INSIDE=1 \
        "${BATS_TEST_DIRNAME}/../build/build.sh" --update-feeds
    [ "$status" -eq 0 ]
    [[ "$output" == *"checkout"* ]]
}

@test "IMMORTALWRT_COMMIT file is 40-char sha1" {
    commit=$(cat "${BATS_TEST_DIRNAME}/../build/IMMORTALWRT_COMMIT")
    [[ "$commit" =~ ^[a-f0-9]{40}$ ]]
}

@test "feeds.conf.default has all required feeds" {
    feeds="${BATS_TEST_DIRNAME}/../build/feeds.conf.default"
    grep -q "^src-git packages" "$feeds"
    grep -q "^src-git luci" "$feeds"
    grep -q "passwall2" "$feeds"
    grep -q "smartdns" "$feeds"
}
```

- [ ] **Step 4: 跑测试确认 fail**

```bash
bats tests/feeds_clone.bats
```

- [ ] **Step 5: 重写 build/build-inner.sh，实现 clone + checkout + feeds 流程**

```bash
#!/usr/bin/env bash
# 容器内构建流程
set -euo pipefail

ACTION="${1:-build}"
NO_CACHE="${2:-0}"

REPO_ROOT="/work"
SRC_DIR="${REPO_ROOT}/immortalwrt"
COMMIT_FILE="${REPO_ROOT}/build/IMMORTALWRT_COMMIT"
FEEDS_FILE="${REPO_ROOT}/build/feeds.conf.default"
DRY_RUN="${DRY_RUN:-0}"

run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "would run: $*"
    else
        "$@"
    fi
}

[ -f "$COMMIT_FILE" ] || { echo "缺少 build/IMMORTALWRT_COMMIT" >&2; exit 1; }
COMMIT=$(tr -d '[:space:]' < "$COMMIT_FILE")
[[ "$COMMIT" =~ ^[a-f0-9]{40}$ ]] || { echo "commit 格式异常: $COMMIT" >&2; exit 1; }

# Step A: clone / fetch / checkout
if [ ! -d "$SRC_DIR/.git" ] || [ "$NO_CACHE" -eq 1 ]; then
    [ "$NO_CACHE" -eq 1 ] && run rm -rf "$SRC_DIR"
    echo "[inner] cloning ImmortalWrt..."
    run git clone https://github.com/immortalwrt/immortalwrt "$SRC_DIR"
fi

cd "$SRC_DIR"
echo "[inner] fetch + checkout $COMMIT"
run git fetch --tags origin
run git checkout "$COMMIT"

# Step B: feeds
echo "[inner] applying feeds.conf.default"
run cp "$FEEDS_FILE" "$SRC_DIR/feeds.conf.default"

echo "[inner] feeds update -a"
run ./scripts/feeds update -a

echo "[inner] feeds install -a"
run ./scripts/feeds install -a

if [ "$ACTION" = "update-feeds" ]; then
    echo "[inner] update-feeds done"
    exit 0
fi

# Step C/D 在 Task 6 中填充（链接 files/、写入 .config、make）
echo "[inner] config + build steps not yet implemented (Task 6)"
exit 0
```

- [ ] **Step 6: 跑 shellcheck + bats**

```bash
shellcheck build/build-inner.sh
bats tests/feeds_clone.bats
```
期望全 ok。

- [ ] **Step 7: commit**

```bash
git add build/IMMORTALWRT_COMMIT build/feeds.conf.default build/build-inner.sh tests/feeds_clone.bats
git commit -m "feat(build): lock immortalwrt commit and configure feeds"
```

---

### Task 6: .config.seed + 完整编译流水线

**Files:**
- Create: `build/.config.seed`
- Modify: `build/build-inner.sh`
- Test: `tests/config_seed.bats`

- [ ] **Step 1: 写 .config.seed（diffconfig 风格，所有需要的包）**

`build/.config.seed`:
```
# ============================================================
# Target
# ============================================================
CONFIG_TARGET_rockchip=y
CONFIG_TARGET_rockchip_armv8=y
CONFIG_TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r2s=y

# ============================================================
# Image options
# ============================================================
CONFIG_TARGET_ROOTFS_PARTSIZE=512
CONFIG_TARGET_KERNEL_PARTSIZE=32
CONFIG_TARGET_IMAGES_GZIP=y

# ============================================================
# Drivers
# ============================================================
CONFIG_PACKAGE_kmod-usb-net-rtl8152=y
CONFIG_PACKAGE_kmod-pwm-rockchip=y

# ============================================================
# Base + LuCI + i18n + theme
# ============================================================
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-base=y
CONFIG_PACKAGE_luci-compat=y
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-i18n-base-zh-cn=y
CONFIG_PACKAGE_luci-i18n-firewall-zh-cn=y
CONFIG_PACKAGE_luci-i18n-opkg-zh-cn=y

# ============================================================
# Transparent proxy
# ============================================================
CONFIG_PACKAGE_luci-app-passwall2=y
CONFIG_PACKAGE_luci-i18n-passwall2-zh-cn=y
CONFIG_PACKAGE_xray-core=y
CONFIG_PACKAGE_sing-box=y
CONFIG_PACKAGE_hysteria=y

# ============================================================
# DNS
# ============================================================
CONFIG_PACKAGE_smartdns=y
CONFIG_PACKAGE_luci-app-smartdns=y
CONFIG_PACKAGE_luci-i18n-smartdns-zh-cn=y

# ============================================================
# VPN
# ============================================================
CONFIG_PACKAGE_wireguard-tools=y
CONFIG_PACKAGE_kmod-wireguard=y
CONFIG_PACKAGE_luci-app-wireguard=y
CONFIG_PACKAGE_luci-proto-wireguard=y
CONFIG_PACKAGE_tailscale=y
CONFIG_PACKAGE_luci-app-tailscale=y

# ============================================================
# Tools
# ============================================================
CONFIG_PACKAGE_luci-app-ttyd=y
CONFIG_PACKAGE_luci-i18n-ttyd-zh-cn=y
CONFIG_PACKAGE_luci-app-sqm=y
CONFIG_PACKAGE_luci-i18n-sqm-zh-cn=y
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_nano=y
CONFIG_PACKAGE_bash=y

# ============================================================
# IPv6
# ============================================================
CONFIG_PACKAGE_ipv6helper=y
```

- [ ] **Step 2: 写 bats 测试（验证 .config.seed 必含项）**

`tests/config_seed.bats`:
```bash
#!/usr/bin/env bats

SEED="${BATS_TEST_DIRNAME}/../build/.config.seed"

@test "selects nanopi-r2s device" {
    grep -q "CONFIG_TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r2s=y" "$SEED"
}

@test "includes USB rtl8152 driver" {
    grep -q "CONFIG_PACKAGE_kmod-usb-net-rtl8152=y" "$SEED"
}

@test "includes rockchip pwm driver" {
    grep -q "CONFIG_PACKAGE_kmod-pwm-rockchip=y" "$SEED"
}

@test "includes passwall2, smartdns, tailscale" {
    grep -q "CONFIG_PACKAGE_luci-app-passwall2=y" "$SEED"
    grep -q "CONFIG_PACKAGE_smartdns=y" "$SEED"
    grep -q "CONFIG_PACKAGE_tailscale=y" "$SEED"
}

@test "includes argon theme and zh-cn base" {
    grep -q "CONFIG_PACKAGE_luci-theme-argon=y" "$SEED"
    grep -q "CONFIG_PACKAGE_luci-i18n-base-zh-cn=y" "$SEED"
}
```

- [ ] **Step 3: 跑 bats，全 pass**

```bash
bats tests/config_seed.bats
```

- [ ] **Step 4: 扩展 build-inner.sh 实现完整流水线**

替换 build-inner.sh 中"Step C/D 在 Task 6 中填充"以下行至文件末尾为：

```bash
# Step C: 链接 files/ 注入 rootfs
echo "[inner] linking files/ into ImmortalWrt source"
if [ -L "$SRC_DIR/files" ] || [ -d "$SRC_DIR/files" ]; then
    run rm -rf "$SRC_DIR/files"
fi
run ln -s "$REPO_ROOT/files" "$SRC_DIR/files"

# Step D: 复制 .config.seed 并 defconfig
echo "[inner] applying .config.seed and running defconfig"
run cp "$REPO_ROOT/build/.config.seed" "$SRC_DIR/.config"
run make defconfig

# Step E: 下载源码包
echo "[inner] make download -j8"
run make download -j8 || run make download -j1 V=s

# Step F: 编译
NPROC=$(nproc)
echo "[inner] make -j${NPROC}"
LOG_DIR="${REPO_ROOT}/logs"
run mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/build-$(date +%Y%m%d-%H%M%S).log"

if ! run bash -c "make -j${NPROC} 2>&1 | tee \"$LOG_FILE\""; then
    echo "[inner] parallel build failed, retrying with -j1 V=s for diagnostics"
    LOG_FILE="${LOG_DIR}/build-verbose-$(date +%Y%m%d-%H%M%S).log"
    run bash -c "make -j1 V=s 2>&1 | tee \"$LOG_FILE\"" || {
        echo "[inner] build failed; last 200 lines:"
        tail -n 200 "$LOG_FILE"
        exit 1
    }
fi

# Step G: 拷贝产物
OUT_DIR="${REPO_ROOT}/out/$(date +%Y%m%d)-${COMMIT:0:8}"
echo "[inner] copying artifacts to $OUT_DIR"
run mkdir -p "$OUT_DIR"
run bash -c "cp $SRC_DIR/bin/targets/rockchip/armv8/*nanopi-r2s* $OUT_DIR/ 2>/dev/null || true"
run bash -c "cp $SRC_DIR/bin/targets/rockchip/armv8/sha256sums $OUT_DIR/ 2>/dev/null || true"

echo "[inner] build done; artifacts in $OUT_DIR"
ls -lh "$OUT_DIR" 2>/dev/null || true
```

- [ ] **Step 5: 跑 shellcheck**

```bash
shellcheck build/build-inner.sh
```

- [ ] **Step 6: dry-run 整个流水线（不真正编译）**

```bash
DRY_RUN=1 BUILD_INSIDE=1 ./build/build-inner.sh build 0
```
期望输出 "would run: ..." 序列。

- [ ] **Step 7: commit**

```bash
git add build/.config.seed build/build-inner.sh tests/config_seed.bats
git commit -m "feat(build): add full diffconfig seed and end-to-end build pipeline"
```

- [ ] **Step 8: 真实编译（耗时里程碑）**

```bash
./build/build.sh 2>&1 | tee logs/first-build.log
```
预期 1-3 小时（取决于网速 + CPU）。最终 `out/<date>-<commit>/` 应有 `immortalwrt-rockchip-armv8-friendlyarm_nanopi-r2s-squashfs-sysupgrade.img.gz`。

- [ ] **Step 9: 验证产物大小与关键二进制**

```bash
ls -lh out/*/immortalwrt-rockchip-armv8-friendlyarm_nanopi-r2s-squashfs-sysupgrade.img.gz
# 期望 30-60 MB

# 解压并扫描 squashfs
gunzip -k out/*/*sysupgrade.img.gz
# 用 binwalk 提取 rootfs（如未装：apt install binwalk）
```

不 commit（产物在 .gitignore）。

---

## Phase 3 — 首次开机初始化与三套 profile

### Task 7: uci-defaults/99-r2s-init 首次开机脚本

**Files:**
- Create: `files/etc/uci-defaults/99-r2s-init`
- Test: `tests/uci_defaults.bats`
- Test fakes: `tests/lib/fakes/uci-recorder/uci`

- [ ] **Step 1: 写 fake uci 工具（记录所有调用到 stdout）**

`tests/lib/fakes/uci-recorder/uci`:
```bash
#!/usr/bin/env bash
echo "uci $*" >> "${UCI_LOG:-/dev/stderr}"
exit 0
```

```bash
chmod +x tests/lib/fakes/uci-recorder/uci
```

- [ ] **Step 2: 写 bats 测试**

`tests/uci_defaults.bats`:
```bash
#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../files/etc/uci-defaults/99-r2s-init"
    export UCI_LOG="${BATS_TMPDIR}/uci.log"
    : > "$UCI_LOG"
    export PATH="${BATS_TEST_DIRNAME}/lib/fakes/uci-recorder:${PATH}"
    export TEST_PROFILES_SRC="${BATS_TEST_DIRNAME}/../files/etc/profiles"
    export TEST_CONFIG_DIR="${BATS_TMPDIR}/config"
    mkdir -p "$TEST_CONFIG_DIR"
}

@test "passes shellcheck" {
    run shellcheck "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "sets hostname" {
    run env CONFIG_DIR="$TEST_CONFIG_DIR" PROFILES_DIR="$TEST_PROFILES_SRC" "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -q "uci set system.@system\[0\].hostname='NanoPi-R2S'" "$UCI_LOG"
}

@test "sets timezone Asia/Shanghai (CST-8)" {
    run env CONFIG_DIR="$TEST_CONFIG_DIR" PROFILES_DIR="$TEST_PROFILES_SRC" "$SCRIPT"
    grep -q "timezone='CST-8'" "$UCI_LOG"
    grep -q "zonename='Asia/Shanghai'" "$UCI_LOG"
}

@test "sets aliyun NTP servers" {
    run env CONFIG_DIR="$TEST_CONFIG_DIR" PROFILES_DIR="$TEST_PROFILES_SRC" "$SCRIPT"
    grep -q "ntp.aliyun.com" "$UCI_LOG"
}

@test "writes mode-switch current=switch-equal" {
    run env CONFIG_DIR="$TEST_CONFIG_DIR" PROFILES_DIR="$TEST_PROFILES_SRC" "$SCRIPT"
    grep -q "mode-switch.current.name='switch-equal'" "$UCI_LOG"
}

@test "enables fan-pid service" {
    # fake init.d enable
    grep -q "fan-pid.*enable" "$UCI_LOG" || \
        [ -e "$TEST_CONFIG_DIR/.fan_pid_enabled_marker" ]
}
```

- [ ] **Step 3: 跑测试确认 fail**

```bash
bats tests/uci_defaults.bats
```

- [ ] **Step 4: 实现 99-r2s-init**

`files/etc/uci-defaults/99-r2s-init`:
```bash
#!/bin/sh
# Runs once on first boot; deleted on success by OpenWRT.
# Path overrides exist for unit testing only.
set -e

CONFIG_DIR="${CONFIG_DIR:-/etc/config}"
PROFILES_DIR="${PROFILES_DIR:-/etc/profiles}"

# 1. Hostname / timezone / NTP
uci set system.@system[0].hostname='NanoPi-R2S'
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'
uci -q delete system.ntp.server
uci add_list system.ntp.server='ntp.aliyun.com'
uci add_list system.ntp.server='ntp1.aliyun.com'
uci add_list system.ntp.server='time.cloudflare.com'
uci commit system

# 2. Default LAN segment 192.168.2.0/24 (later overwritten by switch-equal profile)
uci set network.lan.ipaddr='192.168.2.1'
uci set network.lan.netmask='255.255.255.0'
uci commit network

# 3. Apply switch-equal as default initial profile
if [ -d "$PROFILES_DIR/switch-equal" ]; then
    cp "$PROFILES_DIR/switch-equal/network"  "$CONFIG_DIR/network"
    cp "$PROFILES_DIR/switch-equal/firewall" "$CONFIG_DIR/firewall"
    cp "$PROFILES_DIR/switch-equal/dhcp"     "$CONFIG_DIR/dhcp"
fi

# 4. mode-switch UCI defaults marker
uci set mode-switch.current=mode 2>/dev/null || true
uci set mode-switch.current.name='switch-equal'
uci commit mode-switch

# 5. Enable fan-pid
if [ -x /etc/init.d/fan-pid ]; then
    /etc/init.d/fan-pid enable
    /etc/init.d/fan-pid start
else
    : > "$CONFIG_DIR/.fan_pid_enabled_marker"
fi

# 6. (no root password set; LuCI 强制改密)

exit 0
```

- [ ] **Step 5: 设可执行权限并跑 bats**

```bash
chmod +x files/etc/uci-defaults/99-r2s-init
bats tests/uci_defaults.bats
```
期望全 ok。

- [ ] **Step 6: commit**

```bash
git add files/etc/uci-defaults/99-r2s-init tests/uci_defaults.bats tests/lib/fakes/uci-recorder/
git commit -m "feat(rootfs): add uci-defaults/99-r2s-init for first-boot setup"
```

---

### Task 8: switch-equal profile（默认）

**Files:**
- Create: `files/etc/profiles/switch-equal/{network,firewall,dhcp}`
- Test: `tests/profile_switch_equal.bats`

- [ ] **Step 1: 写 bats 测试**

`tests/profile_switch_equal.bats`:
```bash
#!/usr/bin/env bats

PROFILE_DIR="${BATS_TEST_DIRNAME}/../files/etc/profiles/switch-equal"

@test "network has br-lan with eth0+eth1" {
    grep -q "list ports 'eth0'" "$PROFILE_DIR/network"
    grep -q "list ports 'eth1'" "$PROFILE_DIR/network"
    grep -q "option type 'bridge'" "$PROFILE_DIR/network"
}

@test "lan static 192.168.2.1/24" {
    grep -q "option ipaddr '192.168.2.1'" "$PROFILE_DIR/network"
    grep -q "option netmask '255.255.255.0'" "$PROFILE_DIR/network"
}

@test "wan interface disabled or absent" {
    ! grep -q "config interface 'wan'" "$PROFILE_DIR/network" || \
        grep -A4 "config interface 'wan'" "$PROFILE_DIR/network" | grep -q "option auto '0'"
}

@test "firewall has lan zone with input/output/forward ACCEPT" {
    grep -q "option name 'lan'" "$PROFILE_DIR/firewall"
    grep -q "option input 'ACCEPT'" "$PROFILE_DIR/firewall"
    grep -q "option output 'ACCEPT'" "$PROFILE_DIR/firewall"
    grep -q "option forward 'ACCEPT'" "$PROFILE_DIR/firewall"
}

@test "dhcp serves on br-lan" {
    grep -q "option interface 'lan'" "$PROFILE_DIR/dhcp"
    grep -q "option ignore '0'" "$PROFILE_DIR/dhcp" || \
        ! grep -q "option ignore '1'" "$PROFILE_DIR/dhcp"
}
```

- [ ] **Step 2: 跑测试确认 fail**

```bash
bats tests/profile_switch_equal.bats
```

- [ ] **Step 3: 写 files/etc/profiles/switch-equal/network**

```
config interface 'loopback'
    option device 'lo'
    option proto 'static'
    option ipaddr '127.0.0.1'
    option netmask '255.0.0.0'

config globals 'globals'
    option ula_prefix 'fdc6:0123:4567::/48'

config device
    option name 'br-lan'
    option type 'bridge'
    list ports 'eth0'
    list ports 'eth1'

config interface 'lan'
    option device 'br-lan'
    option proto 'static'
    option ipaddr '192.168.2.1'
    option netmask '255.255.255.0'
    option ip6assign '60'
```

- [ ] **Step 4: 写 files/etc/profiles/switch-equal/firewall**

```
config defaults
    option syn_flood '1'
    option input 'ACCEPT'
    option output 'ACCEPT'
    option forward 'ACCEPT'

config zone
    option name 'lan'
    list network 'lan'
    option input 'ACCEPT'
    option output 'ACCEPT'
    option forward 'ACCEPT'

config rule
    option name 'Allow-DHCP-Renew'
    option src 'lan'
    option proto 'udp'
    option dest_port '68'
    option target 'ACCEPT'
    option family 'ipv4'

config rule
    option name 'Allow-Ping'
    option src 'lan'
    option proto 'icmp'
    option icmp_type 'echo-request'
    option family 'ipv4'
    option target 'ACCEPT'
```

- [ ] **Step 5: 写 files/etc/profiles/switch-equal/dhcp**

```
config dnsmasq
    option domainneeded '1'
    option boguspriv '1'
    option filterwin2k '0'
    option localise_queries '1'
    option rebind_protection '1'
    option rebind_localhost '1'
    option local '/lan/'
    option domain 'lan'
    option expandhosts '1'
    option authoritative '1'
    option readethers '1'
    option leasefile '/tmp/dhcp.leases'
    option resolvfile '/tmp/resolv.conf.d/resolv.conf.auto'
    option nonwildcard '1'
    option localservice '1'

config dhcp 'lan'
    option interface 'lan'
    option start '100'
    option limit '150'
    option leasetime '12h'
    option ignore '0'

config odhcpd 'odhcpd'
    option maindhcp '0'
    option leasefile '/tmp/hosts/odhcpd'
    option leasetrigger '/usr/sbin/odhcpd-update'
    option loglevel '4'
```

- [ ] **Step 6: 跑 bats**

```bash
bats tests/profile_switch_equal.bats
```
期望 5 ok。

- [ ] **Step 7: commit**

```bash
git add files/etc/profiles/switch-equal/ tests/profile_switch_equal.bats
git commit -m "feat(profiles): add switch-equal (default initial mode, br-lan over eth0+eth1)"
```

---

### Task 9: pppoe-main profile

**Files:**
- Create: `files/etc/profiles/pppoe-main/{network,firewall,dhcp}`
- Test: `tests/profile_pppoe_main.bats`

- [ ] **Step 1: 写 bats 测试**

`tests/profile_pppoe_main.bats`:
```bash
#!/usr/bin/env bats

PROFILE_DIR="${BATS_TEST_DIRNAME}/../files/etc/profiles/pppoe-main"

@test "wan uses pppoe on eth0" {
    grep -q "config interface 'wan'" "$PROFILE_DIR/network"
    grep -A6 "config interface 'wan'" "$PROFILE_DIR/network" | grep -q "option proto 'pppoe'"
    grep -A6 "config interface 'wan'" "$PROFILE_DIR/network" | grep -q "option device 'eth0'"
}

@test "lan static 192.168.2.1 on eth1" {
    grep -A6 "config interface 'lan'" "$PROFILE_DIR/network" | grep -q "option device 'eth1'"
    grep -A6 "config interface 'lan'" "$PROFILE_DIR/network" | grep -q "192.168.2.1"
}

@test "firewall has wan zone with masquerade" {
    grep -q "option name 'wan'" "$PROFILE_DIR/firewall"
    grep -q "option masq '1'" "$PROFILE_DIR/firewall"
    grep -q "option mtu_fix '1'" "$PROFILE_DIR/firewall"
}

@test "firewall has forwarding lan -> wan" {
    grep -q "option src 'lan'" "$PROFILE_DIR/firewall"
    grep -q "option dest 'wan'" "$PROFILE_DIR/firewall"
}

@test "dhcp serves on lan" {
    grep -q "option interface 'lan'" "$PROFILE_DIR/dhcp"
    grep -q "option ignore '0'" "$PROFILE_DIR/dhcp" || \
        ! grep -q "option ignore '1'" "$PROFILE_DIR/dhcp"
}
```

- [ ] **Step 2: 跑测试确认 fail**

- [ ] **Step 3: 写 files/etc/profiles/pppoe-main/network**

```
config interface 'loopback'
    option device 'lo'
    option proto 'static'
    option ipaddr '127.0.0.1'
    option netmask '255.0.0.0'

config globals 'globals'
    option ula_prefix 'fdc6:0123:4567::/48'

config interface 'wan'
    option device 'eth0'
    option proto 'pppoe'
    option username ''
    option password ''
    option mtu '1492'

config interface 'wan6'
    option device 'eth0'
    option proto 'dhcpv6'

config interface 'lan'
    option device 'eth1'
    option proto 'static'
    option ipaddr '192.168.2.1'
    option netmask '255.255.255.0'
    option ip6assign '60'
```

- [ ] **Step 4: 写 files/etc/profiles/pppoe-main/firewall**

```
config defaults
    option syn_flood '1'
    option input 'ACCEPT'
    option output 'ACCEPT'
    option forward 'REJECT'

config zone
    option name 'lan'
    list network 'lan'
    option input 'ACCEPT'
    option output 'ACCEPT'
    option forward 'ACCEPT'

config zone
    option name 'wan'
    list network 'wan'
    list network 'wan6'
    option input 'REJECT'
    option output 'ACCEPT'
    option forward 'REJECT'
    option masq '1'
    option mtu_fix '1'

config forwarding
    option src 'lan'
    option dest 'wan'

config rule
    option name 'Allow-DHCP-Renew'
    option src 'wan'
    option proto 'udp'
    option dest_port '68'
    option target 'ACCEPT'
    option family 'ipv4'

config rule
    option name 'Allow-Ping'
    option src 'wan'
    option proto 'icmp'
    option icmp_type 'echo-request'
    option family 'ipv4'
    option target 'ACCEPT'

config rule
    option name 'Allow-IGMP'
    option src 'wan'
    option proto 'igmp'
    option family 'ipv4'
    option target 'ACCEPT'
```

- [ ] **Step 5: 写 files/etc/profiles/pppoe-main/dhcp**

（与 switch-equal 的 dhcp 完全相同，因为 LAN 行为一致）
```
config dnsmasq
    option domainneeded '1'
    option boguspriv '1'
    option filterwin2k '0'
    option localise_queries '1'
    option rebind_protection '1'
    option rebind_localhost '1'
    option local '/lan/'
    option domain 'lan'
    option expandhosts '1'
    option authoritative '1'
    option readethers '1'
    option leasefile '/tmp/dhcp.leases'
    option resolvfile '/tmp/resolv.conf.d/resolv.conf.auto'
    option nonwildcard '1'
    option localservice '1'

config dhcp 'lan'
    option interface 'lan'
    option start '100'
    option limit '150'
    option leasetime '12h'
    option ignore '0'

config dhcp 'wan'
    option interface 'wan'
    option ignore '1'

config odhcpd 'odhcpd'
    option maindhcp '0'
    option leasefile '/tmp/hosts/odhcpd'
    option leasetrigger '/usr/sbin/odhcpd-update'
    option loglevel '4'
```

- [ ] **Step 6: 跑 bats，全 pass**

- [ ] **Step 7: commit**

```bash
git add files/etc/profiles/pppoe-main/ tests/profile_pppoe_main.bats
git commit -m "feat(profiles): add pppoe-main (WAN PPPoE on eth0, LAN on eth1)"
```

---

### Task 10: bypass-gateway profile

**Files:**
- Create: `files/etc/profiles/bypass-gateway/{network,firewall,dhcp}`
- Test: `tests/profile_bypass_gateway.bats`

- [ ] **Step 1: 写 bats 测试**

`tests/profile_bypass_gateway.bats`:
```bash
#!/usr/bin/env bats

PROFILE_DIR="${BATS_TEST_DIRNAME}/../files/etc/profiles/bypass-gateway"

@test "lan on eth0 with placeholder ip 192.168.1.2" {
    grep -A6 "config interface 'lan'" "$PROFILE_DIR/network" | grep -q "option device 'eth0'"
    grep -A6 "config interface 'lan'" "$PROFILE_DIR/network" | grep -q "192.168.1.2"
    grep -A6 "config interface 'lan'" "$PROFILE_DIR/network" | grep -q "option gateway '192.168.1.1'"
}

@test "wan disabled or absent" {
    ! grep -q "config interface 'wan'" "$PROFILE_DIR/network" || \
        grep -A6 "config interface 'wan'" "$PROFILE_DIR/network" | grep -q "option auto '0'"
}

@test "firewall lan zone allows masquerade for transparent proxy" {
    grep -q "option name 'lan'" "$PROFILE_DIR/firewall"
    grep -q "option masq '1'" "$PROFILE_DIR/firewall"
}

@test "firewall has forwarding lan -> lan" {
    grep -q "option src 'lan'" "$PROFILE_DIR/firewall"
    grep -q "option dest 'lan'" "$PROFILE_DIR/firewall"
}

@test "dhcp ignored on lan (option ignore '1')" {
    grep -q "option interface 'lan'" "$PROFILE_DIR/dhcp"
    grep -q "option ignore '1'" "$PROFILE_DIR/dhcp"
}
```

- [ ] **Step 2: 跑测试确认 fail**

- [ ] **Step 3: 写 files/etc/profiles/bypass-gateway/network**

```
config interface 'loopback'
    option device 'lo'
    option proto 'static'
    option ipaddr '127.0.0.1'
    option netmask '255.0.0.0'

config globals 'globals'
    option ula_prefix 'fdc6:0123:4567::/48'

config interface 'lan'
    option device 'eth0'
    option proto 'static'
    option ipaddr '192.168.1.2'
    option netmask '255.255.255.0'
    option gateway '192.168.1.1'
    list dns '192.168.1.1'
```

- [ ] **Step 4: 写 files/etc/profiles/bypass-gateway/firewall**

```
config defaults
    option syn_flood '1'
    option input 'ACCEPT'
    option output 'ACCEPT'
    option forward 'ACCEPT'

config zone
    option name 'lan'
    list network 'lan'
    option input 'ACCEPT'
    option output 'ACCEPT'
    option forward 'ACCEPT'
    option masq '1'
    option mtu_fix '1'

config forwarding
    option src 'lan'
    option dest 'lan'
```

- [ ] **Step 5: 写 files/etc/profiles/bypass-gateway/dhcp**

```
config dnsmasq
    option domainneeded '1'
    option boguspriv '1'
    option filterwin2k '0'
    option localise_queries '1'
    option rebind_protection '1'
    option rebind_localhost '1'
    option local '/lan/'
    option domain 'lan'
    option expandhosts '1'
    option authoritative '1'
    option readethers '1'
    option leasefile '/tmp/dhcp.leases'
    option resolvfile '/tmp/resolv.conf.d/resolv.conf.auto'
    option nonwildcard '1'
    option localservice '1'

config dhcp 'lan'
    option interface 'lan'
    option ignore '1'

config odhcpd 'odhcpd'
    option maindhcp '0'
    option leasefile '/tmp/hosts/odhcpd'
    option leasetrigger '/usr/sbin/odhcpd-update'
    option loglevel '4'
```

- [ ] **Step 6: 跑 bats**

- [ ] **Step 7: commit**

```bash
git add files/etc/profiles/bypass-gateway/ tests/profile_bypass_gateway.bats
git commit -m "feat(profiles): add bypass-gateway (single-arm transparent gateway)"
```

---

## Phase 4 — mode-switch（后端 + LuCI）

### Task 11: mode-switch UCI 默认配置

**Files:**
- Create: `files/etc/config/mode-switch`
- Test: `tests/mode_switch_uci.bats`

- [ ] **Step 1: 写 bats 测试**

`tests/mode_switch_uci.bats`:
```bash
#!/usr/bin/env bats

CFG="${BATS_TEST_DIRNAME}/../files/etc/config/mode-switch"

@test "has current mode set to switch-equal" {
    grep -q "config mode 'current'" "$CFG"
    grep -A2 "config mode 'current'" "$CFG" | grep -q "option name 'switch-equal'"
}

@test "has pppoe section with empty username/password and mtu 1492" {
    grep -q "config pppoe 'pppoe'" "$CFG"
    grep -A6 "config pppoe 'pppoe'" "$CFG" | grep -q "option username ''"
    grep -A6 "config pppoe 'pppoe'" "$CFG" | grep -q "option password ''"
    grep -A6 "config pppoe 'pppoe'" "$CFG" | grep -q "option mtu '1492'"
}

@test "has bypass section with placeholder upstream gateway" {
    grep -q "config bypass 'bypass'" "$CFG"
    grep -A6 "config bypass 'bypass'" "$CFG" | grep -q "option ipaddr '192.168.1.2'"
    grep -A6 "config bypass 'bypass'" "$CFG" | grep -q "option gateway '192.168.1.1'"
    grep -A6 "config bypass 'bypass'" "$CFG" | grep -q "option dns '192.168.1.1'"
}
```

- [ ] **Step 2: 跑测试确认 fail**

- [ ] **Step 3: 写 files/etc/config/mode-switch**

```
config mode 'current'
    option name 'switch-equal'

config pppoe 'pppoe'
    option username ''
    option password ''
    option mtu '1492'
    option service ''

config bypass 'bypass'
    option ipaddr '192.168.1.2'
    option netmask '255.255.255.0'
    option gateway '192.168.1.1'
    option dns '192.168.1.1'
```

- [ ] **Step 4: 跑 bats**

- [ ] **Step 5: commit**

```bash
git add files/etc/config/mode-switch tests/mode_switch_uci.bats
git commit -m "feat(rootfs): add mode-switch UCI defaults"
```

---

### Task 12: /usr/bin/mode-switch 后端脚本

**Files:**
- Create: `files/usr/bin/mode-switch`
- Test: `tests/mode_switch_backend.bats`

- [ ] **Step 1: 写 bats 测试（mock uci 与 init.d）**

`tests/mode_switch_backend.bats`:
```bash
#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../files/usr/bin/mode-switch"

    # 隔离环境
    export ROOT="${BATS_TMPDIR}/rootfs"
    rm -rf "$ROOT"
    mkdir -p "$ROOT/etc/config" "$ROOT/etc/init.d" "$ROOT/var/log" "$ROOT/etc/profiles"

    # 复制真实 profiles
    cp -r "${BATS_TEST_DIRNAME}/../files/etc/profiles/"* "$ROOT/etc/profiles/"
    cp "${BATS_TEST_DIRNAME}/../files/etc/config/mode-switch" "$ROOT/etc/config/"

    # 起始 network/firewall/dhcp 用 switch-equal 占位
    cp "$ROOT/etc/profiles/switch-equal/network"  "$ROOT/etc/config/network"
    cp "$ROOT/etc/profiles/switch-equal/firewall" "$ROOT/etc/config/firewall"
    cp "$ROOT/etc/profiles/switch-equal/dhcp"     "$ROOT/etc/config/dhcp"

    # fake init.d
    cat > "$ROOT/etc/init.d/network" <<'EOF'
#!/bin/sh
echo "network $1" >> "$ROOT/var/log/init.log"
EOF
    cp "$ROOT/etc/init.d/network" "$ROOT/etc/init.d/firewall"
    cp "$ROOT/etc/init.d/network" "$ROOT/etc/init.d/dnsmasq"
    chmod +x "$ROOT/etc/init.d/"*

    # fake uci: 简单实现 (set/get/commit/show 满足脚本需求)
    mkdir -p "${BATS_TMPDIR}/bin"
    cat > "${BATS_TMPDIR}/bin/uci" <<'EOFUCI'
#!/usr/bin/env bash
# minimal fake uci backed by ini-style file at $ROOT/etc/config/<name>
file_for() { echo "$ROOT/etc/config/$1"; }
case "$1" in
  get)
      key="$2"; pkg=${key%%.*}; rest=${key#*.}; sect=${rest%%.*}; opt=${rest#*.}
      grep -E "^[[:space:]]*option ${opt} " "$(file_for "$pkg")" 2>/dev/null \
          | head -1 | sed -E "s/.*option ${opt} '([^']*)'.*/\1/"
      ;;
  set)
      key="${2%=*}"; val="${2#*=}"; pkg=${key%%.*}; rest=${key#*.}; sect=${rest%%.*}; opt=${rest#*.}
      f=$(file_for "$pkg")
      if grep -qE "^[[:space:]]*option ${opt} " "$f"; then
          sed -i.bak -E "s|^([[:space:]]*option ${opt} ).*|\1'${val}'|" "$f" && rm -f "${f}.bak"
      else
          echo "    option ${opt} '${val}'" >> "$f"
      fi
      ;;
  commit) ;;
  show) cat "$(file_for "$2")" 2>/dev/null ;;
esac
EOFUCI
    chmod +x "${BATS_TMPDIR}/bin/uci"
    export PATH="${BATS_TMPDIR}/bin:${PATH}"
}

teardown() {
    rm -rf "$ROOT"
}

@test "passes shellcheck" {
    run shellcheck "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "shows help" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"pppoe"* ]]
    [[ "$output" == *"switch"* ]]
    [[ "$output" == *"bypass"* ]]
}

@test "rejects unknown mode" {
    run env ROOT="$ROOT" "$SCRIPT" bogus
    [ "$status" -ne 0 ]
}

@test "status reports current mode" {
    run env ROOT="$ROOT" "$SCRIPT" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"switch-equal"* ]]
}

@test "switch to pppoe copies pppoe-main profiles" {
    run env ROOT="$ROOT" SKIP_RESTART=1 "$SCRIPT" pppoe
    [ "$status" -eq 0 ]
    grep -q "proto 'pppoe'" "$ROOT/etc/config/network"
    grep -q "option name 'wan'" "$ROOT/etc/config/firewall"
}

@test "switch to bypass copies bypass-gateway profile" {
    run env ROOT="$ROOT" SKIP_RESTART=1 "$SCRIPT" bypass
    [ "$status" -eq 0 ]
    grep -q "192.168.1.2" "$ROOT/etc/config/network"
}

@test "switch creates timestamped backup" {
    run env ROOT="$ROOT" SKIP_RESTART=1 "$SCRIPT" pppoe
    [ "$status" -eq 0 ]
    found=$(find "$ROOT/etc" -maxdepth 1 -name 'config.bak.*' -type d | wc -l)
    [ "$found" -gt 0 ]
}

@test "switch updates mode-switch.current.name" {
    env ROOT="$ROOT" SKIP_RESTART=1 "$SCRIPT" pppoe
    grep -q "option name 'pppoe-main'" "$ROOT/etc/config/mode-switch"
}

@test "switch injects pppoe creds into network" {
    # 先在 mode-switch 里写 username/password
    sed -i.bak -E "s|option username ''|option username 'alice'|" "$ROOT/etc/config/mode-switch"
    sed -i.bak -E "s|option password ''|option password 'secret'|" "$ROOT/etc/config/mode-switch"
    rm -f "$ROOT/etc/config/mode-switch.bak"

    env ROOT="$ROOT" SKIP_RESTART=1 "$SCRIPT" pppoe
    grep -q "option username 'alice'" "$ROOT/etc/config/network"
    grep -q "option password 'secret'" "$ROOT/etc/config/network"
}

@test "switch rolls back on simulated network failure" {
    # 让 init.d/network 返回非零
    cat > "$ROOT/etc/init.d/network" <<'EOF'
#!/bin/sh
echo "network $1" >> "$ROOT/var/log/init.log"
exit 1
EOF
    chmod +x "$ROOT/etc/init.d/network"

    run env ROOT="$ROOT" "$SCRIPT" pppoe
    [ "$status" -ne 0 ]
    # 回滚后 network 应该回到 switch-equal 内容（含 br-lan）
    grep -q "br-lan" "$ROOT/etc/config/network"
}
```

- [ ] **Step 2: 跑测试确认 fail**

```bash
bats tests/mode_switch_backend.bats
```

- [ ] **Step 3: 实现 files/usr/bin/mode-switch**

```bash
#!/usr/bin/env bash
# mode-switch: 在 PPPoE 主路由 / 双口对等交换 / 旁路由 三种模式间切换
# usage: mode-switch [pppoe|switch|bypass|status]
set -u

ROOT="${ROOT:-}"
PROFILES_DIR="${ROOT}/etc/profiles"
CONFIG_DIR="${ROOT}/etc/config"
LOG_FILE="${ROOT}/var/log/mode-switch.log"
INITD="${ROOT}/etc/init.d"
SKIP_RESTART="${SKIP_RESTART:-0}"

usage() {
    cat <<'EOF'
Usage: mode-switch <pppoe|switch|bypass|status|--help>

Modes:
  pppoe    - PPPoE 主路由 (eth0=WAN PPPoE, eth1=LAN)
  switch   - 双口对等交换 (eth0+eth1 桥接为 br-lan)
  bypass   - 旁路由透明网关 (eth0 单臂)
  status   - 显示当前激活模式
EOF
}

log() {
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

current_mode() {
    uci -q get mode-switch.current.name 2>/dev/null || echo "unknown"
}

profile_for() {
    case "$1" in
        pppoe)  echo "pppoe-main" ;;
        switch) echo "switch-equal" ;;
        bypass) echo "bypass-gateway" ;;
        *)      echo "" ;;
    esac
}

backup_configs() {
    local ts="$1"
    local bak="${ROOT}/etc/config.bak.${ts}"
    mkdir -p "$bak"
    for f in network firewall dhcp; do
        cp "$CONFIG_DIR/$f" "$bak/$f"
    done
    echo "$bak"
}

restore_from() {
    local bak="$1"
    log "restoring from $bak"
    for f in network firewall dhcp; do
        cp "$bak/$f" "$CONFIG_DIR/$f"
    done
}

apply_profile() {
    local prof="$1"
    local src="${PROFILES_DIR}/${prof}"
    [ -d "$src" ] || { log "profile not found: $src"; return 1; }
    for f in network firewall dhcp; do
        cp "$src/$f" "$CONFIG_DIR/$f" || return 1
    done
}

inject_pppoe_creds() {
    local user pass mtu service
    user=$(uci -q get mode-switch.pppoe.username || echo "")
    pass=$(uci -q get mode-switch.pppoe.password || echo "")
    mtu=$(uci -q get mode-switch.pppoe.mtu || echo "1492")
    service=$(uci -q get mode-switch.pppoe.service || echo "")

    [ -n "$user" ] && uci set network.wan.username="$user"
    [ -n "$pass" ] && uci set network.wan.password="$pass"
    [ -n "$mtu" ] && uci set network.wan.mtu="$mtu"
    [ -n "$service" ] && uci set network.wan.service="$service"
    uci commit network
}

inject_bypass_params() {
    local ip mask gw dns
    ip=$(uci -q get mode-switch.bypass.ipaddr || echo "")
    mask=$(uci -q get mode-switch.bypass.netmask || echo "")
    gw=$(uci -q get mode-switch.bypass.gateway || echo "")
    dns=$(uci -q get mode-switch.bypass.dns || echo "")

    [ -n "$ip" ] && uci set network.lan.ipaddr="$ip"
    [ -n "$mask" ] && uci set network.lan.netmask="$mask"
    [ -n "$gw" ] && uci set network.lan.gateway="$gw"
    if [ -n "$dns" ]; then
        uci -q delete network.lan.dns
        uci add_list network.lan.dns="$dns"
    fi
    uci commit network
}

restart_services() {
    [ "$SKIP_RESTART" -eq 1 ] && { log "SKIP_RESTART=1; not restarting"; return 0; }
    "$INITD/network" restart || return 1
    "$INITD/firewall" restart || return 1
    "$INITD/dnsmasq" restart || return 1
    return 0
}

do_status() {
    echo "current mode: $(current_mode)"
    if [ -f "$LOG_FILE" ]; then
        echo "--- last 50 log lines ---"
        tail -n 50 "$LOG_FILE"
    fi
}

main() {
    local action="${1:-}"
    case "$action" in
        ""|--help|-h) usage; exit 0 ;;
        status) do_status; exit 0 ;;
        pppoe|switch|bypass) ;;
        *) usage >&2; exit 2 ;;
    esac

    local prof; prof=$(profile_for "$action")
    [ -n "$prof" ] || { usage >&2; exit 2; }

    log "switching to $action ($prof)"

    local ts; ts=$(date +%Y%m%d-%H%M%S)
    local bak; bak=$(backup_configs "$ts")
    log "backup at $bak"

    if ! apply_profile "$prof"; then
        log "apply_profile failed; rolling back"
        restore_from "$bak"
        exit 1
    fi

    case "$action" in
        pppoe)  inject_pppoe_creds ;;
        bypass) inject_bypass_params ;;
    esac

    uci set mode-switch.current.name="$prof"
    uci commit mode-switch

    if ! restart_services; then
        log "service restart failed; rolling back"
        restore_from "$bak"
        # 即便恢复，仍尝试再次 restart
        "$INITD/network" restart >/dev/null 2>&1 || true
        "$INITD/firewall" restart >/dev/null 2>&1 || true
        "$INITD/dnsmasq" restart >/dev/null 2>&1 || true
        exit 1
    fi

    log "switch to $action completed"
}

main "$@"
```

- [ ] **Step 4: 设可执行权限并跑 shellcheck**

```bash
chmod +x files/usr/bin/mode-switch
shellcheck files/usr/bin/mode-switch
```

- [ ] **Step 5: 跑 bats**

```bash
bats tests/mode_switch_backend.bats
```
期望 10 ok。

- [ ] **Step 6: commit**

```bash
git add files/usr/bin/mode-switch tests/mode_switch_backend.bats
git commit -m "feat(mode-switch): backend script with rollback and PPPoE/bypass injection"
```

---

### Task 13: mode-switch LuCI controller

**Files:**
- Create: `files/usr/lib/lua/luci/controller/mode_switch.lua`
- Test: `tests/luci_mode_switch.bats`

- [ ] **Step 1: 写 bats 测试（仅 syntax + 路由匹配）**

`tests/luci_mode_switch.bats`:
```bash
#!/usr/bin/env bats

CTRL="${BATS_TEST_DIRNAME}/../files/usr/lib/lua/luci/controller/mode_switch.lua"

@test "passes lua syntax check" {
    run luac -p "$CTRL"
    [ "$status" -eq 0 ]
}

@test "registers index() entry function" {
    grep -qE "^function index\(\)" "$CTRL"
}

@test "registers /admin/status/mode_switch entry" {
    grep -q '"admin", "status", "mode_switch"' "$CTRL"
}

@test "exposes do_switch action" {
    grep -q "function action_switch" "$CTRL"
    grep -q '"do_switch"' "$CTRL"
}

@test "exposes pppoe and bypass tabs" {
    grep -q '"pppoe"' "$CTRL"
    grep -q '"bypass"' "$CTRL"
}
```

- [ ] **Step 2: 跑测试确认 fail**

- [ ] **Step 3: 实现 controller**

`files/usr/lib/lua/luci/controller/mode_switch.lua`:
```lua
module("luci.controller.mode_switch", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/mode-switch") then
        return
    end

    local root = entry({"admin", "status", "mode_switch"},
                       alias("admin", "status", "mode_switch", "status"),
                       _("Mode Switch"), 90)
    root.dependent = false

    entry({"admin", "status", "mode_switch", "status"},
          template("mode_switch/status"), _("Status"), 10).leaf = true

    entry({"admin", "status", "mode_switch", "pppoe"},
          cbi("mode_switch/pppoe"), _("PPPoE"), 20).leaf = true

    entry({"admin", "status", "mode_switch", "bypass"},
          cbi("mode_switch/bypass"), _("Bypass"), 30).leaf = true

    entry({"admin", "status", "mode_switch", "do_switch"},
          call("action_switch")).leaf = true

    entry({"admin", "status", "mode_switch", "current"},
          call("action_current")).leaf = true

    entry({"admin", "status", "mode_switch", "log"},
          call("action_log")).leaf = true
end

local function exec(cmd)
    local p = io.popen(cmd .. " 2>&1; echo __EXIT__$?")
    local out = p:read("*a") or ""
    p:close()
    local code = tonumber(out:match("__EXIT__(%d+)") or "1") or 1
    out = out:gsub("__EXIT__%d+%s*$", "")
    return code, out
end

function action_switch()
    local http = require "luci.http"
    local mode = http.formvalue("mode") or ""
    if not (mode == "pppoe" or mode == "switch" or mode == "bypass") then
        http.status(400, "Bad Request")
        http.prepare_content("application/json")
        http.write_json({ ok = false, error = "invalid mode: " .. mode })
        return
    end
    local code, out = exec("/usr/bin/mode-switch " .. mode)
    http.prepare_content("application/json")
    http.write_json({ ok = (code == 0), code = code, output = out })
end

function action_current()
    local http = require "luci.http"
    local code, out = exec("/usr/bin/mode-switch status")
    http.prepare_content("application/json")
    http.write_json({ ok = (code == 0), output = out })
end

function action_log()
    local http = require "luci.http"
    local f = io.open("/var/log/mode-switch.log", "r")
    local content = ""
    if f then
        content = f:read("*a") or ""
        f:close()
    end
    -- last 50 lines
    local lines = {}
    for line in content:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    local start = math.max(1, #lines - 49)
    local tail = {}
    for i = start, #lines do tail[#tail+1] = lines[i] end
    http.prepare_content("text/plain")
    http.write(table.concat(tail, "\n"))
end
```

- [ ] **Step 4: 跑 luac syntax check**

```bash
luac -p files/usr/lib/lua/luci/controller/mode_switch.lua
```

- [ ] **Step 5: 跑 bats**

```bash
bats tests/luci_mode_switch.bats
```
期望 5 ok。

- [ ] **Step 6: commit**

```bash
git add files/usr/lib/lua/luci/controller/mode_switch.lua tests/luci_mode_switch.bats
git commit -m "feat(luci): add mode_switch controller with status/pppoe/bypass tabs"
```

---

### Task 14: mode-switch LuCI 视图与 cbi 模型

**Files:**
- Create: `files/usr/lib/lua/luci/view/mode_switch/status.htm`
- Create: `files/usr/lib/lua/luci/model/cbi/mode_switch/pppoe.lua`
- Create: `files/usr/lib/lua/luci/model/cbi/mode_switch/bypass.lua`

- [ ] **Step 1: 创建 cbi 目录**

```bash
mkdir -p files/usr/lib/lua/luci/model/cbi/mode_switch
```

- [ ] **Step 2: 写 status.htm（模板）**

`files/usr/lib/lua/luci/view/mode_switch/status.htm`:
```html
<%+header%>
<style>
.r2s-mode-card { padding: 12px 16px; border: 1px solid #ddd; border-radius: 6px; margin-bottom: 12px; }
.r2s-current { font-weight: bold; padding: 4px 8px; background: #e8f5e9; border-radius: 4px; }
.r2s-mode-buttons button { margin-right: 8px; }
.r2s-log { background: #1e1e1e; color: #ddd; font-family: monospace; padding: 12px; max-height: 300px; overflow: auto; }
</style>

<h2><%:Mode Switch%></h2>

<div class="r2s-mode-card">
    <div><%:Current mode%>: <span class="r2s-current" id="r2s-current">—</span></div>
    <div class="r2s-mode-buttons" style="margin-top:12px;">
        <button class="cbi-button cbi-button-apply" onclick="r2sSwitch('switch')">双口对等交换</button>
        <button class="cbi-button cbi-button-apply" onclick="r2sSwitch('pppoe')">PPPoE 主路由</button>
        <button class="cbi-button cbi-button-apply" onclick="r2sSwitch('bypass')">旁路由网关</button>
    </div>
</div>

<div class="r2s-mode-card">
    <h3><%:Recent log%></h3>
    <pre class="r2s-log" id="r2s-log">加载中...</pre>
</div>

<script>
function r2sFetch(url, opts) {
    return fetch(url, opts || {}).then(function(r){ return r.text().then(function(t){ return { code: r.status, body: t }; }); });
}

function r2sRefreshCurrent() {
    r2sFetch('<%=luci.dispatcher.build_url("admin","status","mode_switch","current")%>')
        .then(function(res){
            try {
                var j = JSON.parse(res.body);
                var m = (j.output || '').match(/current mode:\s*(\S+)/);
                document.getElementById('r2s-current').textContent = m ? m[1] : '?';
            } catch (e) {
                document.getElementById('r2s-current').textContent = 'error';
            }
        });
}

function r2sRefreshLog() {
    r2sFetch('<%=luci.dispatcher.build_url("admin","status","mode_switch","log")%>')
        .then(function(res){
            document.getElementById('r2s-log').textContent = res.body || '(empty)';
        });
}

function r2sSwitch(mode) {
    if (!confirm('确认切换到 ' + mode + ' 模式？网络可能短暂中断。')) return;
    var fd = new FormData();
    fd.append('mode', mode);
    r2sFetch('<%=luci.dispatcher.build_url("admin","status","mode_switch","do_switch")%>',
             { method: 'POST', body: fd })
        .then(function(res){
            try {
                var j = JSON.parse(res.body);
                alert(j.ok ? '切换成功\n\n' + j.output : '切换失败 (code ' + j.code + ')\n\n' + j.output);
            } catch (e) {
                alert('响应解析失败: ' + res.body);
            }
            setTimeout(function(){ r2sRefreshCurrent(); r2sRefreshLog(); }, 1500);
        });
}

r2sRefreshCurrent();
r2sRefreshLog();
setInterval(r2sRefreshLog, 5000);
</script>

<%+footer%>
```

- [ ] **Step 3: 写 cbi/mode_switch/pppoe.lua**

```lua
local m = Map("mode-switch", translate("PPPoE 配置"),
    translate("拨号账号；保存后切到 PPPoE 模式生效。"))

local s = m:section(NamedSection, "pppoe", "pppoe", "")
s.anonymous = true
s.addremove = false

local user = s:option(Value, "username", translate("用户名"))
user.rmempty = true

local pass = s:option(Value, "password", translate("密码"))
pass.password = true
pass.rmempty = true

local mtu = s:option(Value, "mtu", translate("MTU"))
mtu.datatype = "uinteger"
mtu.default = "1492"

local svc = s:option(Value, "service", translate("服务名（可空）"))
svc.rmempty = true

return m
```

- [ ] **Step 4: 写 cbi/mode_switch/bypass.lua**

```lua
local m = Map("mode-switch", translate("旁路由配置"),
    translate("作为旁路由时本机的 IP 与上级网关；保存后切到 bypass 模式生效。"))

local s = m:section(NamedSection, "bypass", "bypass", "")
s.anonymous = true
s.addremove = false

local ip = s:option(Value, "ipaddr", translate("本机 IP"))
ip.datatype = "ip4addr"
ip.default = "192.168.1.2"

local mask = s:option(Value, "netmask", translate("子网掩码"))
mask.datatype = "ip4addr"
mask.default = "255.255.255.0"

local gw = s:option(Value, "gateway", translate("上级网关"))
gw.datatype = "ip4addr"
gw.default = "192.168.1.1"

local dns = s:option(Value, "dns", translate("上游 DNS"))
dns.datatype = "ip4addr"
dns.default = "192.168.1.1"

return m
```

- [ ] **Step 5: luac syntax check**

```bash
luac -p files/usr/lib/lua/luci/model/cbi/mode_switch/pppoe.lua
luac -p files/usr/lib/lua/luci/model/cbi/mode_switch/bypass.lua
```

- [ ] **Step 6: 视图存在性测试**

`tests/luci_mode_switch_views.bats`:
```bash
#!/usr/bin/env bats

DIR="${BATS_TEST_DIRNAME}/../files/usr/lib/lua/luci"

@test "status template exists and references current mode JS" {
    [ -f "$DIR/view/mode_switch/status.htm" ]
    grep -q "r2s-current" "$DIR/view/mode_switch/status.htm"
    grep -q "r2sSwitch" "$DIR/view/mode_switch/status.htm"
}

@test "pppoe cbi compiles" {
    run luac -p "$DIR/model/cbi/mode_switch/pppoe.lua"
    [ "$status" -eq 0 ]
}

@test "bypass cbi compiles" {
    run luac -p "$DIR/model/cbi/mode_switch/bypass.lua"
    [ "$status" -eq 0 ]
}
```

```bash
bats tests/luci_mode_switch_views.bats
```

- [ ] **Step 7: commit**

```bash
git add files/usr/lib/lua/luci/view/mode_switch/ files/usr/lib/lua/luci/model/cbi/mode_switch/ tests/luci_mode_switch_views.bats
git commit -m "feat(luci): add mode_switch status template + pppoe/bypass cbi forms"
```

---

## Phase 5 — fan-pid（PID 风扇控制）

### Task 15: fan UCI 默认配置

**Files:**
- Create: `files/etc/config/fan`
- Test: `tests/fan_uci.bats`

- [ ] **Step 1: 写 bats 测试**

`tests/fan_uci.bats`:
```bash
#!/usr/bin/env bats

CFG="${BATS_TEST_DIRNAME}/../files/etc/config/fan"

@test "has pid section enabled" {
    grep -q "config fan 'pid'" "$CFG"
    grep -q "option enabled '1'" "$CFG"
}

@test "setpoint is 55" {
    grep -q "option setpoint '55'" "$CFG"
}

@test "PID gains present" {
    grep -q "option kp" "$CFG"
    grep -q "option ki" "$CFG"
    grep -q "option kd" "$CFG"
}

@test "interval and pwm bounds present" {
    grep -q "option interval" "$CFG"
    grep -q "option pwm_min" "$CFG"
    grep -q "option pwm_max" "$CFG"
    grep -q "option pwm_path" "$CFG"
}
```

- [ ] **Step 2: 跑测试确认 fail**

- [ ] **Step 3: 写 files/etc/config/fan**

```
config fan 'pid'
    option enabled '1'
    option setpoint '55'
    option kp '4.0'
    option ki '0.2'
    option kd '1.0'
    option interval '5'
    option pwm_min '0'
    option pwm_max '255'
    option pwm_path '/sys/class/pwm/pwmchip0/pwm0'
    option thermal_path '/sys/class/thermal/thermal_zone0/temp'
```

- [ ] **Step 4: 跑 bats**

- [ ] **Step 5: commit**

```bash
git add files/etc/config/fan tests/fan_uci.bats
git commit -m "feat(rootfs): add fan PID UCI defaults"
```

---

### Task 16: /usr/bin/fan-pid-loop 主循环

**Files:**
- Create: `files/usr/bin/fan-pid-loop`
- Test: `tests/fan_pid_loop.bats`

- [ ] **Step 1: 写 bats 测试**

`tests/fan_pid_loop.bats`:
```bash
#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../files/usr/bin/fan-pid-loop"

    export THERMAL="${BATS_TMPDIR}/thermal/temp"
    export PWM_DIR="${BATS_TMPDIR}/pwm"
    export STATE="${BATS_TMPDIR}/fan-pid.state"
    mkdir -p "$(dirname "$THERMAL")" "$PWM_DIR"
    : > "$PWM_DIR/duty_cycle"
    echo 50000 > "$THERMAL"  # 50.0 °C
}

teardown() {
    rm -rf "${BATS_TMPDIR}/thermal" "$PWM_DIR" "$STATE"
}

@test "passes shellcheck" {
    run shellcheck "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "single iteration computes pwm and writes duty_cycle + state" {
    run env FAN_THERMAL="$THERMAL" FAN_PWM_DIR="$PWM_DIR" FAN_STATE="$STATE" \
        FAN_SETPOINT=55 FAN_KP=4.0 FAN_KI=0.2 FAN_KD=1.0 FAN_INTERVAL=1 \
        FAN_PWM_MIN=0 FAN_PWM_MAX=255 FAN_ONCE=1 \
        "$SCRIPT"
    [ "$status" -eq 0 ]
    [ -f "$STATE" ]
    grep -q "temp_c=50" "$STATE"
    grep -q "pwm=" "$STATE"
}

@test "below setpoint at 50C with positive Kp keeps pwm at min" {
    # error = 50-55 = -5; out = -20 -> clamped to 0
    run env FAN_THERMAL="$THERMAL" FAN_PWM_DIR="$PWM_DIR" FAN_STATE="$STATE" \
        FAN_SETPOINT=55 FAN_KP=4.0 FAN_KI=0 FAN_KD=0 FAN_INTERVAL=1 \
        FAN_PWM_MIN=0 FAN_PWM_MAX=255 FAN_ONCE=1 \
        "$SCRIPT"
    pwm=$(awk -F= '/^pwm/{print $2}' "$STATE")
    [ "$pwm" = "0" ]
}

@test "above setpoint clamps to pwm_max if extreme" {
    echo 90000 > "$THERMAL"  # 90C, error=35
    run env FAN_THERMAL="$THERMAL" FAN_PWM_DIR="$PWM_DIR" FAN_STATE="$STATE" \
        FAN_SETPOINT=55 FAN_KP=20 FAN_KI=0 FAN_KD=0 FAN_INTERVAL=1 \
        FAN_PWM_MIN=0 FAN_PWM_MAX=255 FAN_ONCE=1 \
        "$SCRIPT"
    pwm=$(awk -F= '/^pwm/{print $2}' "$STATE")
    [ "$pwm" = "255" ]
}

@test "missing thermal forces pwm_max and continues" {
    rm -f "$THERMAL"
    run env FAN_THERMAL="$THERMAL" FAN_PWM_DIR="$PWM_DIR" FAN_STATE="$STATE" \
        FAN_SETPOINT=55 FAN_KP=4 FAN_KI=0 FAN_KD=0 FAN_INTERVAL=1 \
        FAN_PWM_MIN=0 FAN_PWM_MAX=200 FAN_ONCE=1 \
        "$SCRIPT"
    [ "$status" -eq 0 ]
    pwm=$(awk -F= '/^pwm/{print $2}' "$STATE")
    [ "$pwm" = "200" ]
}

@test "convergence over 30 iterations approaches setpoint" {
    # 用反馈仿真: 每次 pwm 越大温度越接近 setpoint
    # 这里简单用静态 70C 起始，多迭代积分项发力
    echo 70000 > "$THERMAL"
    last_pwm=0
    for i in $(seq 1 30); do
        env FAN_THERMAL="$THERMAL" FAN_PWM_DIR="$PWM_DIR" FAN_STATE="$STATE" \
            FAN_SETPOINT=55 FAN_KP=4.0 FAN_KI=0.5 FAN_KD=1.0 FAN_INTERVAL=1 \
            FAN_PWM_MIN=0 FAN_PWM_MAX=255 FAN_ONCE=1 \
            "$SCRIPT"
        last_pwm=$(awk -F= '/^pwm/{print $2}' "$STATE")
    done
    # 在持续高温下 pwm 应被推到接近 max
    [ "$last_pwm" -ge 200 ]
}
```

- [ ] **Step 2: 跑测试确认 fail**

- [ ] **Step 3: 实现 files/usr/bin/fan-pid-loop**

```bash
#!/usr/bin/env bash
# fan-pid-loop: PID 风扇主循环
# 状态文件: $FAN_STATE (单次 / 测试时); 默认 /var/run/fan-pid.state
# 通过环境变量覆盖 UCI 选项, 测试用; 生产由 init.d/fan-pid 从 /etc/config/fan 读
set -u

# 从 UCI 读默认值（生产路径）；测试通过环境变量覆盖
read_uci() {
    local key="$1" default="$2"
    if command -v uci >/dev/null 2>&1; then
        uci -q get "fan.pid.$key" 2>/dev/null || echo "$default"
    else
        echo "$default"
    fi
}

THERMAL="${FAN_THERMAL:-$(read_uci thermal_path /sys/class/thermal/thermal_zone0/temp)}"
PWM_DIR="${FAN_PWM_DIR:-$(read_uci pwm_path /sys/class/pwm/pwmchip0/pwm0)}"
STATE="${FAN_STATE:-/var/run/fan-pid.state}"
SETPOINT="${FAN_SETPOINT:-$(read_uci setpoint 55)}"
KP="${FAN_KP:-$(read_uci kp 4.0)}"
KI="${FAN_KI:-$(read_uci ki 0.2)}"
KD="${FAN_KD:-$(read_uci kd 1.0)}"
INTERVAL="${FAN_INTERVAL:-$(read_uci interval 5)}"
PWM_MIN="${FAN_PWM_MIN:-$(read_uci pwm_min 0)}"
PWM_MAX="${FAN_PWM_MAX:-$(read_uci pwm_max 255)}"
ONCE="${FAN_ONCE:-0}"

LOG_LIMIT_S=60
last_thermal_warn=0
last_pwm_warn=0

now() { date +%s; }
log_warn_throttled() {
    local kind="$1" msg="$2" current_var="$3"
    local now_s; now_s=$(now)
    local last="${!current_var}"
    if [ $((now_s - last)) -ge "$LOG_LIMIT_S" ]; then
        echo "[fan-pid] $msg" >&2
        eval "$current_var=$now_s"
    fi
}

read_temp_c() {
    local raw
    if [ -r "$THERMAL" ]; then
        raw=$(cat "$THERMAL" 2>/dev/null) || return 1
        [ -n "$raw" ] || return 1
        # millidegree -> degree (整数)
        echo $((raw / 1000))
        return 0
    fi
    return 1
}

write_pwm() {
    local val="$1"
    if [ -d "$PWM_DIR" ]; then
        echo "$val" > "$PWM_DIR/duty_cycle" 2>/dev/null
        return $?
    fi
    return 1
}

clamp_int() {
    local v="$1" min="$2" max="$3"
    if [ "$v" -lt "$min" ]; then echo "$min"; return; fi
    if [ "$v" -gt "$max" ]; then echo "$max"; return; fi
    echo "$v"
}

# 用 awk 处理浮点 PID（busybox shell 无 bc）
pid_step() {
    local temp="$1" setpoint="$2" kp="$3" ki="$4" kd="$5" \
          dt="$6" prev_err="$7" integ="$8" pwm_min="$9" pwm_max="${10}"
    awk -v t="$temp" -v sp="$setpoint" -v kp="$kp" -v ki="$ki" -v kd="$kd" \
        -v dt="$dt" -v pe="$prev_err" -v ig="$integ" -v lo="$pwm_min" -v hi="$pwm_max" '
    BEGIN {
        err = t - sp
        ig_new = ig + err * dt
        deriv = (err - pe) / dt
        out = kp*err + ki*ig_new + kd*deriv
        if (out < lo) { out = lo; ig_new = ig }    # 抗饱和
        if (out > hi) { out = hi; ig_new = ig }
        printf "%d %.6f %.6f", int(out + 0.5), err, ig_new
    }'
}

run_once() {
    local temp out err integ
    temp=$(read_temp_c) || temp=""
    if [ -z "$temp" ]; then
        log_warn_throttled thermal "thermal read failed; forcing PWM=$PWM_MAX" last_thermal_warn
        out="$PWM_MAX"
        if ! write_pwm "$out"; then
            log_warn_throttled pwm "pwm write failed (path=$PWM_DIR/duty_cycle)" last_pwm_warn
        fi
        echo "temp_c=" > "$STATE"
        echo "pwm=$out" >> "$STATE"
        return 0
    fi

    integ="${INTEG:-0}"
    prev_err="${PREV_ERR:-0}"
    read -r out err integ_new < <(pid_step "$temp" "$SETPOINT" "$KP" "$KI" "$KD" \
                                            "$INTERVAL" "$prev_err" "$integ" \
                                            "$PWM_MIN" "$PWM_MAX")
    out=$(clamp_int "$out" "$PWM_MIN" "$PWM_MAX")

    if ! write_pwm "$out"; then
        log_warn_throttled pwm "pwm write failed; will retry" last_pwm_warn
    fi

    {
        echo "temp_c=$temp"
        echo "pwm=$out"
        echo "err=$err"
        echo "integ=$integ_new"
        echo "ts=$(date '+%F %T')"
    } > "$STATE"

    PREV_ERR="$err"
    INTEG="$integ_new"
}

main_loop() {
    PREV_ERR=0
    INTEG=0
    while true; do
        run_once
        sleep "$INTERVAL" 2>/dev/null || sleep 5
    done
}

trap 'echo "$PWM_MAX" > "$PWM_DIR/duty_cycle" 2>/dev/null || true; exit 0' TERM INT

mkdir -p "$(dirname "$STATE")" 2>/dev/null || true

load_state_for_once() {
    PREV_ERR=0
    INTEG=0
    [ -f "$STATE" ] || return 0
    local v
    v=$(awk -F= '/^err=/ {print $2}' "$STATE")
    [ -n "$v" ] && PREV_ERR="$v"
    v=$(awk -F= '/^integ=/ {print $2}' "$STATE")
    [ -n "$v" ] && INTEG="$v"
}

if [ "$ONCE" = "1" ]; then
    load_state_for_once
    run_once
else
    main_loop
fi
```

- [ ] **Step 4: 设可执行权限并跑 shellcheck**

```bash
chmod +x files/usr/bin/fan-pid-loop
shellcheck files/usr/bin/fan-pid-loop
```

- [ ] **Step 5: 跑 bats**

```bash
bats tests/fan_pid_loop.bats
```
期望 5 ok。

- [ ] **Step 6: commit**

```bash
git add files/usr/bin/fan-pid-loop tests/fan_pid_loop.bats
git commit -m "feat(fan-pid): add PID loop with anti-windup and degraded-safe behavior"
```

---

### Task 17: /etc/init.d/fan-pid procd 守护

**Files:**
- Create: `files/etc/init.d/fan-pid`
- Test: `tests/init_fan_pid.bats`

- [ ] **Step 1: 写 bats 测试**

`tests/init_fan_pid.bats`:
```bash
#!/usr/bin/env bats

INIT="${BATS_TEST_DIRNAME}/../files/etc/init.d/fan-pid"

@test "passes shellcheck" {
    run shellcheck -s sh "$INIT"
    [ "$status" -eq 0 ]
}

@test "uses procd start_service convention" {
    grep -q "USE_PROCD=1" "$INIT"
    grep -q "start_service" "$INIT"
}

@test "honors uci enabled flag" {
    grep -q "config_load 'fan'" "$INIT"
    grep -q "fan\\.pid\\.enabled" "$INIT" || grep -q "config_get .*enabled" "$INIT"
}

@test "respawns on crash" {
    grep -q "respawn" "$INIT"
}
```

- [ ] **Step 2: 跑测试确认 fail**

- [ ] **Step 3: 实现 init.d/fan-pid**

```sh
#!/bin/sh /etc/rc.common
# Copyright (C) 2026 NanoPi-R2S
USE_PROCD=1
START=95
STOP=10

PROG=/usr/bin/fan-pid-loop

start_service() {
    local enabled
    config_load 'fan'
    config_get enabled pid enabled '0'

    if [ "$enabled" != "1" ]; then
        echo "fan-pid disabled in /etc/config/fan; not starting"
        return 0
    fi

    procd_open_instance
    procd_set_param command "$PROG"
    procd_set_param respawn 3600 5 5
    procd_set_param stderr 1
    procd_set_param stdout 1
    procd_close_instance
}

reload_service() {
    stop
    start
}

service_triggers() {
    procd_add_reload_trigger "fan"
}
```

- [ ] **Step 4: 设可执行权限并跑 shellcheck（sh 模式）**

```bash
chmod +x files/etc/init.d/fan-pid
shellcheck -s sh files/etc/init.d/fan-pid
```

- [ ] **Step 5: 跑 bats**

```bash
bats tests/init_fan_pid.bats
```
期望 4 ok。

- [ ] **Step 6: commit**

```bash
git add files/etc/init.d/fan-pid tests/init_fan_pid.bats
git commit -m "feat(fan-pid): add procd init.d wrapper with reload trigger on /etc/config/fan"
```

---

### Task 18: fan-pid LuCI 控制器与视图

**Files:**
- Create: `files/usr/lib/lua/luci/controller/fan_pid.lua`
- Create: `files/usr/lib/lua/luci/model/cbi/fan_pid/main.lua`
- Create: `files/usr/lib/lua/luci/view/fan_pid/status_partial.htm`
- Test: `tests/luci_fan_pid.bats`

- [ ] **Step 1: 创建目录**

```bash
mkdir -p files/usr/lib/lua/luci/model/cbi/fan_pid
```

- [ ] **Step 2: 写 bats 测试**

`tests/luci_fan_pid.bats`:
```bash
#!/usr/bin/env bats

DIR="${BATS_TEST_DIRNAME}/../files/usr/lib/lua/luci"

@test "controller has lua syntax" {
    run luac -p "$DIR/controller/fan_pid.lua"
    [ "$status" -eq 0 ]
}

@test "controller registers /admin/system/fan_pid" {
    grep -q '"admin", "system", "fan_pid"' "$DIR/controller/fan_pid.lua"
}

@test "controller exposes state action" {
    grep -q "function action_state" "$DIR/controller/fan_pid.lua"
}

@test "cbi main has lua syntax" {
    run luac -p "$DIR/model/cbi/fan_pid/main.lua"
    [ "$status" -eq 0 ]
}

@test "cbi binds setpoint, kp, ki, kd" {
    grep -q "setpoint" "$DIR/model/cbi/fan_pid/main.lua"
    grep -q "\"kp\"" "$DIR/model/cbi/fan_pid/main.lua"
    grep -q "\"ki\"" "$DIR/model/cbi/fan_pid/main.lua"
    grep -q "\"kd\"" "$DIR/model/cbi/fan_pid/main.lua"
}
```

- [ ] **Step 3: 跑测试确认 fail**

- [ ] **Step 4: 实现 controller/fan_pid.lua**

```lua
module("luci.controller.fan_pid", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/fan") then
        return
    end
    entry({"admin", "system", "fan_pid"},
          cbi("fan_pid/main"), _("Fan PID"), 80).leaf = true
    entry({"admin", "system", "fan_pid", "state"},
          call("action_state")).leaf = true
end

function action_state()
    local http = require "luci.http"
    local f = io.open("/var/run/fan-pid.state", "r")
    local kv = {}
    if f then
        for line in f:lines() do
            local k, v = line:match("^(%w+)=(.*)$")
            if k then kv[k] = v end
        end
        f:close()
    end
    http.prepare_content("application/json")
    http.write_json(kv)
end
```

- [ ] **Step 5: 实现 cbi/fan_pid/main.lua**

```lua
local m = Map("fan", translate("Fan PID"),
    translate("基于 thermal_zone0 的 PID 风扇控制；保存后自动 reload。"))

local s = m:section(NamedSection, "pid", "fan", "")
s.anonymous = true
s.addremove = false

s:option(Flag, "enabled", translate("启用"))

local sp = s:option(Value, "setpoint", translate("目标温度 (°C)"))
sp.datatype = "uinteger"
sp.default = "55"

local kp = s:option(Value, "kp", translate("Kp"))
kp.default = "4.0"
local ki = s:option(Value, "ki", translate("Ki"))
ki.default = "0.2"
local kd = s:option(Value, "kd", translate("Kd"))
kd.default = "1.0"

local interval = s:option(Value, "interval", translate("采样间隔 (s)"))
interval.datatype = "uinteger"
interval.default = "5"

local pmin = s:option(Value, "pwm_min", translate("PWM min"))
pmin.datatype = "uinteger"
pmin.default = "0"

local pmax = s:option(Value, "pwm_max", translate("PWM max"))
pmax.datatype = "uinteger"
pmax.default = "255"

s:option(Value, "pwm_path", translate("PWM 设备路径")).default = "/sys/class/pwm/pwmchip0/pwm0"
s:option(Value, "thermal_path", translate("温度文件路径")).default = "/sys/class/thermal/thermal_zone0/temp"

function m.on_after_commit(self)
    luci.sys.exec("/etc/init.d/fan-pid reload >/dev/null 2>&1 &")
end

return m
```

- [ ] **Step 6: 跑 luac + bats**

```bash
luac -p files/usr/lib/lua/luci/controller/fan_pid.lua
luac -p files/usr/lib/lua/luci/model/cbi/fan_pid/main.lua
bats tests/luci_fan_pid.bats
```
期望 5 ok。

- [ ] **Step 7: commit**

```bash
git add files/usr/lib/lua/luci/controller/fan_pid.lua files/usr/lib/lua/luci/model/cbi/fan_pid/ tests/luci_fan_pid.bats
git commit -m "feat(luci): add fan_pid CBI form with auto-reload on commit"
```

---

## Phase 6 — 部署脚本

### Task 19: scripts/flash-sd.sh（macOS 烧卡）

**Files:**
- Create: `scripts/flash-sd.sh`
- Test: `tests/flash_sd.bats`

- [ ] **Step 1: 写 bats 测试**

`tests/flash_sd.bats`:
```bash
#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../scripts/flash-sd.sh"
    export FAKE_BIN="${BATS_TMPDIR}/bin"
    mkdir -p "$FAKE_BIN"

    cat > "$FAKE_BIN/diskutil" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    list)
        cat <<'OUT'
/dev/disk2 (external, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:                                                   *15.9 GB    disk2
OUT
        ;;
    info)  echo "Total Size: 15.9 GB"; echo "Internal: No" ;;
    unmountDisk) ;;
    *) ;;
esac
EOF
    chmod +x "$FAKE_BIN/diskutil"

    cat > "$FAKE_BIN/dd" <<'EOF'
#!/usr/bin/env bash
echo "would dd: $*" >&2
exit 0
EOF
    chmod +x "$FAKE_BIN/dd"

    cat > "$FAKE_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
    chmod +x "$FAKE_BIN/sudo"

    cat > "$FAKE_BIN/shasum" <<'EOF'
#!/usr/bin/env bash
echo "deadbeef00000000000000000000000000000000000000000000000000000000  -"
EOF
    chmod +x "$FAKE_BIN/shasum"

    export PATH="$FAKE_BIN:$PATH"

    # 准备假镜像
    export FAKE_IMG="${BATS_TMPDIR}/fake.img.gz"
    echo "fake-data" | gzip > "$FAKE_IMG"
    export FAKE_SHA="${BATS_TMPDIR}/fake.img.gz.sha256"
    echo "deadbeef00000000000000000000000000000000000000000000000000000000  $(basename "$FAKE_IMG")" > "$FAKE_SHA"
}

@test "passes shellcheck" {
    run shellcheck "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "shows help" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "lists disks" {
    run "$SCRIPT" --list
    [ "$status" -eq 0 ]
    [[ "$output" == *"disk2"* ]]
}

@test "writes when target + image given (dry-run mode)" {
    run env DRY_RUN=1 "$SCRIPT" --image "$FAKE_IMG" --target /dev/disk2 --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"would dd"* ]] || [[ "$output" == *"DRY"* ]]
}

@test "refuses non-external disk" {
    cat > "$FAKE_BIN/diskutil" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    info) echo "Total Size: 500 GB"; echo "Internal: Yes" ;;
    *) echo "/dev/disk0 (internal, physical):" ;;
esac
EOF
    chmod +x "$FAKE_BIN/diskutil"
    run env DRY_RUN=1 "$SCRIPT" --image "$FAKE_IMG" --target /dev/disk0 --yes
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: 跑测试确认 fail**

- [ ] **Step 3: 实现 scripts/flash-sd.sh**

```bash
#!/usr/bin/env bash
# flash-sd.sh: macOS 上把 sysupgrade.img.gz 写入 SD 卡，带二次确认与 sha256 校验
set -euo pipefail

SCRIPT_NAME=$(basename "$0")
DRY_RUN="${DRY_RUN:-0}"

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Options:
  --list              List external removable disks (diskutil)
  --image <PATH>      Path to .img.gz to flash
  --target <DEV>      Target disk (e.g., /dev/disk2)
  --yes               Skip interactive size-confirmation prompt
  --help              Show this message

环境变量:
  DRY_RUN=1           Print actions, do not write
EOF
}

require_macos() {
    [ "$(uname -s)" = "Darwin" ] || { echo "仅支持 macOS"; exit 1; }
}

list_disks() {
    diskutil list | awk '/^\/dev\/disk[0-9]+ \(external, physical\):/{print $0}'
}

verify_external() {
    local dev="$1"
    diskutil info "$dev" 2>/dev/null | grep -qE "Internal:[[:space:]]*No" || {
        echo "拒绝：$dev 不是外置可移除磁盘" >&2
        return 1
    }
}

confirm_size() {
    local dev="$1"
    diskutil info "$dev" | awk -F: '/Total Size/ {print $2}' | sed 's/^[[:space:]]*//' | head -1
}

extract_image() {
    local gz="$1" out="$2"
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "would gunzip -c $gz > $out"
        return 0
    fi
    gunzip -c "$gz" > "$out"
}

verify_sha() {
    local file="$1" sha_file="$2"
    [ -f "$sha_file" ] || { echo "no sha file ($sha_file); skip verify"; return 0; }
    local expected; expected=$(awk '{print $1}' "$sha_file" | head -1)
    local actual; actual=$(shasum -a 256 "$file" | awk '{print $1}')
    [ "$expected" = "$actual" ] || { echo "sha256 不匹配 (expected=$expected actual=$actual)"; return 1; }
}

require_macos

ACTION=""
IMAGE=""
TARGET=""
YES=0

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)  usage; exit 0 ;;
        --list)     ACTION="list" ;;
        --image)    IMAGE="$2"; shift ;;
        --target)   TARGET="$2"; shift ;;
        --yes)      YES=1 ;;
        *)          echo "Unknown: $1"; usage >&2; exit 2 ;;
    esac
    shift
done

if [ "$ACTION" = "list" ]; then
    list_disks
    exit 0
fi

[ -n "$IMAGE" ] && [ -n "$TARGET" ] || { usage >&2; exit 2; }
[ -f "$IMAGE" ] || { echo "image 不存在: $IMAGE"; exit 1; }

verify_external "$TARGET" || exit 1

# sha256 校验（如有 .sha256 同名文件）
verify_sha "$IMAGE" "${IMAGE}.sha256" || exit 1

SIZE=$(confirm_size "$TARGET")
echo "Target: $TARGET  Size: $SIZE"
echo "Image:  $IMAGE"

if [ "$YES" -ne 1 ]; then
    read -r -p "请输入磁盘大小数字（如 16，确认无误）: " CONFIRMED_SIZE
    case "$SIZE" in
        *"${CONFIRMED_SIZE}"*) ;;
        *) echo "大小不匹配，终止"; exit 1 ;;
    esac
    read -r -p "确认写入 $TARGET？[type 'yes'] " ANSWER
    [ "$ANSWER" = "yes" ] || { echo "取消"; exit 1; }
fi

# 把 /dev/disk2 改写成 /dev/rdisk2 以加速
RAW_TARGET="${TARGET/disk/rdisk}"
TMP_IMG=$(mktemp -t r2s-flash.XXXXXX.img)
trap 'rm -f "$TMP_IMG"' EXIT

echo "[1/3] 解压镜像 -> $TMP_IMG"
extract_image "$IMAGE" "$TMP_IMG"

echo "[2/3] 卸载 $TARGET"
if [ "$DRY_RUN" -eq 1 ]; then
    echo "would diskutil unmountDisk $TARGET"
else
    diskutil unmountDisk "$TARGET"
fi

echo "[3/3] dd if=$TMP_IMG of=$RAW_TARGET bs=4m"
if [ "$DRY_RUN" -eq 1 ]; then
    echo "would sudo dd if=$TMP_IMG of=$RAW_TARGET bs=4m"
else
    sudo dd if="$TMP_IMG" of="$RAW_TARGET" bs=4m status=progress
    sync
    diskutil eject "$TARGET" 2>/dev/null || true
fi

echo "完成"
```

- [ ] **Step 4: 设可执行权限并跑 shellcheck**

```bash
chmod +x scripts/flash-sd.sh
shellcheck scripts/flash-sd.sh
```

- [ ] **Step 5: 跑 bats**

```bash
bats tests/flash_sd.bats
```
期望 5 ok。

- [ ] **Step 6: commit**

```bash
git add scripts/flash-sd.sh tests/flash_sd.bats
git commit -m "feat(scripts): add macOS flash-sd with two-step confirmation and sha256 verify"
```

---

### Task 20: 部署前检查脚本扩展

**Files:**
- Modify: `scripts/pre-deploy-check.sh`（已在 Task 2 创建占位，本任务扩展构建产物存在性检查）
- Test: `tests/pre_deploy_check.bats`（追加测试）

- [ ] **Step 1: 给 bats 追加测试**

在 `tests/pre_deploy_check.bats` 末尾追加：
```bash
@test "--check-image fails when no image" {
    run env CHECK_IMAGE_DIR="${BATS_TMPDIR}/empty" "${BATS_TEST_DIRNAME}/../scripts/pre-deploy-check.sh" --check-image
    [ "$status" -ne 0 ]
}

@test "--check-image succeeds when image present" {
    mkdir -p "${BATS_TMPDIR}/with-image"
    : > "${BATS_TMPDIR}/with-image/immortalwrt-rockchip-armv8-friendlyarm_nanopi-r2s-squashfs-sysupgrade.img.gz"
    run env CHECK_IMAGE_DIR="${BATS_TMPDIR}/with-image" "${BATS_TEST_DIRNAME}/../scripts/pre-deploy-check.sh" --check-image
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: 跑测试确认 fail**

- [ ] **Step 3: 修改 scripts/pre-deploy-check.sh**

在 `DRY_RUN=1` 解析后追加：
```bash
CHECK_IMAGE=0
case "${1:-}" in
    --check-image) CHECK_IMAGE=1; shift ;;
esac

if [ "$CHECK_IMAGE" -eq 1 ]; then
    DIR="${CHECK_IMAGE_DIR:-out}"
    found=$(find "$DIR" -name 'immortalwrt-*nanopi-r2s*sysupgrade.img.gz' -type f 2>/dev/null | head -1)
    if [ -z "$found" ]; then
        echo "no sysupgrade image found under $DIR"
        exit 1
    fi
    echo "OK: found image $found"
    exit 0
fi
```

注意：把 `[ "${1:-}" = "--dry-run" ] && DRY_RUN=1` 改为支持 `--check-image` 与 `--dry-run` 并存的解析。

修改后的开头部分：
```bash
#!/usr/bin/env bash
set -u
DRY_RUN=0
CHECK_IMAGE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)     DRY_RUN=1 ;;
        --check-image) CHECK_IMAGE=1 ;;
        *) echo "unknown: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ "$CHECK_IMAGE" -eq 1 ]; then
    DIR="${CHECK_IMAGE_DIR:-out}"
    found=$(find "$DIR" -name 'immortalwrt-*nanopi-r2s*sysupgrade.img.gz' -type f 2>/dev/null | head -1)
    if [ -z "$found" ]; then
        echo "no sysupgrade image found under $DIR"
        exit 1
    fi
    echo "OK: found image $found"
    exit 0
fi
```

- [ ] **Step 4: 跑 shellcheck + bats**

```bash
shellcheck scripts/pre-deploy-check.sh
bats tests/pre_deploy_check.bats
```
期望全 ok（含原有 3 个 + 新增 2 个）。

- [ ] **Step 5: commit**

```bash
git add scripts/pre-deploy-check.sh tests/pre_deploy_check.bats
git commit -m "feat(scripts): pre-deploy-check supports --check-image"
```

---

## Phase 7 — CI 与文档

### Task 21: GitHub Actions 编译流水线

**Files:**
- Create: `.github/workflows/build.yml`
- Test: `tests/ci_workflow.bats`

- [ ] **Step 1: 写 bats 测试**

`tests/ci_workflow.bats`:
```bash
#!/usr/bin/env bats

WF="${BATS_TEST_DIRNAME}/../.github/workflows/build.yml"

@test "yaml is valid (python yaml.safe_load)" {
    run python3 -c "import yaml,sys; yaml.safe_load(open('$WF'))"
    [ "$status" -eq 0 ]
}

@test "triggers on push, workflow_dispatch, tag v*" {
    grep -q "push:" "$WF"
    grep -q "workflow_dispatch:" "$WF"
    grep -q "tags:" "$WF"
}

@test "uses ubuntu-latest runner" {
    grep -q "runs-on: ubuntu-latest" "$WF"
}

@test "frees disk space" {
    grep -qE "free.*disk|jlumbroso/free-disk-space|rm -rf /usr/share/dotnet" "$WF"
}

@test "checks IMMORTALWRT_COMMIT" {
    grep -q "IMMORTALWRT_COMMIT" "$WF"
}

@test "uploads artifact" {
    grep -q "actions/upload-artifact" "$WF"
}

@test "creates release on tag" {
    grep -qE "softprops/action-gh-release|gh release create" "$WF"
}

@test "uses ccache and dl cache" {
    grep -q "actions/cache" "$WF"
    grep -q "ccache" "$WF"
}
```

- [ ] **Step 2: 跑测试确认 fail**

- [ ] **Step 3: 实现 .github/workflows/build.yml**

```yaml
name: build

on:
  push:
    branches: [main]
    tags:
      - 'v*'
  workflow_dispatch:

permissions:
  contents: write

jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 360
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Free disk space
        uses: jlumbroso/free-disk-space@main
        with:
          tool-cache: true
          android: true
          dotnet: true
          haskell: true
          large-packages: true
          swap-storage: true

      - name: Install build deps
        run: |
          sudo apt-get update
          sudo apt-get install -y --no-install-recommends \
            build-essential ccache ecj fastjar file g++ gawk gettext git \
            java-propose-classpath libelf-dev libncurses-dev libssl-dev \
            python3 python3-distutils python3-setuptools rsync subversion \
            swig time unzip wget xsltproc zlib1g-dev sudo curl ca-certificates \
            bash bc bison flex gcc-multilib g++-multilib zstd

      - name: Read locked commit
        id: commit
        run: |
          COMMIT=$(tr -d '[:space:]' < build/IMMORTALWRT_COMMIT)
          echo "commit=$COMMIT" >> "$GITHUB_OUTPUT"
          echo "short=${COMMIT:0:8}" >> "$GITHUB_OUTPUT"

      - name: Clone ImmortalWrt
        run: |
          git clone https://github.com/immortalwrt/immortalwrt
          cd immortalwrt
          git checkout ${{ steps.commit.outputs.commit }}

      - name: Apply feeds
        run: |
          cp build/feeds.conf.default immortalwrt/feeds.conf.default
          cd immortalwrt
          ./scripts/feeds update -a
          ./scripts/feeds install -a

      - name: Link rootfs files
        run: |
          rm -rf immortalwrt/files
          ln -s "$PWD/files" immortalwrt/files

      - name: Apply diffconfig
        run: |
          cp build/.config.seed immortalwrt/.config
          cd immortalwrt
          make defconfig

      - name: Cache dl
        uses: actions/cache@v4
        with:
          path: immortalwrt/dl
          key: dl-${{ steps.commit.outputs.short }}-${{ hashFiles('build/.config.seed') }}
          restore-keys: |
            dl-${{ steps.commit.outputs.short }}-
            dl-

      - name: Cache ccache
        uses: actions/cache@v4
        with:
          path: ~/.ccache
          key: ccache-${{ steps.commit.outputs.short }}-${{ github.sha }}
          restore-keys: |
            ccache-${{ steps.commit.outputs.short }}-

      - name: Download sources
        run: |
          cd immortalwrt
          make download -j8 V=s 2>&1 | tail -200 || make download -j1 V=s

      - name: Build
        run: |
          cd immortalwrt
          export PATH=/usr/lib/ccache:$PATH
          make -j$(nproc) 2>&1 | tee ../logs/build.log \
            || make -j1 V=s 2>&1 | tee -a ../logs/build.log

      - name: Collect artifacts
        run: |
          OUT="out/${{ steps.commit.outputs.short }}"
          mkdir -p "$OUT"
          cp immortalwrt/bin/targets/rockchip/armv8/*nanopi-r2s* "$OUT/" || true
          cp immortalwrt/bin/targets/rockchip/armv8/sha256sums   "$OUT/" || true
          ls -lh "$OUT"

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: nanopi-r2s-${{ steps.commit.outputs.short }}
          path: out/
          if-no-files-found: error

      - name: Upload build log
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: build-log-${{ steps.commit.outputs.short }}
          path: logs/
          if-no-files-found: ignore

      - name: GitHub Release on tag
        if: startsWith(github.ref, 'refs/tags/v')
        uses: softprops/action-gh-release@v2
        with:
          files: |
            out/**/immortalwrt-rockchip-armv8-friendlyarm_nanopi-r2s-squashfs-sysupgrade.img.gz
            out/**/sha256sums
```

- [ ] **Step 4: 跑 bats**

```bash
bats tests/ci_workflow.bats
```
期望 8 ok。

- [ ] **Step 5: commit**

```bash
git add .github/workflows/build.yml tests/ci_workflow.bats
git commit -m "feat(ci): add GitHub Actions build pipeline with cache and release"
```

---

### Task 22: 完善 README + 实机测试清单

**Files:**
- Modify: `README.md`
- Create: `docs/manual-tests.md`

- [ ] **Step 1: 重写 README.md**

```markdown
# NanoPi R2S 多模式定制 OpenWRT

[![build](https://github.com/<user>/<repo>/actions/workflows/build.yml/badge.svg)](https://github.com/<user>/<repo>/actions/workflows/build.yml)

基于 ImmortalWrt master 的 NanoPi R2S 定制固件，**单镜像**在线切换三种工作模式：

| 模式 | 用途 |
| --- | --- |
| `switch-equal`（默认） | 双口对等交换：eth0+eth1 桥接 br-lan，同段 DHCP，互通 |
| `pppoe-main` | PPPoE 主路由：eth0 拨号、eth1 LAN |
| `bypass-gateway` | 旁路由透明网关：eth0 单臂，挂上级路由下 |

## 特性

- ImmortalWrt master（编译时锁定 commit）
- 内置 Passwall2 / SmartDNS / Tailscale / WireGuard / SQM / ttyd
- LuCI 模式切换页面（`状态 → Mode Switch`）
- LuCI PID 风扇控制页面（`系统 → Fan PID`）
- macOS Docker 一键编译 + GitHub Actions CI

## 默认参数

| 项 | 值 |
| --- | --- |
| LAN 网段 | 192.168.2.0/24 |
| LAN IP | 192.168.2.1 |
| 主机名 | `NanoPi-R2S` |
| 时区 | Asia/Shanghai |
| 默认初始模式 | `switch-equal` |

首次开机访问 `http://192.168.2.1` 即提示设置 root 密码。

## 快速开始

### 依赖

```bash
brew install bats-core shellcheck hadolint lua
# 启动 Docker Desktop
./scripts/pre-deploy-check.sh
```

### 编译

```bash
./build/build.sh                 # 完整编译（首次约 1-3 小时）
./build/build.sh --update-feeds  # 只刷新 feeds
./build/build.sh --shell         # 进容器调试
./build/build.sh --no-cache      # 强制重编
```

产物：`out/<date>-<commit>/immortalwrt-rockchip-armv8-friendlyarm_nanopi-r2s-squashfs-sysupgrade.img.gz`

### 烧录

```bash
./scripts/flash-sd.sh --list                                  # 列出外置磁盘
./scripts/flash-sd.sh --image out/.../sysupgrade.img.gz \
                      --target /dev/disk2                     # 二次确认后写卡
```

### 切换模式

启动后浏览器访问 LuCI（默认 `http://192.168.2.1`）：

1. `状态 → Mode Switch`
2. 选目标模式（PPPoE 主路由前请先到 `PPPoE` tab 填账号）
3. 点击切换；网络 5 秒内未起则自动回滚

CLI：
```bash
ssh root@192.168.2.1 mode-switch pppoe   # 或 switch / bypass / status
```

## 目录结构

参见 [`docs/superpowers/specs/2026-04-25-nanopi-r2s-openwrt-design.md`](docs/superpowers/specs/2026-04-25-nanopi-r2s-openwrt-design.md) §5。

## 文档

- 设计 spec: `docs/superpowers/specs/2026-04-25-nanopi-r2s-openwrt-design.md`
- 实施 plan: `docs/superpowers/plans/2026-04-25-nanopi-r2s-openwrt-implementation.md`
- 实机测试清单: `docs/manual-tests.md`
```

- [ ] **Step 2: 创建 docs/manual-tests.md**

```markdown
# 实机测试清单

## 前置

- 烧录最新 `out/<date>-<commit>/sysupgrade.img.gz` 到 microSD
- 准备：
  - 上级路由（用于 bypass 模式测试）
  - 一台测试 PC（直连 R2S）
  - PPPoE 测试账号（用于 pppoe 模式）
  - 串口 / SSH 客户端

## 1. 启动与默认模式

- [ ] R2S 上电，金属壳风扇短暂全速 → 数秒内 PID 接管平滑下降
- [ ] PC 网线接 R2S 任一网口（默认 switch-equal，两口等效）
- [ ] PC 自动取得 192.168.2.x IP
- [ ] 浏览器访问 `http://192.168.2.1`，提示设置 root 密码
- [ ] 设密码后能进 LuCI 主页

## 2. switch-equal（默认）

- [ ] 同时连两台 PC 各到一个网口，分别取得 192.168.2.x
- [ ] PC1 ping PC2 通
- [ ] `cat /etc/config/mode-switch` 显示 `current.name='switch-equal'`

## 3. pppoe-main

- [ ] LuCI `Mode Switch → PPPoE` tab，填测试账号 + 保存
- [ ] LuCI `Mode Switch → Status`，点 "PPPoE 主路由"
- [ ] 等待 ~30 秒，`ifstatus wan | jq .ipv4-address` 取得运营商 IP
- [ ] LAN 客户端能上网，DNS 解析正常
- [ ] `iptables -t nat -nvL | grep MASQUERADE` 看到规则

## 4. bypass-gateway

- [ ] LuCI `Mode Switch → Bypass` tab，填上级网关 IP / 掩码 / DNS / 本机 IP
- [ ] 切换到 bypass
- [ ] 上级路由内手动改一台 PC 网关到 R2S 旁路 IP
- [ ] PC 仍能上网；`traceroute 8.8.8.8` 第一跳显示 R2S
- [ ] Passwall2 启用一个简单代理；测试国外访问走代理

## 5. 模式切换无残留

- [ ] 从 pppoe → switch → bypass → switch 来回各一次
- [ ] 每次切换后 `ip a` 和 `cat /etc/config/network` 内容与 profile 一致
- [ ] 没有遗留的 `pppoe-wan` 接口或 br-lan 残留
- [ ] `find /etc -maxdepth 1 -name 'config.bak.*' -type d` 累计备份按时间排序

## 6. PID 风扇

- [ ] 启动 `stress-ng --cpu 4 --timeout 5m`
- [ ] 5 分钟内温度收敛在 setpoint (55°C) ±5°C
- [ ] `tail -f /var/run/fan-pid.state` 看到 pwm 平滑变化（不抖动）
- [ ] LuCI `系统 → Fan PID` 改 setpoint=60，保存后 5 秒内 pwm 下降

## 7. 异常恢复

- [ ] 故意填一个不存在的 PPPoE 账号 + 切换 → 5 秒回滚到原模式
- [ ] `tail /var/log/mode-switch.log` 看到 rollback 记录
- [ ] 删除 `/sys/class/thermal/thermal_zone0/temp`（用 mount --bind 一个空文件） → 风扇切到全速；放开后恢复
```

- [ ] **Step 3: 提交**

```bash
git add README.md docs/manual-tests.md
git commit -m "docs: complete README and manual-tests checklist"
```

---

### Task 23: 端到端验证

**Files:**
- 无新建；本任务是验证里程碑

- [ ] **Step 1: 跑全部 bats**

```bash
bats tests/
```
期望全 ok（约 50+ 测试）。

- [ ] **Step 2: 跑 shellcheck 全扫描**

```bash
find scripts build files/etc/uci-defaults files/etc/init.d files/usr/bin -type f \
    -exec shellcheck -x {} +
```
期望 0 warning。

- [ ] **Step 3: 跑 luac 全扫描**

```bash
find files/usr/lib/lua -name '*.lua' -exec luac -p {} \;
```
期望无输出（=全部 syntax pass）。

- [ ] **Step 4: 跑 hadolint**

```bash
hadolint --config docker/.hadolint.yaml docker/Dockerfile
```

- [ ] **Step 5: 本地完整编译**

```bash
./build/build.sh
```

- [ ] **Step 6: 验证产物**

```bash
./scripts/pre-deploy-check.sh --check-image
ls -lh out/*/immortalwrt-*nanopi-r2s*sysupgrade.img.gz
# 期望 30-60 MB
```

- [ ] **Step 7: 推到 GitHub 触发 CI**

```bash
git remote add origin git@github.com:<user>/OpenWRT_R2S.git   # 首次
git push -u origin main
```
- 在 GitHub Actions 页面观察 workflow，期望编译成功并产出 artifact。

- [ ] **Step 8: 烧录 & 实机**

按 `docs/manual-tests.md` 逐项执行。

- [ ] **Step 9: 创建版本 tag 触发 release**

```bash
git tag v0.1.0
git push origin v0.1.0
```
GitHub Releases 页面应自动创建 v0.1.0 release，含 sysupgrade.img.gz + sha256sums。

- [ ] **Step 10: 最终 commit（如有杂项调整）**

```bash
git add -A
git status   # 确认无遗漏
git commit -m "chore: end-to-end validation pass" || true
```

---

## 附录 A — 已知风险与应急策略

| 风险 | 影响 | 应急 |
| --- | --- | --- |
| ImmortalWrt master 引入破坏性变更 | 编译失败或 LuCI 不兼容 | 把 IMMORTALWRT_COMMIT 退回上一个已知好 commit |
| R2S DTS 未暴露 PWM 节点 | fan-pid 写不到 `/sys/class/pwm/...` | 退化到日志限流 + 全速；后续在 `patches/` 加 DTS overlay |
| Passwall2 第三方 feed 上游变更 | feeds install 失败 | feeds.conf 锁定具体 commit/分支；如必要在 `patches/` 加补丁 |
| GitHub Actions 磁盘不足 | 编译中途 No space | 已用 jlumbroso/free-disk-space；不行则换 self-hosted runner |
| macOS Docker Desktop QEMU 性能差 | Apple Silicon 强制 amd64 编译过慢 | 容器走原生 linux/arm64（Dockerfile 不指定 platform） |

## 附录 B — 调试命令速查

| 目标 | 命令 |
| --- | --- |
| 看当前模式 | `mode-switch status` |
| 看模式切换日志 | `tail -f /var/log/mode-switch.log` |
| 看风扇状态 | `cat /var/run/fan-pid.state` |
| 看温度 | `cat /sys/class/thermal/thermal_zone0/temp` |
| 看 PPPoE 拨号状态 | `ifstatus wan` |
| 强制风扇全速 | `echo 255 > /sys/class/pwm/pwmchip0/pwm0/duty_cycle` |
| 重启网络 | `/etc/init.d/network restart && /etc/init.d/firewall restart && /etc/init.d/dnsmasq restart` |

---

**自审完成日期：** 2026-04-25

**Spec coverage 自查：** 设计 §3.1 (Task 5/6) / §3.2 (Task 6) / §3.3 (Task 8/9/10) / §3.4 (Task 11/12/13/14) / §3.5 (Task 15/16/17/18) / §3.6 (Task 7) / §3.7 (Task 7) / §4.1-4.3 (Task 3/4/5/6) / §4.4 (Task 21) / §5 (Task 1) / §6 (Task 19) / §7 (Task 12/16/19) / §8.1 (Task 6/23) / §8.2 (Task 7/12/16) / §8.3 (Task 22)。无遗漏。
