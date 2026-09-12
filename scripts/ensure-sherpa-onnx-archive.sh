#!/usr/bin/env bash
# Download the sherpa-onnx-sys prebuilt archive with OS-trust curl.
#
# sherpa-onnx-sys's build.rs fetches GitHub release tarballs with ureq + rustls
# webpki roots. Corporate TLS inspection (a company FORWARDTRUST CA in the OS
# store) makes that download fail with UnknownIssuer while /usr/bin/curl and
# Safari succeed. Point SHERPA_ONNX_ARCHIVE_DIR at a curl-fetched copy so the
# build script never opens its own TLS stack.
#
# Source this file from desktop cargo/tauri recipes, or run it to print the
# cache directory. Existing SHERPA_ONNX_LIB_DIR / SHERPA_ONNX_ARCHIVE_DIR values
# are left alone when they already satisfy the crate.

set -euo pipefail

_buzz_sherpa_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_buzz_sherpa_repo_root="$(cd "${_buzz_sherpa_script_dir}/.." && pwd)"

sherpa_onnx_sys_version_from_lock() {
    local lock="$1"
    awk '
        $0 == "name = \"sherpa-onnx-sys\"" { found = 1; next }
        found && $1 == "version" {
            gsub(/"/, "", $3)
            print $3
            exit
        }
    ' "$lock"
}

sherpa_onnx_archive_name() {
    local version="$1"
    local host="$2"
    local triple
    case "$host" in
        aarch64-apple-darwin) triple="osx-arm64-static-lib" ;;
        x86_64-apple-darwin) triple="osx-x64-static-lib" ;;
        x86_64-unknown-linux-gnu | x86_64-unknown-linux-musl) triple="linux-x64-static-lib" ;;
        aarch64-unknown-linux-gnu | aarch64-unknown-linux-musl) triple="linux-aarch64-static-lib" ;;
        x86_64-pc-windows-msvc | x86_64-pc-windows-gnu) triple="win-x64-static-MT-Release-lib" ;;
        *)
            echo "error: no sherpa-onnx prebuilt archive for host ${host}" >&2
            return 1
            ;;
    esac
    printf 'sherpa-onnx-v%s-%s.tar.bz2\n' "$version" "$triple"
}

sherpa_onnx_curl() {
    if [[ -x /usr/bin/curl ]]; then
        printf '%s\n' /usr/bin/curl
        return 0
    fi
    command -v curl
}

sherpa_onnx_default_cache() {
    printf '%s\n' "${BUZZ_SHERPA_ONNX_CACHE:-${_buzz_sherpa_repo_root}/.cache/sherpa-onnx-archives}"
}

ensure_sherpa_onnx_archive() {
    if [[ -n "${SHERPA_ONNX_LIB_DIR:-}" ]]; then
        return 0
    fi

    local lock="${_buzz_sherpa_repo_root}/desktop/src-tauri/Cargo.lock"
    local version host archive cache dest url curl_bin tmp
    version="$(sherpa_onnx_sys_version_from_lock "$lock")"
    if [[ -z "$version" ]]; then
        echo "error: could not read sherpa-onnx-sys version from ${lock}" >&2
        return 1
    fi

    host="${BUZZ_SHERPA_ONNX_HOST:-$(rustc -vV | sed -n 's/^host: //p')}"
    archive="$(sherpa_onnx_archive_name "$version" "$host")"
    cache="$(sherpa_onnx_default_cache)"
    if [[ -n "${SHERPA_ONNX_ARCHIVE_DIR:-}" ]]; then
        cache="$SHERPA_ONNX_ARCHIVE_DIR"
    fi
    dest="${cache}/${archive}"

    if [[ -f "$dest" ]]; then
        export SHERPA_ONNX_ARCHIVE_DIR="$cache"
        return 0
    fi

    url="https://github.com/k2-fsa/sherpa-onnx/releases/download/v${version}/${archive}"
    curl_bin="$(sherpa_onnx_curl)" || {
        echo "error: curl is required to fetch ${url}" >&2
        return 1
    }

    mkdir -p "$cache"
    tmp="${dest}.partial"
    echo "Fetching sherpa-onnx libs with ${curl_bin} (OS certificate store): ${url}" >&2

    # macOS /usr/bin/curl uses the Keychain, including enterprise TLS-inspection
    # CAs. Drop rustls-oriented CA overrides so we do not inherit a webpki bundle.
    if [[ "$(uname -s)" == Darwin ]]; then
        env -u SSL_CERT_FILE -u CURL_CA_BUNDLE -u REQUESTS_CA_BUNDLE \
            "$curl_bin" -fL --retry 3 --connect-timeout 30 -o "$tmp" "$url"
    else
        "$curl_bin" -fL --retry 3 --connect-timeout 30 -o "$tmp" "$url"
    fi
    mv "$tmp" "$dest"
    export SHERPA_ONNX_ARCHIVE_DIR="$cache"
}

if [[ "${BUZZ_SHERPA_ONNX_SKIP_RUN:-}" != 1 ]]; then
    ensure_sherpa_onnx_archive
    if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
        printf '%s\n' "${SHERPA_ONNX_ARCHIVE_DIR:-}"
    fi
fi
