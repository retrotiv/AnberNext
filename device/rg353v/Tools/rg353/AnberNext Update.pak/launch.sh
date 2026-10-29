#!/bin/sh
# AnberNext Update.pak - atualizador pelo proprio aparelho (RG353V).
#
# Baixa a ultima versao do AnberNext (retrotiv/AnberNext) pelo Wi-Fi e aplica
# SOMENTE na particao do cartao de boot onde este pak vive. Nunca alcanca o
# cartao de jogos nem a memoria interna (Android) do console - ver as travas
# de seguranca abaixo.
#
# Esta e de proposito a UNICA rota de atualizacao do AnberNext: nao usamos o
# auto-update do NextUI original. A rota aponta para o repositorio do projeto.

set -u

# ---------------------------------------------------------------------------------------
# onde as coisas estao
# ---------------------------------------------------------------------------------------
REPO="retrotiv/AnberNext"
API="https://api.github.com/repos/${REPO}/releases/latest"

PAKDIR="$(cd "$(dirname "$0")" && pwd)"

# As pastas de topo que uma release pode tocar. Qualquer coisa fora disso e recusada.
ALLOWED_TOP=".system Tools Emus .tmp_update"

# ---------------------------------------------------------------------------------------
# achar a raiz do cartao de boot e provar que e o cartao de boot, nada mais
# ---------------------------------------------------------------------------------------
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

SDCARD="$(find_sdcard)" || SDCARD=""
[ -n "$SDCARD" ] && SDCARD="$(cd "$SDCARD" && pwd -P)"

# ---------------------------------------------------------------------------------------
# tela: usa o show2.elf (apresentador do proprio NextUI, com fonte embutida).
# Tenta primeiro a copia embutida no pak (autossuficiente), depois as do sistema,
# depois o PATH. Se nenhum existir, cai so no log, mas nunca trava.
# ---------------------------------------------------------------------------------------
SHOW=""
for c in "$PAKDIR/bin/show2.elf" \
         "$SDCARD/.system/rg353/bin/show2.elf" \
         "$SDCARD/.tmp_update/rg353/show2.elf"; do
	[ -n "$c" ] && [ -x "$c" ] && { SHOW="$c"; break; }
done
if [ -z "$SHOW" ] && command -v show2.elf >/dev/null 2>&1; then SHOW="show2.elf"; fi

LOGO=""
for c in "$PAKDIR/res/logo.png" \
         "$SDCARD/.system/res/logo.png" \
         "$SDCARD/.system/rg353/res/logo.png"; do
	[ -n "$c" ] && [ -f "$c" ] && { LOGO="$c"; break; }
done

FIFO="/tmp/show2.fifo"
BG="0x1a1205"
FG="0xf2a53a"
UI_PID=""

ui_start() {   # tela de progresso que fica no ar o tempo todo
	[ -n "$SHOW" ] && [ -n "$LOGO" ] || return 0
	rm -f "$FIFO" 2>/dev/null
	"$SHOW" --mode=daemon --image="$LOGO" --bgcolor="$BG" --fontcolor="$FG" --text="$1" >/dev/null 2>&1 &
	UI_PID=$!
	n=0
	while [ "$n" -lt 15 ]; do
		[ -p "$FIFO" ] && break
		sleep 0.2
		n=$((n + 1))
	done
}
ui_text() { [ -n "$UI_PID" ] && [ -p "$FIFO" ] && printf 'TEXT:%s\n' "$1" >"$FIFO" 2>/dev/null; return 0; }
ui_prog() { [ -n "$UI_PID" ] && [ -p "$FIFO" ] && printf 'PROGRESS:%s\n' "$1" >"$FIFO" 2>/dev/null; return 0; }
ui_stop() {
	[ -n "$UI_PID" ] || return 0
	printf 'QUIT\n' >"$FIFO" 2>/dev/null
	wait "$UI_PID" 2>/dev/null
	UI_PID=""
}
# mensagem final de tela cheia que o usuario le, depois volta ao menu
ui_final() {
	ui_stop
	[ -n "$SHOW" ] && [ -n "$LOGO" ] || return 0
	"$SHOW" --mode=simple --image="$LOGO" --bgcolor="$BG" --fontcolor="$FG" --text="$1" --timeout="${2:-4}" >/dev/null 2>&1
}
trap 'ui_stop' EXIT INT TERM

# ---------------------------------------------------------------------------------------
# log / resultado (diagnostico, alem da tela)
# ---------------------------------------------------------------------------------------
if [ -n "$SDCARD" ]; then
	LOGDIR="$SDCARD/.userdata/rg353/logs"
	WORK="$SDCARD/.anbernext"
else
	LOGDIR="/tmp"; WORK="/tmp/.anbernext"
