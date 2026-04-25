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
