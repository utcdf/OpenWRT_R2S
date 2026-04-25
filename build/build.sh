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
            bash build/build.sh "$([ "$ACTION" = "update-feeds" ] && echo --update-feeds)" \
            "$([ "$NO_CACHE" -eq 1 ] && echo --no-cache)"
        ;;
esac
