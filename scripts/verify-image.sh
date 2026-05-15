#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Verify a Rockspack/RocksDB container image.
#
# Checks:
#   1. The remote image manifest contains the expected platforms.
#   2. The image can be pulled/run for the selected platform(s).
#   3. The container contains RocksDB headers and shared libraries.
#   4. The dynamic linker can discover librocksdb.
#
# Examples:
#   ./scripts/verify-image.sh
#   ./scripts/verify-image.sh --image haluan/rockspack:11.1.1-ubuntu26.04-devel
#   ./scripts/verify-image.sh --run all
#   ./scripts/verify-image.sh --run skip
#
# Environment overrides:
#   IMAGE=haluan/rockspack:11.1.1-ubuntu26.04-devel ./scripts/verify-image.sh
#   REQUIRED_PLATFORMS="linux/amd64 linux/arm64" ./scripts/verify-image.sh
#   CONTAINER_ENGINE=podman ./scripts/verify-image.sh
#   RUN_MODE=current ./scripts/verify-image.sh

set -Eeuo pipefail

IMAGE="${IMAGE:-haluan/rockspack:11.1.1-ubuntu26.04-devel}"
REQUIRED_PLATFORMS="${REQUIRED_PLATFORMS:-linux/amd64 linux/arm64}"
EXPECTED_UBUNTU_VERSION="${EXPECTED_UBUNTU_VERSION:-26.04}"
RUN_MODE="${RUN_MODE:-current}" # current | all | skip
CONTAINER_ENGINE="${CONTAINER_ENGINE:-}"

usage() {
  cat <<'USAGE'
Usage:
  verify-image.sh [options]

Options:
  --image <image>          Image reference to verify.
                           Default: haluan/rockspack:11.1.1-ubuntu26.04-devel

  --platforms "<list>"     Space-separated required platforms.
                           Default: "linux/amd64 linux/arm64"

  --ubuntu-version <ver>   Expected Ubuntu VERSION_ID inside the image.
                           Default: 26.04

  --run <mode>             Runtime verification mode:
                             current  Run only the current host container platform.
                             all      Run all required platforms. Requires QEMU/emulation for non-native arch.
                             skip     Only verify the remote manifest.
                           Default: current

  --engine <engine>        Container engine: docker or podman.
                           Default: auto-detect.

  -h, --help               Show this help.

Examples:
  ./scripts/verify-image.sh
  ./scripts/verify-image.sh --image haluan/rockspack:11.1.1-ubuntu26.04-devel
  ./scripts/verify-image.sh --run all
  ./scripts/verify-image.sh --run skip
USAGE
}

log() {
  printf '[verify-image] %s\n' "$*"
}

pass() {
  printf '[verify-image] PASS: %s\n' "$*"
}

fail() {
  printf '[verify-image] ERROR: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --image)
      [ "$#" -ge 2 ] || fail "--image requires a value"
      IMAGE="$2"
      shift 2
      ;;
    --platforms)
      [ "$#" -ge 2 ] || fail "--platforms requires a value"
      REQUIRED_PLATFORMS="$2"
      shift 2
      ;;
    --ubuntu-version)
      [ "$#" -ge 2 ] || fail "--ubuntu-version requires a value"
      EXPECTED_UBUNTU_VERSION="$2"
      shift 2
      ;;
    --run)
      [ "$#" -ge 2 ] || fail "--run requires one of: current, all, skip"
      RUN_MODE="$2"
      shift 2
      ;;
    --engine)
      [ "$#" -ge 2 ] || fail "--engine requires one of: docker, podman"
      CONTAINER_ENGINE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

case "$RUN_MODE" in
  current|all|skip) ;;
  *) fail "Invalid --run value: $RUN_MODE. Expected: current, all, or skip" ;;
esac

detect_engine() {
  if [ -n "$CONTAINER_ENGINE" ]; then
    command -v "$CONTAINER_ENGINE" >/dev/null 2>&1 || fail "Container engine not found: $CONTAINER_ENGINE"
    printf '%s\n' "$CONTAINER_ENGINE"
    return
  fi

  # Prefer Podman when Docker CLI is connected to a Podman backend.
  if command -v docker >/dev/null 2>&1 && docker version 2>/dev/null | grep -qi 'Podman Engine'; then
    if command -v podman >/dev/null 2>&1; then
      printf 'podman\n'
      return
    fi
  fi

  if command -v docker >/dev/null 2>&1; then
    printf 'docker\n'
    return
  fi

  if command -v podman >/dev/null 2>&1; then
    printf 'podman\n'
    return
  fi

  fail "Neither docker nor podman was found"
}

