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
    echo "would dd if=$TMP_IMG of=$RAW_TARGET bs=4m"
else
    sudo dd if="$TMP_IMG" of="$RAW_TARGET" bs=4m status=progress
    sync
    diskutil eject "$TARGET" 2>/dev/null || true
fi

echo "完成"
