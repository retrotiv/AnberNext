#!/bin/sh
# AnberNext Rollback.pak — restore the most recent backup made by AnberNext Update.pak.
# Same safety scope: only ever writes to the boot card this pak lives on.

set -u
PAKDIR="$(cd "$(dirname "$0")" && pwd)"

find_sdcard() {
	d="$PAKDIR"; i=0
	while [ "$i" -lt 8 ]; do
		[ -d "$d/.system/rg353" ] && { printf '%s\n' "$d"; return 0; }
		nd="$(dirname "$d")"; [ "$nd" = "$d" ] && break; d="$nd"; i=$((i + 1))
	done
	return 1
}
SDCARD="$(find_sdcard)" || { echo "FATAL: boot card not found"; exit 1; }
SDCARD="$(cd "$SDCARD" && pwd -P)"
case "$SDCARD" in "" | "/" | *sd2* | *mmcblk0* | *android* ) echo "ABORT: refusing '$SDCARD'"; exit 1;; esac
[ -d "$SDCARD/.system/rg353" ] || { echo "ABORT: not the boot card"; exit 1; }

WORK="$SDCARD/.anbernext"; BACKUP="$WORK/backup"
LOG="$SDCARD/.userdata/rg353/logs/anbernext-ota.log"
RESULT="$WORK/last-result.txt"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] rollback: $*" >>"$LOG"; echo "$*"; }
result() { printf '%s\n' "$*" >"$RESULT" 2>/dev/null; log "$*"; }

# newest backup dir
LAST="$(ls -1dt "$BACKUP"/*/ 2>/dev/null | head -1)"
[ -n "$LAST" ] && [ -d "$LAST" ] || { result "No backup to restore."; exit 0; }
LAST="${LAST%/}"

log "restoring from $LAST"
( cd "$LAST" && find . -type f ) | while read -r f; do
	rel="${f#./}"
	dest="$SDCARD/$rel"
	destdir="$(dirname "$dest")"
	mkdir -p "$destdir" 2>/dev/null
	rdd="$(cd "$destdir" 2>/dev/null && pwd -P)" || continue
	case "$rdd/" in "$SDCARD/"*) : ;; *) continue;; esac
	cp -p "$LAST/$rel" "$dest" 2>>"$LOG"
done

# restore the release tag too, if the backup carried it
[ -f "$LAST/.system/rg353/anbernext-release.txt" ] && cp -p "$LAST/.system/rg353/anbernext-release.txt" "$SDCARD/.system/rg353/anbernext-release.txt" 2>/dev/null

sync
result "Rolled back from ${LAST#$SDCARD/}. Restart to use it."
exit 0
