#!/usr/bin/env bash
set -euo pipefail

DRIFT_VERSION="2.35.4"
RELEASE_BASE="https://github.com/simolus3/drift/releases/download/drift-${DRIFT_VERSION}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_DIR="${ROOT_DIR}/web"
mkdir -p "${WEB_DIR}"

download_and_verify() {
  local file_name="$1"
  local expected_sha256="$2"
  local destination="${WEB_DIR}/${file_name}"

  echo "Downloading ${file_name} from Drift ${DRIFT_VERSION}..."
  curl --fail --location --silent --show-error \
    "${RELEASE_BASE}/${file_name}" \
    --output "${destination}"

  local actual_sha256
  if command -v sha256sum >/dev/null 2>&1; then
    actual_sha256="$(sha256sum "${destination}" | awk '{print $1}')"
  else
    actual_sha256="$(shasum -a 256 "${destination}" | awk '{print $1}')"
  fi

  if [[ "${actual_sha256}" != "${expected_sha256}" ]]; then
    rm -f "${destination}"
    echo "SHA-256 verification failed for ${file_name}. File removed." >&2
    exit 1
  fi

  echo "Verified ${file_name}"
}

download_and_verify \
  "sqlite3.wasm" \
  "e7451780e78c56ff864fe9317a0fbcd6aeb2e8de3beba7f5efd963202f7ec3d9"
download_and_verify \
  "drift_worker.js" \
  "48c950cd8e3bc3cddb34816c860e228be8832bef07a297c27e9907c057ff8162"

echo "Drift Web assets are installed and checksum-verified."
