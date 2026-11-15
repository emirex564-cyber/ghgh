#!/bin/bash
# macvm-fix.sh - Stela v0.4.2'yi indirir, dogrular, acar ve calistirir.
#
#   bash macvm-fix.sh            -> Stela'yi baslat (USB secip macOS kurulum USB'si yapar)
#   bash macvm-fix.sh update     -> mevcut Stela USB'sini guncelle
#   bash macvm-fix.sh log        -> acilis kaydini log.txt olarak kaydet
#   (Stela'nin diger komutlari da aynen gecer: status, repair, settings ...)
#
# DIKKAT: "create" secilen USB'yi TAMAMEN SILER.
set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

VER=v0.4.2
NAME="stela-${VER}-linux-x86_64"
URL="https://github.com/tylertms/Stela/releases/download/${VER}/${NAME}.tar.gz"
SHA256="d0c374d388de8d4859b7ea173f0be8599edcf943ffadd47b7d2369abfffcfa99"
DIR=/root/stela

say()  { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[uyari] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[hata] %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "root olarak calistir:  su -c \"bash $0\""
[[ $(uname -m) == x86_64 ]] || die "Bu Stela surumu sadece x86_64 Linux icin."

# ---------------------------------------------------------------- araclar
need=()
for c in curl tar sha256sum lsblk lspci; do command -v "$c" >/dev/null || need+=("$c"); done
if (( ${#need[@]} )); then
  say "Eksik araclar kuruluyor: ${need[*]}"
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl tar coreutils util-linux pciutils >/dev/null
fi

# ---------------------------------------------------------------- indir + dogrula + ac
mkdir -p "$DIR"
TGZ="$DIR/${NAME}.tar.gz"
if [[ -x $DIR/$NAME/stela ]] && echo "$SHA256  $TGZ" | sha256sum -c --status 2>/dev/null; then
  say "Stela ${VER} zaten indirilmis: $DIR/$NAME"
else
  say "Stela ${VER} indiriliyor (~22 MB)"
  curl -fL --retry 3 -o "$TGZ.part" "$URL" || die "indirilemedi: $URL"
  mv "$TGZ.part" "$TGZ"
  echo "$SHA256  $TGZ" | sha256sum -c --status || { rm -f "$TGZ"; die "SHA-256 tutmadi, dosya bozuk ya da degistirilmis. Tekrar dene."; }
  echo "  SHA-256 dogrulandi"
  say "Arsiv aciliyor: $DIR/$NAME"
  rm -rf "${DIR:?}/$NAME"
  tar -xzf "$TGZ" -C "$DIR"
  chmod +x "$DIR/$NAME/stela"
fi
"$DIR/$NAME/stela" --version >/dev/null 2>&1 || die "stela calismiyor (bozuk indirme olabilir): $DIR/$NAME/stela"

# ---------------------------------------------------------------- donanim kontrolu
say "Donanim kontrolu"
gpus=$(lspci -nn | grep -iE "vga|3d controller|display" || true)
echo "$gpus" | sed 's/^/  /'
if echo "$gpus" | grep -qi "nvidia"; then
  id=$(echo "$gpus" | grep -i nvidia | grep -oE '10de:[0-9a-f]{4}' | head -n1 | cut -d: -f2)
  dec=$((16#${id:-0}))
  if (( (dec>=0x1e00 && dec<=0x1fff) || (dec>=0x2180 && dec<=0x2fff) )); then
    echo "  NVIDIA karti ($id) Stela'nin destekledigi aileler arasinda."
  else
    warn "NVIDIA karti ($id) Stela'nin destekledigi aileler arasinda gorunmuyor."
  fi
else
  warn "Bu bilgisayarda NVIDIA ekran karti YOK. Stela goruntu icin NVIDIA GTX 16 / RTX 20+ ister;"
  warn "USB hazirlanir ama bu laptopta macOS ekrani GELMEZ (USB'yi NVIDIA'li baska bir PC'de kullanabilirsin)."
fi
warn "Stela'da touchpad (I2C), Wi-Fi, Bluetooth ve ses desteklenmiyor: USB fare ve kablolu internet gerekir."

say "Takili USB diskler"
lsblk -d -o NAME,SIZE,MODEL,TRAN,RM | awk 'NR==1 || /usb/' | sed 's/^/  /'
lsblk -d -o TRAN | grep -q usb || warn "USB bellek gorunmuyor. En az 8 GB (Offline icin 32 GB) bir USB tak, sonra tekrar calistir."

# ---------------------------------------------------------------- calistir
[[ ${MACVM_NO_RUN:-0} == 1 ]] && { echo "MACVM_NO_RUN=1: stela calistirilmadi"; exit 0; }
say "Stela baslatiliyor. USB'yi ve kurulum tipini sec. 'create' secilen USB'yi SILER."
cd "$DIR/$NAME"
exec ./stela "$@"