ENGINE="$(detect_engine)"
log "Container engine: $ENGINE"
log "Image: $IMAGE"
log "Required platforms: $REQUIRED_PLATFORMS"
log "Runtime verification mode: $RUN_MODE"

need_cmd python3

manifest_inspect() {
  case "$ENGINE" in
    docker)
      "$ENGINE" manifest inspect "$IMAGE"
      ;;
    podman)
      "$ENGINE" manifest inspect "docker://$IMAGE"
      ;;
    *)
      fail "Unsupported engine: $ENGINE"
      ;;
  esac
}

log "Inspecting remote manifest..."
MANIFEST_JSON="$(manifest_inspect)" || fail "Could not inspect manifest for image: $IMAGE"

PLATFORMS="$(
  printf '%s' "$MANIFEST_JSON" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
platforms = set()

def add_platform(obj):
    os_name = obj.get("os")
    arch = obj.get("architecture")
    variant = obj.get("variant")
    if os_name and arch:
        value = f"{os_name}/{arch}"
        if variant:
            value += f"/{variant}"
        platforms.add(value)

if isinstance(data, dict) and "manifests" in data:
    for manifest in data.get("manifests", []):
        platform = manifest.get("platform", {})
        add_platform(platform)
elif isinstance(data, dict):
    add_platform(data)

for platform in sorted(platforms):
    print(platform)
'
)"

[ -n "$PLATFORMS" ] || fail "No platforms found in manifest"

log "Manifest platforms:"
printf '%s\n' "$PLATFORMS" | sed 's/^/[verify-image]   - /'

platform_exists() {
  required="$1"
  while IFS= read -r actual; do
    [ "$actual" = "$required" ] && return 0
    case "$actual" in
      "$required"/*) return 0 ;;
    esac
  done <<EOF_PLATFORM_LIST
$PLATFORMS
EOF_PLATFORM_LIST
  return 1
}

for required in $REQUIRED_PLATFORMS; do
  if platform_exists "$required"; then
    pass "Manifest contains platform: $required"
  else
    fail "Manifest does not contain required platform: $required"
  fi
done

current_container_platform() {
  os="linux"
  arch="$(uname -m)"

  case "$arch" in
    x86_64|amd64)
      arch="amd64"
      ;;
    arm64|aarch64)
      arch="arm64"
      ;;
    *)
      fail "Unsupported host architecture for automatic platform detection: $arch"
      ;;
  esac

  printf '%s/%s\n' "$os" "$arch"
}

RUN_PLATFORMS=""
case "$RUN_MODE" in
  skip)
    pass "Runtime verification skipped"
    exit 0
    ;;
  current)
    RUN_PLATFORMS="$(current_container_platform)"
    ;;
  all)
    RUN_PLATFORMS="$REQUIRED_PLATFORMS"
    ;;
esac

container_verify_script='set -eu

echo "Container uname: $(uname -sm)"

if [ -f /etc/os-release ]; then
  . /etc/os-release
  echo "Container OS: ${PRETTY_NAME:-unknown}"
  if [ "${VERSION_ID:-}" != "__EXPECTED_UBUNTU_VERSION__" ]; then
    echo "ERROR: expected Ubuntu VERSION_ID=__EXPECTED_UBUNTU_VERSION__, got ${VERSION_ID:-unknown}" >&2
    exit 1
  fi
fi

test -d /usr/local/include/rocksdb
test -f /usr/local/include/rocksdb/db.h

found_lib=0
for candidate in /usr/local/lib/librocksdb.so /usr/local/lib/librocksdb.so.*; do
  if [ -e "$candidate" ]; then
    found_lib=1
    echo "Found RocksDB library: $candidate"
  fi
done

if [ "$found_lib" -ne 1 ]; then
  echo "ERROR: librocksdb.so not found under /usr/local/lib" >&2
  exit 1
fi

if command -v ldconfig >/dev/null 2>&1; then
  ldconfig
  ldconfig -p | grep -q "librocksdb" || {
    echo "ERROR: ldconfig cannot discover librocksdb" >&2
    exit 1
  }
fi

echo "RocksDB headers and shared library verified."
'
container_verify_script="${container_verify_script//__EXPECTED_UBUNTU_VERSION__/$EXPECTED_UBUNTU_VERSION}"

for platform in $RUN_PLATFORMS; do
  if ! platform_exists "$platform"; then
    fail "Selected run platform is not available in manifest: $platform"
  fi

  log "Running container verification for platform: $platform"
  "$ENGINE" run \
    --rm \
    --pull=always \
    --platform "$platform" \
    "$IMAGE" \
    /bin/sh -lc "$container_verify_script" \
    || fail "Runtime verification failed for platform: $platform"

  pass "Runtime verification succeeded for platform: $platform"
done

pass "Image verification completed successfully: $IMAGE"
