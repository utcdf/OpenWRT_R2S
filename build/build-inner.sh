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

# Step C/D 在 Task 6 中填充（链接 files/、写入 .config、make）
echo "[inner] config + build steps not yet implemented (Task 6)"
exit 0
