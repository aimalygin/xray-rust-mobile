#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

require_stable=0
if [[ "${1:-}" == "--require-stable" ]]; then
  require_stable=1
  shift
fi

value="${1:-}"
[[ "$#" -eq 1 && -n "$value" ]] ||
  die "usage: $0 [--require-stable] <version-or-tag>"

version="${value#v}"
semver_core='(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
if [[ "$version" =~ ^${semver_core}$ ]]; then
  channel="stable"
elif [[ "$version" =~ ^${semver_core}-rc\.([1-9][0-9]*)$ ]]; then
  channel="prerelease"
else
  die "unsupported release version $value; expected MAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH-rc.N with N >= 1"
fi

if [[ "$require_stable" -eq 1 && "$channel" != "stable" ]]; then
  die "remote Maven publication is restricted to stable release tags: $value"
fi

echo "$channel"