fi
DL="$WORK/download"
STAGE="$WORK/staging"
BACKUP="$WORK/backup"
RELFILE="$SDCARD/.system/rg353/anbernext-release.txt"
HUMANFILE="$SDCARD/.system/rg353/anbernext-version.txt"
RESULT="$WORK/last-result.txt"
mkdir -p "$LOGDIR" "$DL" "$STAGE" "$BACKUP" 2>/dev/null
LOG="$LOGDIR/anbernext-ota.log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG" 2>/dev/null; }
result() { printf '%s\n' "$*" >"$RESULT" 2>/dev/null; log "$*"; }

# ---------------------------------------------------------------------------------------
# TRAVAS DE SEGURANCA - so roda se o alvo for provadamente o cartao de boot
# ---------------------------------------------------------------------------------------
abort() { result "ABORTADO (seguranca): $*"; ui_final "Nao consegui achar o cartao do AnberNext com seguranca. Nada foi alterado." 5; exit 1; }

[ -n "$SDCARD" ] || abort "nao localizei o cartao de boot (.system/rg353)"
case "$SDCARD" in
	"" | "/" | "/mnt" | "/media" ) abort "caminho do cartao suspeito: '$SDCARD'";;
esac
[ -d "$SDCARD/.system/rg353" ] || abort "'$SDCARD' nao e o cartao do AnberNext"
case "$SDCARD" in
	*sd2* | *SD2* | *mmcblk0* | *android* | *ANDROID* ) abort "recuso tocar em '$SDCARD'";;
esac
for other in /mnt/sd2 /mnt/SDCARD2 /media/sd2; do
	[ -e "$other" ] || continue
	o="$(cd "$other" 2>/dev/null && pwd -P)" || continue
	[ "$o" = "$SDCARD" ] && abort "o cartao de boot aponta para o de jogos ($other)"
done

# ---------------------------------------------------------------------------------------
# tela inicial - a partir daqui sempre ha algo visivel
# ---------------------------------------------------------------------------------------
ui_start "AnberNext: procurando atualizacao..."

# ---------------------------------------------------------------------------------------
# ferramentas
# ---------------------------------------------------------------------------------------
if command -v curl >/dev/null 2>&1; then GET="curl -fsSL --connect-timeout 15 -o"; GETS="curl -fsSL --connect-timeout 15";
elif command -v wget >/dev/null 2>&1; then GET="wget -q -O"; GETS="wget -q -O -";
else result "sem curl/wget"; ui_final "Faltam ferramentas de rede no aparelho. Atualize por outra via." 6; exit 1; fi
command -v unzip >/dev/null 2>&1 || { result "sem unzip"; ui_final "Falta o unzip no aparelho." 6; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { result "sem sha256sum"; ui_final "Falta o sha256sum no aparelho." 6; exit 1; }

# ---------------------------------------------------------------------------------------
# checar rede
# ---------------------------------------------------------------------------------------
ui_prog 5
$GETS "https://api.github.com" >/dev/null 2>&1 || { result "sem internet"; ui_final "Sem internet. Conecte o Wi-Fi e tente de novo." 6; exit 0; }

# ---------------------------------------------------------------------------------------
# ler a ultima release
# ---------------------------------------------------------------------------------------
ui_text "Lendo a ultima versao publicada..."
ui_prog 10
JSON="$DL/latest.json"
$GET "$JSON" "$API" 2>>"$LOG" || { result "release server inacessivel"; ui_final "Nao consegui falar com o servidor de versoes. Tente mais tarde." 6; exit 0; }

LATEST="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$JSON" | head -1)"
[ -n "$LATEST" ] || { result "nenhuma release"; ui_final "Nenhuma versao encontrada ainda." 6; exit 0; }

