#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export BUZZ_SHERPA_ONNX_SKIP_RUN=1
# shellcheck disable=SC1091
source "$repo_root/scripts/ensure-sherpa-onnx-archive.sh"

fail() {
    echo "$*" >&2
    exit 1
}

got=$(sherpa_onnx_archive_name 1.13.4 aarch64-apple-darwin)
[[ "$got" == "sherpa-onnx-v1.13.4-osx-arm64-static-lib.tar.bz2" ]] ||
    fail "macos arm archive: $got"

got=$(sherpa_onnx_archive_name 1.13.4 x86_64-apple-darwin)
[[ "$got" == "sherpa-onnx-v1.13.4-osx-x64-static-lib.tar.bz2" ]] ||
    fail "macos x64 archive: $got"

got=$(sherpa_onnx_archive_name 1.13.4 x86_64-unknown-linux-gnu)
[[ "$got" == "sherpa-onnx-v1.13.4-linux-x64-static-lib.tar.bz2" ]] ||
    fail "linux x64 archive: $got"

got=$(sherpa_onnx_archive_name 1.13.4 aarch64-unknown-linux-gnu)
[[ "$got" == "sherpa-onnx-v1.13.4-linux-aarch64-static-lib.tar.bz2" ]] ||
    fail "linux arm archive: $got"

if sherpa_onnx_archive_name 1.13.4 wasm32-unknown-unknown >/dev/null 2>&1; then
    fail "expected unsupported host to fail"
fi

lock=$(mktemp)
trap 'rm -f "$lock"' EXIT
cat >"$lock" <<'LOCK'
[[package]]
name = "serde"
version = "1.0.0"

[[package]]
name = "sherpa-onnx-sys"
version = "1.13.4"
source = "registry+https://github.com/rust-lang/crates.io-index"
LOCK

got=$(sherpa_onnx_sys_version_from_lock "$lock")
[[ "$got" == "1.13.4" ]] || fail "lockfile version: $got"

got=$(sherpa_onnx_sys_version_from_lock "$repo_root/desktop/src-tauri/Cargo.lock")
[[ "$got" == "1.13.4" ]] || fail "desktop lockfile version drifted: $got"

curl_bin=$(sherpa_onnx_curl)
[[ -n "$curl_bin" ]] || fail "curl helper returned empty"
if [[ -x /usr/bin/curl ]]; then
    [[ "$curl_bin" == /usr/bin/curl ]] || fail "expected /usr/bin/curl, got $curl_bin"
fi

echo "ensure-sherpa-onnx-archive helper tests passed"
