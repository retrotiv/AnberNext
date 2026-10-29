#!/bin/sh
# AnberNext Rollback.pak - restaura o backup mais recente feito pelo AnberNext Update.pak.
# Mesma trava de seguranca: so escreve no cartao de boot onde este pak vive.

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
SDCARD="$(find_sdcard)" || SDCARD=""
[ -n "$SDCARD" ] && SDCARD="$(cd "$SDCARD" && pwd -P)"

# tela via show2.elf (apresentador do NextUI, fonte embutida); copia do pak primeiro
SHOW=""
for c in "$PAKDIR/bin/show2.elf" "$SDCARD/.system/rg353/bin/show2.elf" "$SDCARD/.tmp_update/rg353/show2.elf"; do
	[ -n "$c" ] && [ -x "$c" ] && { SHOW="$c"; break; }
done
if [ -z "$SHOW" ] && command -v show2.elf >/dev/null 2>&1; then SHOW="show2.elf"; fi
LOGO=""
for c in "$PAKDIR/res/logo.png" "$SDCARD/.system/res/logo.png" "$SDCARD/.system/rg353/res/logo.png"; do
	[ -n "$c" ] && [ -f "$c" ] && { LOGO="$c"; break; }
done
BG="0x1a1205"; FG="0xf2a53a"
ui_msg() { [ -n "$SHOW" ] && [ -n "$LOGO" ] && "$SHOW" --mode=simple --image="$LOGO" --bgcolor="$BG" --fontcolor="$FG" --text="$1" --timeout="${2:-5}" >/dev/null 2>&1; return 0; }

case "$SDCARD" in "" | "/" | *sd2* | *mmcblk0* | *android* ) ui_msg "Nao achei o cartao do AnberNext com seguranca. Nada mudou." 6; exit 1;; esac
[ -d "$SDCARD/.system/rg353" ] || { ui_msg "Este nao e o cartao do AnberNext. Nada mudou." 6; exit 1; }

WORK="$SDCARD/.anbernext"; BACKUP="$WORK/backup"
LOG="$SDCARD/.userdata/rg353/logs/anbernext-ota.log"
RESULT="$WORK/last-result.txt"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] rollback: $*" >>"$LOG" 2>/dev/null; }
result() { printf '%s\n' "$*" >"$RESULT" 2>/dev/null; log "$*"; }

ui_msg "AnberNext: voltando para a versao anterior..." 2 &

# pasta de backup mais nova
LAST="$(ls -1dt "$BACKUP"/*/ 2>/dev/null | head -1)"
[ -n "$LAST" ] && [ -d "$LAST" ] || { result "nenhum backup para restaurar"; ui_msg "Nao ha backup anterior para voltar." 6; exit 0; }
LAST="${LAST%/}"

log "restaurando de $LAST"
( cd "$LAST" && find . -type f ) | while read -r f; do
	rel="${f#./}"
	dest="$SDCARD/$rel"
	destdir="$(dirname "$dest")"
	mkdir -p "$destdir" 2>/dev/null
	rdd="$(cd "$destdir" 2>/dev/null && pwd -P)" || continue
	case "$rdd/" in "$SDCARD/"*) : ;; *) continue;; esac
	cp -p "$LAST/$rel" "$dest" 2>>"$LOG"
done

[ -f "$LAST/.system/rg353/anbernext-release.txt" ] && cp -p "$LAST/.system/rg353/anbernext-release.txt" "$SDCARD/.system/rg353/anbernext-release.txt" 2>/dev/null

sync
result "voltou de ${LAST#$SDCARD/}"
ui_msg "Pronto. Voltei para a versao anterior. Reinicie o aparelho." 6
exit 0