ZIP_URL="$(grep -o '"browser_download_url"[^,]*' "$JSON" | sed 's/.*"\(https[^"]*\)".*/\1/' | grep -i 'update\.zip$' | head -1)"
SHA_URL="$(grep -o '"browser_download_url"[^,]*' "$JSON" | sed 's/.*"\(https[^"]*\)".*/\1/' | grep -i 'update\.zip\.sha256$' | head -1)"
[ -n "$ZIP_URL" ] || { result "release sem pacote"; ui_final "A versao $LATEST ainda nao tem pacote de atualizacao." 6; exit 0; }

CURRENT="desconhecida"
[ -f "$RELFILE" ] && CURRENT="$(tr -d ' \t\r\n' <"$RELFILE")"
log "current=$CURRENT latest=$LATEST"
if [ "$CURRENT" = "$LATEST" ]; then
	result "ja atualizado ($CURRENT)"
	ui_final "Ja esta na versao mais nova ($CURRENT)." 5
	exit 0
fi

# ---------------------------------------------------------------------------------------
# baixar + verificar
# ---------------------------------------------------------------------------------------
ui_text "Baixando $LATEST..."
ui_prog 20
ZIP="$DL/update.zip"
rm -f "$ZIP"
$GET "$ZIP" "$ZIP_URL" 2>>"$LOG" || { result "download falhou"; ui_final "O download falhou. Verifique o Wi-Fi e tente de novo." 6; exit 0; }
ui_prog 55

if [ -z "$SHA_URL" ]; then
	result "sem checksum"
	ui_final "A versao $LATEST nao trouxe verificacao. Por seguranca, nao apliquei." 6
	exit 1
fi
ui_text "Verificando o download..."
$GET "$DL/update.zip.sha256" "$SHA_URL" 2>>"$LOG"
WANT="$(awk '{print $1}' "$DL/update.zip.sha256" | head -1)"
HAVE="$(sha256sum "$ZIP" | awk '{print $1}')"
if [ -z "$WANT" ] || [ "$WANT" != "$HAVE" ]; then
	result "checksum nao bate (want $WANT got $HAVE)"
	ui_final "O arquivo baixado nao conferiu. Nada foi alterado. Tente de novo." 6
	exit 1
fi
log "checksum ok ($HAVE)"
ui_prog 65

# ---------------------------------------------------------------------------------------
# extrair e validar TODOS os caminhos antes de tocar no cartao
# ---------------------------------------------------------------------------------------
rm -rf "$STAGE"; mkdir -p "$STAGE"
unzip -oq "$ZIP" -d "$STAGE" 2>>"$LOG" || { result "unzip falhou"; ui_final "Nao consegui abrir o pacote. Tente de novo." 6; exit 1; }

PKG_TAG=""
[ -f "$STAGE/anbernext-release.txt" ] && PKG_TAG="$(tr -d ' \t\r\n' <"$STAGE/anbernext-release.txt")"
[ "$PKG_TAG" = "$LATEST" ] || { result "tag do pacote '$PKG_TAG' != release '$LATEST'"; ui_final "O pacote nao confere com a versao. Nada foi alterado." 6; exit 1; }

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
	result "caminhos inseguros: $(head -3 "$DL/pathcheck.txt" | tr '\n' ' ')"
	ui_final "O pacote tinha caminhos fora do permitido. Recusado, nada mudou." 6
	exit 1
fi

if [ -f "$STAGE/MANIFEST.sha256" ]; then
	( cd "$STAGE" && sha256sum -c MANIFEST.sha256 ) >>"$LOG" 2>&1 || { result "manifest falhou"; ui_final "Um arquivo do pacote nao conferiu. Recusado, nada mudou." 6; exit 1; }
	log "manifesto por arquivo verificado"
fi
ui_prog 80

# ---------------------------------------------------------------------------------------
# aplicar: faz backup de cada arquivo que vai trocar, depois copia
# ---------------------------------------------------------------------------------------
ui_text "Aplicando $LATEST..."
BDIR="$BACKUP/$CURRENT-$(date '+%Y%m%d%H%M%S')"
mkdir -p "$BDIR"
if [ -f "$RELFILE" ]; then
	mkdir -p "$BDIR/.system/rg353"
	cp -p "$RELFILE" "$BDIR/.system/rg353/anbernext-release.txt" 2>/dev/null
fi

( cd "$STAGE" && find . -type f ! -name 'anbernext-release.txt' ! -name 'MANIFEST.sha256' ) | while read -r f; do
	rel="${f#./}"
	dest="$SDCARD/$rel"
	destdir="$(dirname "$dest")"
	mkdir -p "$destdir" 2>/dev/null
	rdd="$(cd "$destdir" 2>/dev/null && pwd -P)" || { echo "SKIP $rel"; continue; }
	case "$rdd/" in "$SDCARD/"*) : ;; *) echo "ESCAPE $rel"; continue;; esac
	if [ -f "$dest" ]; then
		mkdir -p "$BDIR/$(dirname "$rel")" 2>/dev/null
		cp -p "$dest" "$BDIR/$rel" 2>/dev/null
	fi
	cp -p "$STAGE/$rel" "$dest" 2>>"$LOG"
done
ui_prog 95

printf '%s\n' "$LATEST" >"$RELFILE"
printf '%s (atualizado pelo aparelho em %s)\n' "$LATEST" "$(date '+%Y-%m-%d')" >"$HUMANFILE"

rm -f "$ZIP" "$DL/update.zip.sha256"
sync
ui_prog 100
result "atualizado para $LATEST (backup em ${BDIR#$SDCARD/})"
ui_final "Atualizado para $LATEST. Reinicie o aparelho para usar." 6
exit 0
