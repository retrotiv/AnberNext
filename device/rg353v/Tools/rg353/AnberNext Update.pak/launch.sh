#!/bin/sh
# AnberNext Update.pak - atualizador pelo proprio aparelho (RG353V).
#
# Baixa a ultima versao do AnberNext (retrotiv/AnberNext) pelo Wi-Fi e aplica
# SOMENTE na particao do cartao de boot onde este pak vive. Nunca alcanca o
# cartao de jogos nem a memoria interna (Android) do console.
#
# Esta e de proposito a UNICA rota de atualizacao do AnberNext.
# O pacote e um .tar, aberto por um busybox embutido (sem unzip/gzip do aparelho).

set -u

REPO="retrotiv/AnberNext"
API="https://api.github.com/repos/${REPO}/releases/latest"
PAKDIR="$(cd "$(dirname "$0")" && pwd)"
ALLOWED_TOP=".system Tools Emus .tmp_update"

find_sdcard() {
	d="$PAKDIR"; i=0
	while [ "$i" -lt 8 ]; do
		if [ -d "$d/.system/rg353" ]; then printf '%s\n' "$d"; return 0; fi
		nd="$(dirname "$d")"; [ "$nd" = "$d" ] && break; d="$nd"; i=$((i + 1))
	done
	return 1
}
SDCARD="$(find_sdcard)" || SDCARD=""
[ -n "$SDCARD" ] && SDCARD="$(cd "$SDCARD" && pwd -P)"

# as copias embutidas podem perder o bit de execucao no FAT32; forca de volta
chmod 0755 "$PAKDIR/bin/show2.elf" "$PAKDIR/bin/busybox" 2>/dev/null

# tela via show2.elf (apresentador do NextUI, fonte embutida)
SHOW=""
for c in "$PAKDIR/bin/show2.elf" "$SDCARD/.system/rg353/bin/show2.elf" "$SDCARD/.tmp_update/rg353/show2.elf"; do
	[ -n "$c" ] && [ -f "$c" ] && { SHOW="$c"; break; }
done
if [ -z "$SHOW" ] && command -v show2.elf >/dev/null 2>&1; then SHOW="show2.elf"; fi
LOGO=""
for c in "$PAKDIR/res/logo.png" "$SDCARD/.system/res/logo.png" "$SDCARD/.system/rg353/res/logo.png"; do
	[ -n "$c" ] && [ -f "$c" ] && { LOGO="$c"; break; }
done
FIFO="/tmp/show2.fifo"; BG="0x1a1205"; FG="0xf2a53a"; UI_PID=""
ui_start() {
	[ -n "$SHOW" ] && [ -n "$LOGO" ] || return 0
	rm -f "$FIFO" 2>/dev/null
	"$SHOW" --mode=daemon --image="$LOGO" --bgcolor="$BG" --fontcolor="$FG" --text="$1" >/dev/null 2>&1 &
	UI_PID=$!
	n=0
	while [ "$n" -lt 15 ]; do [ -p "$FIFO" ] && break; sleep 0.2; n=$((n + 1)); done
}
ui_text() { [ -n "$UI_PID" ] && [ -p "$FIFO" ] && printf 'TEXT:%s\n' "$1" >"$FIFO" 2>/dev/null; return 0; }
ui_prog() { [ -n "$UI_PID" ] && [ -p "$FIFO" ] && printf 'PROGRESS:%s\n' "$1" >"$FIFO" 2>/dev/null; return 0; }
ui_stop() { [ -n "$UI_PID" ] || return 0; printf 'QUIT\n' >"$FIFO" 2>/dev/null; wait "$UI_PID" 2>/dev/null; UI_PID=""; }
ui_final() { ui_stop; [ -n "$SHOW" ] && [ -n "$LOGO" ] && "$SHOW" --mode=simple --image="$LOGO" --bgcolor="$BG" --fontcolor="$FG" --text="$1" --timeout="${2:-5}" >/dev/null 2>&1; return 0; }
trap 'ui_stop' EXIT INT TERM

# busybox embutido abre o .tar; achado por EXISTENCIA (nao por -x, que falha no FAT32)
BB=""
[ -f "$PAKDIR/bin/busybox" ] && BB="$PAKDIR/bin/busybox"
[ -z "$BB" ] && command -v busybox >/dev/null 2>&1 && BB="busybox"
HAVE_SHA=0; command -v sha256sum >/dev/null 2>&1 && HAVE_SHA=1

