#!/usr/bin/env bash
# make-update-package.sh — build an AnberNext OTA update package for a release.
#
# Usage:
#   tools/make-update-package.sh <tag> <nextui-layer-root> [out-dir] [paths...]
#
#   <tag>                e.g. v3.15  (must match the GitHub release tag)
#   <nextui-layer-root>  a directory that contains .system/rg353 (the boot card's NEXTUI
#                        partition, or a build output tree laid out the same way)
#   [out-dir]            where to write the package (default: ./dist)
#   [paths...]           optional: only these subpaths (relative to the root) go in the
#                        package — for a light "patch" release. Default ships the whole
#                        NextUI layer: .system/rg353 Tools/rg353 Emus/rg353
#
# Produces, in <out-dir>:
#   anbernext-<tag>-update.zip          the package the device downloads
#   anbernext-<tag>-update.zip.sha256   checksum the device verifies before unpacking
# and, inside the zip:
#   anbernext-release.txt               the tag (device refuses a package whose tag differs)
#   MANIFEST.sha256                      per-file checksums (device verifies each)
#
# Upload BOTH output files as assets of the GitHub release <tag>.
set -euo pipefail

TAG="${1:?usage: make-update-package.sh <tag> <layer-root> [out-dir] [paths...]}"
ROOT="${2:?missing nextui-layer-root}"
OUT="${3:-dist}"
shift || true; shift || true; [ $# -gt 0 ] && shift || true
PATHS=("$@")
[ ${#PATHS[@]} -eq 0 ] && PATHS=(".system/rg353" "Tools/rg353" "Emus/rg353")

[ -d "$ROOT/.system/rg353" ] || { echo "error: '$ROOT' does not contain .system/rg353" >&2; exit 1; }
command -v zip >/dev/null || { echo "error: need 'zip'" >&2; exit 1; }
command -v sha256sum >/dev/null || { echo "error: need 'sha256sum'" >&2; exit 1; }

mkdir -p "$OUT"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo ">> staging $TAG from $ROOT"
for p in "${PATHS[@]}"; do
	case "$p" in /*|*..*) echo "error: unsafe path '$p'" >&2; exit 1;; esac
	if [ -e "$ROOT/$p" ]; then
		mkdir -p "$STAGE/$(dirname "$p")"
		cp -a "$ROOT/$p" "$STAGE/$(dirname "$p")/"
		echo "   + $p"
	else
		echo "   (skip, absent) $p"
	fi
done

# the package's own tag — the device compares this with the release it fetched
printf '%s\n' "$TAG" >"$STAGE/anbernext-release.txt"

# per-file manifest
( cd "$STAGE" && find . -type f ! -name MANIFEST.sha256 -print0 \
	| sort -z | xargs -0 sha256sum ) >"$STAGE/MANIFEST.sha256"

ZIP="$OUT/anbernext-${TAG}-update.zip"
rm -f "$ZIP"
( cd "$STAGE" && zip -rq "$OLDPWD/$ZIP" . )
sha256sum "$ZIP" | awk '{print $1}' >"$ZIP.sha256"

echo
echo ">> done:"
echo "   $ZIP ($(du -h "$ZIP" | cut -f1))"
echo "   $ZIP.sha256 ($(cat "$ZIP.sha256"))"
echo
echo "Next: create the GitHub release and attach both files, e.g."
echo "   gh release create $TAG \"$ZIP\" \"$ZIP.sha256\" --repo retrotiv/AnberNext \\"
echo "     --title \"AnberNext $TAG\" --notes-file docs/release-notes/$TAG.md"
