#!/usr/bin/env bash
# 部署前依赖与环境检查（macOS 主机）
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