# abre o pacote entrando na pasta (sem depender do -C do tar)
extract_pkg() {
	src="$1"; dst="$2"
	case "$src" in
		*.tar)
			[ -n "$BB" ] && ( cd "$dst" && "$BB" tar -xf "$src" ) 2>>"$LOG" && return 0
			( cd "$dst" && tar -xf "$src" ) 2>>"$LOG" && return 0
			[ -n "$BB" ] && "$BB" tar -xf "$src" -C "$dst" 2>>"$LOG" && return 0
			return 1 ;;
		*.tar.gz|*.tgz)
			( cd "$dst" && tar -xzf "$src" ) 2>>"$LOG" && return 0
			if command -v gzip >/dev/null 2>&1 && [ -n "$BB" ]; then
				gzip -dc "$src" 2>>"$LOG" | ( cd "$dst" && "$BB" tar -xf - ) 2>>"$LOG" && return 0
			fi
			return 1 ;;
		*.zip)
			command -v unzip >/dev/null 2>&1 && ( cd "$dst" && unzip -oq "$src" ) 2>>"$LOG" && return 0
			return 1 ;;
	esac
	return 1
}

if [ -n "$SDCARD" ]; then LOGDIR="$SDCARD/.userdata/rg353/logs"; WORK="$SDCARD/.anbernext"; else LOGDIR="/tmp"; WORK="/tmp/.anbernext"; fi
DL="$WORK/download"; STAGE="$WORK/staging"; BACKUP="$WORK/backup"
RELFILE="$SDCARD/.system/rg353/anbernext-release.txt"
HUMANFILE="$SDCARD/.system/rg353/anbernext-version.txt"
RESULT="$WORK/last-result.txt"
mkdir -p "$LOGDIR" "$DL" "$STAGE" "$BACKUP" 2>/dev/null
LOG="$LOGDIR/anbernext-ota.log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG" 2>/dev/null; }
result() { printf '%s\n' "$*" >"$RESULT" 2>/dev/null; log "$*"; }

abort() { result "ABORTADO (seguranca): $*"; ui_final "Cartao do AnberNext nao confirmado. Nada mudou." 5; exit 1; }
[ -n "$SDCARD" ] || abort "nao localizei .system/rg353"
case "$SDCARD" in "" | "/" | "/mnt" | "/media" ) abort "caminho suspeito: '$SDCARD'";; esac
[ -d "$SDCARD/.system/rg353" ] || abort "'$SDCARD' nao e o cartao"
case "$SDCARD" in *sd2* | *SD2* | *mmcblk0* | *android* | *ANDROID* ) abort "recuso '$SDCARD'";; esac
for other in /mnt/sd2 /mnt/SDCARD2 /media/sd2; do
	[ -e "$other" ] || continue
	o="$(cd "$other" 2>/dev/null && pwd -P)" || continue
	[ "$o" = "$SDCARD" ] && abort "boot aponta para o cartao de jogos"
done

ui_start "AnberNext: procurando atualizacao..."

if command -v curl >/dev/null 2>&1; then GET="curl -fsSL --connect-timeout 15 -o"; GETS="curl -fsSL --connect-timeout 15";
elif command -v wget >/dev/null 2>&1; then GET="wget -q -O"; GETS="wget -q -O -";
else result "sem curl/wget"; ui_final "Falta rede no aparelho." 6; exit 1; fi

ui_prog 5
$GETS "https://api.github.com" >/dev/null 2>&1 || { result "sem internet"; ui_final "Sem internet. Ligue o Wi-Fi." 6; exit 0; }

ui_text "Lendo a ultima versao..."
ui_prog 10
JSON="$DL/latest.json"
$GET "$JSON" "$API" 2>>"$LOG" || { result "server inacessivel"; ui_final "Servidor fora. Tente depois." 6; exit 0; }

LATEST="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$JSON" | head -1)"
[ -n "$LATEST" ] || { result "nenhuma release"; ui_final "Nenhuma versao encontrada." 6; exit 0; }

CURRENT="desconhecida"
[ -f "$RELFILE" ] && CURRENT="$(tr -d ' \t\r\n' <"$RELFILE")"
log "current=$CURRENT latest=$LATEST"
if [ "$CURRENT" = "$LATEST" ]; then
	result "ja atualizado ($CURRENT)"
	ui_final "Ja esta na versao $CURRENT." 5
	exit 0
fi

pick_asset() { grep -o '"browser_download_url"[^,]*' "$JSON" | sed 's/.*"\(https[^"]*\)".*/\1/' | grep -iE "$1" | head -1; }
PKG_URL="$(pick_asset 'update\.tar$')"; PKG_EXT="tar"; SHA_URL="$(pick_asset 'update\.tar\.sha256$')"
if [ -z "$PKG_URL" ]; then PKG_URL="$(pick_asset 'update\.tar\.gz$')"; PKG_EXT="tar.gz"; SHA_URL="$(pick_asset 'update\.tar\.gz\.sha256$')"; fi
if [ -z "$PKG_URL" ]; then PKG_URL="$(pick_asset 'update\.zip$')"; PKG_EXT="zip"; SHA_URL="$(pick_asset 'update\.zip\.sha256$')"; fi
[ -n "$PKG_URL" ] || { result "release sem pacote"; ui_final "Versao $LATEST sem pacote." 6; exit 0; }

