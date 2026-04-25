#!/usr/bin/env bash
# 容器内构建流程
set -euo pipefail

ACTION="${1:-build}"
NO_CACHE="${2:-0}"

# REPO_ROOT: when running in Docker, use /work; otherwise use script's parent dir
if [ -d "/work/build" ]; then
    REPO_ROOT="/work"
else
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

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

# In DRY_RUN mode, the SRC_DIR may not exist, so create a stub for testing
if [ "$DRY_RUN" -eq 1 ] && [ ! -d "$SRC_DIR/.git" ]; then
    mkdir -p "$SRC_DIR/.git"
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
