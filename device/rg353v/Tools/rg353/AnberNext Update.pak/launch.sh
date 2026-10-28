#!/bin/sh
# AnberNext Update.pak — in-device over-the-air updater for the RG353V.
#
# It pulls the latest AnberNext release from retrotiv/AnberNext over Wi-Fi and applies it
# ONLY to the NextUI card partition this pak lives on. It can never reach the shared games
# card or the console's internal (Android) storage — see the safety section below.
#
# This is deliberately the ONLY update route for AnberNext: we do not use NextUI's upstream
# auto-update. The route points at the project's own repository.

set -u

# ---------------------------------------------------------------------------------------
# where things are
# ---------------------------------------------------------------------------------------
REPO="retrotiv/AnberNext"
API="https://api.github.com/repos/${REPO}/releases/latest"

PAKDIR="$(cd "$(dirname "$0")" && pwd)"

# The top-level dirs a release is ever allowed to touch. Anything in an update package
# outside this list is refused. These are all NextUI-layer dirs on the boot card.
ALLOWED_TOP=".system Tools Emus .tmp_update"

# ---------------------------------------------------------------------------------------
# find the boot-card root, and prove it is the boot card and nothing else
# ---------------------------------------------------------------------------------------
# Walk up from the pak until we hit the partition root that holds .system/rg353. That root
# is the only place we will ever write. We never derive it from a mount guess.
find_sdcard() {
	d="$PAKDIR"
	i=0
	while [ "$i" -lt 8 ]; do
		if [ -d "$d/.system/rg353" ]; then
			printf '%s\n' "$d"
			return 0
		fi
		nd="$(dirname "$d")"
		[ "$nd" = "$d" ] && break
		d="$nd"
		i=$((i + 1))
	done
	return 1
}

SDCARD="$(find_sdcard)" || { echo "FATAL: could not locate the AnberNext boot card (.system/rg353)"; exit 1; }
SDCARD="$(cd "$SDCARD" && pwd -P)"   # resolve to a real, canonical path

LOGDIR="$SDCARD/.userdata/rg353/logs"
WORK="$SDCARD/.anbernext"
DL="$WORK/download"
STAGE="$WORK/staging"
BACKUP="$WORK/backup"
RELFILE="$SDCARD/.system/rg353/anbernext-release.txt"   # machine tag, e.g. v3.15
HUMANFILE="$SDCARD/.system/rg353/anbernext-version.txt"  # human string shown in About
RESULT="$WORK/last-result.txt"

mkdir -p "$LOGDIR" "$DL" "$STAGE" "$BACKUP" 2>/dev/null
LOG="$LOGDIR/anbernext-ota.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG"; echo "$*"; }
result() { printf '%s\n' "$*" >"$RESULT" 2>/dev/null; log "$*"; }

# best-effort on-screen message: use a NextUI presenter binary if one is present, otherwise
# just the log + result file (finalized during on-device testing).
say() {
	for p in "$SDCARD/.system/rg353/bin/minui-presenter" "$SDCARD/.system/rg353/bin/show.elf"; do
		if [ -x "$p" ]; then "$p" --message "$*" --timeout 2 >/dev/null 2>&1 && return 0; fi
	done
	log "$*"
}

# ---------------------------------------------------------------------------------------
# HARD SAFETY GATES — refuse to run unless the target is provably the boot card
# ---------------------------------------------------------------------------------------
abort() { result "ABORTED (safety): $*"; exit 1; }

case "$SDCARD" in
	"" | "/" | "/mnt" | "/media" ) abort "boot-card path looks wrong: '$SDCARD'";;
esac
# the resolved root must still carry the NextUI layer
[ -d "$SDCARD/.system/rg353" ] || abort "'$SDCARD' is not the AnberNext boot card"
# never, ever operate on a path that smells like the shared games card or internal memory
case "$SDCARD" in
	*sd2* | *SD2* | *mmcblk0* | *android* | *ANDROID* ) abort "refusing to touch '$SDCARD'";;
esac
# refuse if the games card and the boot card somehow resolved to the same place
for other in /mnt/sd2 /mnt/SDCARD2 /media/sd2; do
	[ -e "$other" ] || continue
	o="$(cd "$other" 2>/dev/null && pwd -P)" || continue
	[ "$o" = "$SDCARD" ] && abort "boot card resolves to the games card ($other)"
done

# ---------------------------------------------------------------------------------------
# tools
# ---------------------------------------------------------------------------------------
if command -v curl >/dev/null 2>&1; then GET="curl -fsSL --connect-timeout 15 -o"; GETS="curl -fsSL --connect-timeout 15";
elif command -v wget >/dev/null 2>&1; then GET="wget -q -O"; GETS="wget -q -O -";
else abort "no curl or wget on the device"; fi
command -v unzip >/dev/null 2>&1 || abort "no unzip on the device"
command -v sha256sum >/dev/null 2>&1 || abort "no sha256sum on the device"

# ---------------------------------------------------------------------------------------
# check network
# ---------------------------------------------------------------------------------------
say "AnberNext: checking for updates..."
$GETS "https://api.github.com" >/dev/null 2>&1 || { result "No internet. Connect Wi-Fi and try again."; exit 0; }

# ---------------------------------------------------------------------------------------
# read the latest release
# ---------------------------------------------------------------------------------------
JSON="$DL/latest.json"
$GET "$JSON" "$API" 2>>"$LOG" || { result "Could not reach the release server."; exit 0; }

# tag_name
LATEST="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$JSON" | head -1)"
[ -n "$LATEST" ] || { result "No release found yet in $REPO."; exit 0; }