ui_text "Baixando $LATEST..."
ui_prog 20
PKG="$DL/update.$PKG_EXT"
rm -f "$PKG"
$GET "$PKG" "$PKG_URL" 2>>"$LOG" || { result "download falhou"; ui_final "Download falhou. Veja o Wi-Fi." 6; exit 0; }
ui_prog 55

if [ "$HAVE_SHA" -eq 1 ] && [ -n "$SHA_URL" ]; then
	ui_text "Verificando..."
	$GET "$DL/pkg.sha256" "$SHA_URL" 2>>"$LOG"
	WANT="$(awk '{print $1}' "$DL/pkg.sha256" | head -1)"
	HAVE="$(sha256sum "$PKG" | awk '{print $1}')"
	if [ -n "$WANT" ] && [ "$WANT" != "$HAVE" ]; then
		result "checksum nao bate (want $WANT got $HAVE)"
		ui_final "Download corrompido. Tente de novo." 6
		exit 1
	fi
	log "checksum ok ($HAVE)"
else
	log "sem sha256sum ou sem hash; seguindo (HTTPS)"
fi
ui_prog 65

rm -rf "$STAGE"; mkdir -p "$STAGE"
if ! extract_pkg "$PKG" "$STAGE"; then
	err="$(tail -1 "$LOG" 2>/dev/null)"
	result "FALHA AO ABRIR ($PKG_EXT) BB='$BB' tar=$(command -v tar 2>/dev/null): $err"
	ui_final "Nao abriu o pacote. Detalhe no cartao." 7
	exit 1
fi

PKG_TAG=""
[ -f "$STAGE/anbernext-release.txt" ] && PKG_TAG="$(tr -d ' \t\r\n' <"$STAGE/anbernext-release.txt")"
[ "$PKG_TAG" = "$LATEST" ] || { result "tag '$PKG_TAG' != '$LATEST'"; ui_final "Pacote nao confere. Nada mudou." 6; exit 1; }

( cd "$STAGE" && find . -type f ! -name 'anbernext-release.txt' ! -name 'MANIFEST.sha256' ) | while read -r f; do
	rel="${f#./}"
	case "$rel" in
		/*) echo "ABSOLUTE:$rel";;
		*..*) echo "DOTDOT:$rel";;
		*) top="${rel%%/*}"; case " $ALLOWED_TOP " in *" $top "*) : ;; *) echo "OUTSIDE:$rel";; esac;;
	esac
done >"$DL/pathcheck.txt"
if [ -s "$DL/pathcheck.txt" ]; then
	result "caminhos inseguros: $(head -3 "$DL/pathcheck.txt" | tr '\n' ' ')"
	ui_final "Pacote com caminho invalido. Recusado." 6
	exit 1
fi

if [ "$HAVE_SHA" -eq 1 ] && [ -f "$STAGE/MANIFEST.sha256" ]; then
	( cd "$STAGE" && sha256sum -c MANIFEST.sha256 ) >>"$LOG" 2>&1 || { result "manifest falhou"; ui_final "Arquivo nao conferiu. Recusado." 6; exit 1; }
	log "manifesto verificado"
fi
ui_prog 80

ui_text "Aplicando $LATEST..."
BDIR="$BACKUP/$CURRENT-$(date '+%Y%m%d%H%M%S')"
mkdir -p "$BDIR"
if [ -f "$RELFILE" ]; then mkdir -p "$BDIR/.system/rg353"; cp -p "$RELFILE" "$BDIR/.system/rg353/anbernext-release.txt" 2>/dev/null; fi

( cd "$STAGE" && find . -type f ! -name 'anbernext-release.txt' ! -name 'MANIFEST.sha256' ) | while read -r f; do
	rel="${f#./}"
	dest="$SDCARD/$rel"
	destdir="$(dirname "$dest")"
	mkdir -p "$destdir" 2>/dev/null
	rdd="$(cd "$destdir" 2>/dev/null && pwd -P)" || { echo "SKIP $rel"; continue; }
	case "$rdd/" in "$SDCARD/"*) : ;; *) echo "ESCAPE $rel"; continue;; esac
	if [ -f "$dest" ]; then mkdir -p "$BDIR/$(dirname "$rel")" 2>/dev/null; cp -p "$dest" "$BDIR/$rel" 2>/dev/null; fi
	cp -p "$STAGE/$rel" "$dest" 2>>"$LOG"
done
ui_prog 95

printf '%s\n' "$LATEST" >"$RELFILE"
printf '%s (atualizado pelo aparelho em %s)\n' "$LATEST" "$(date '+%Y-%m-%d')" >"$HUMANFILE"
rm -f "$PKG"
sync
ui_prog 100
result "atualizado para $LATEST (backup em ${BDIR#$SDCARD/})"
ui_final "Atualizado para $LATEST. Reinicie." 6
exit 0
