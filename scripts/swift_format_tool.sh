#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pkg_dir="${repo_root}/PlaywrightDashboard"
tools_dir="${pkg_dir}/.build/tools"
source_dir="${tools_dir}/swift-format-src"
install_dir="${tools_dir}/swift-format"
local_bin="${install_dir}/swift-format"
tag="${SWIFT_FORMAT_TAG:-swift-6.3.1-RELEASE}"
repo_url="${SWIFT_FORMAT_REPO:-https://github.com/swiftlang/swift-format.git}"

find_global_swift_format() {
  if [ "${SWIFT_FORMAT_SKIP_GLOBAL:-0}" = "1" ]; then
    return 1
  fi

  if command -v swift-format >/dev/null 2>&1; then
    command -v swift-format
    return 0
  fi

  if command -v xcrun >/dev/null 2>&1 && xcrun --find swift-format >/dev/null 2>&1; then
    xcrun --find swift-format
    return 0
  fi

  return 1
}

ensure_local_swift_format() {
  if [ -x "${local_bin}" ]; then
    return 0
  fi

  mkdir -p "${tools_dir}"

  if [ ! -d "${source_dir}/.git" ]; then
    rm -rf "${source_dir}"
    git clone --depth 1 --branch "${tag}" "${repo_url}" "${source_dir}"
  else
    git -C "${source_dir}" fetch --depth 1 origin "refs/tags/${tag}:refs/tags/${tag}"
    git -C "${source_dir}" checkout --detach "${tag}"
  fi

  swift build \
    --package-path "${source_dir}" \
    --configuration release \
    --product swift-format \
    --scratch-path "${tools_dir}/swift-format-build"

  mkdir -p "${install_dir}"
  cp "${tools_dir}/swift-format-build/release/swift-format" "${local_bin}"
  chmod +x "${local_bin}"
}

if [ "${SWIFT_FORMAT:-}" != "" ] && [ "${SWIFT_FORMAT}" != "$0" ]; then
  exec "${SWIFT_FORMAT}" "$@"
fi

if formatter="$(find_global_swift_format)"; then
  exec "${formatter}" "$@"
fi

ensure_local_swift_format
exec "${local_bin}" "$@"