# asset urls (browser_download_url lines), pick the update zip and its checksum
ZIP_URL="$(grep -o '"browser_download_url"[^,]*' "$JSON" | sed 's/.*"\(https[^"]*\)".*/\1/' | grep -i 'update\.zip$' | head -1)"
SHA_URL="$(grep -o '"browser_download_url"[^,]*' "$JSON" | sed 's/.*"\(https[^"]*\)".*/\1/' | grep -i 'update\.zip\.sha256$' | head -1)"
[ -n "$ZIP_URL" ] || { result "Release $LATEST has no update package."; exit 0; }

CURRENT="unknown"
[ -f "$RELFILE" ] && CURRENT="$(tr -d ' \t\r\n' <"$RELFILE")"
log "current=$CURRENT latest=$LATEST"
if [ "$CURRENT" = "$LATEST" ]; then
	result "Already up to date ($CURRENT)."
	exit 0
fi

# ---------------------------------------------------------------------------------------
# download + verify
# ---------------------------------------------------------------------------------------
say "AnberNext: downloading $LATEST..."
ZIP="$DL/update.zip"
rm -f "$ZIP"
$GET "$ZIP" "$ZIP_URL" 2>>"$LOG" || { result "Download failed."; exit 0; }

if [ -n "$SHA_URL" ]; then
	$GET "$DL/update.zip.sha256" "$SHA_URL" 2>>"$LOG"
	WANT="$(awk '{print $1}' "$DL/update.zip.sha256" | head -1)"
	HAVE="$(sha256sum "$ZIP" | awk '{print $1}')"
	if [ -z "$WANT" ] || [ "$WANT" != "$HAVE" ]; then
		result "Checksum mismatch — download rejected (want $WANT, got $HAVE)."
		exit 1
	fi
	log "checksum ok ($HAVE)"
else
	result "Release $LATEST has no checksum; refusing to apply."
	exit 1
fi

# ---------------------------------------------------------------------------------------
# extract to staging and validate EVERY path before touching the card
# ---------------------------------------------------------------------------------------
rm -rf "$STAGE"; mkdir -p "$STAGE"
unzip -oq "$ZIP" -d "$STAGE" 2>>"$LOG" || { result "Could not unpack the update."; exit 1; }

# the package must carry its own release tag and it must match the release we fetched
PKG_TAG=""
[ -f "$STAGE/anbernext-release.txt" ] && PKG_TAG="$(tr -d ' \t\r\n' <"$STAGE/anbernext-release.txt")"
[ "$PKG_TAG" = "$LATEST" ] || { result "Package tag '$PKG_TAG' != release '$LATEST' — rejected."; exit 1; }

# validate paths: relative only, no '..', top dir in the allow-list, nothing escaping SDCARD
bad=0
( cd "$STAGE" && find . -type f ! -name 'anbernext-release.txt' ! -name 'MANIFEST.sha256' ) | while read -r f; do
	rel="${f#./}"
	case "$rel" in
		/*) echo "ABSOLUTE:$rel";;
		*..*) echo "DOTDOT:$rel";;
		*) top="${rel%%/*}"
		   case " $ALLOWED_TOP " in *" $top "*) : ;; *) echo "OUTSIDE:$rel";; esac;;
	esac
done >"$DL/pathcheck.txt"
if [ -s "$DL/pathcheck.txt" ]; then
	result "Update rejected — unsafe paths: $(head -3 "$DL/pathcheck.txt" | tr '\n' ' ')"
	exit 1
fi

# per-file manifest (optional but preferred): verify each file's hash
if [ -f "$STAGE/MANIFEST.sha256" ]; then
	( cd "$STAGE" && sha256sum -c MANIFEST.sha256 ) >>"$LOG" 2>&1 || { result "A file in the package failed its checksum — rejected."; exit 1; }
	log "per-file manifest verified"
fi

# ---------------------------------------------------------------------------------------
# apply: back up every file we are about to replace, then copy in
# ---------------------------------------------------------------------------------------
BDIR="$BACKUP/$CURRENT-$(date '+%Y%m%d%H%M%S')"
mkdir -p "$BDIR"
# preserve the current release tag so a rollback restores both the files AND the version
if [ -f "$RELFILE" ]; then
	mkdir -p "$BDIR/.system/rg353"
	cp -p "$RELFILE" "$BDIR/.system/rg353/anbernext-release.txt" 2>/dev/null
fi
say "AnberNext: applying $LATEST..."

( cd "$STAGE" && find . -type f ! -name 'anbernext-release.txt' ! -name 'MANIFEST.sha256' ) | while read -r f; do
	rel="${f#./}"
	dest="$SDCARD/$rel"
	# final paranoid check: dest must be inside SDCARD
	destdir="$(dirname "$dest")"
	mkdir -p "$destdir" 2>/dev/null
	rdd="$(cd "$destdir" 2>/dev/null && pwd -P)" || { echo "SKIP $rel"; continue; }
	case "$rdd/" in "$SDCARD/"*) : ;; *) echo "ESCAPE $rel"; continue;; esac
	# back up the existing file
	if [ -f "$dest" ]; then
		mkdir -p "$BDIR/$(dirname "$rel")" 2>/dev/null
		cp -p "$dest" "$BDIR/$rel" 2>/dev/null
	fi
	cp -p "$STAGE/$rel" "$dest" 2>>"$LOG"
done

# record the new version
printf '%s\n' "$LATEST" >"$RELFILE"
# human line for the About screen, keep it readable
printf '%s (atualizado pelo aparelho em %s)\n' "$LATEST" "$(date '+%Y-%m-%d')" >"$HUMANFILE"

# tidy the big download, keep the backup for rollback
rm -f "$ZIP" "$DL/update.zip.sha256"

sync
result "Updated to $LATEST. Backup kept at ${BDIR#$SDCARD/}. Restart to use it."
say "AnberNext updated to $LATEST — restart the device."
exit 0
