#!/usr/bin/env bash
# Compila libmpv (mpv + FFmpeg + dipendenze) in versione LGPL per Morph Audiophile.
#
# Parte da libmpv-android (lo stesso progetto del pacchetto dev.jdtech.mpv:libmpv usato oggi) e
# cambia solo due cose:
#   - FFmpeg senza --enable-gpl (resta --enable-version3, necessario per mbedtls: licenza LGPL v3);
#   - mpv con -Dgpl=false (licenza LGPL v2.1+).
# I decoder audio, i filtri audio e il ricampionamento sono gli stessi: la resa non cambia.
#
# Requisiti: Linux (o la CI di GitHub, vedi github-workflow.yml), git, wget, autoconf, pkgconf,
# libtool, ninja-build, meson, python3-jinja2, gperf, nasm, unzip, ANDROID_HOME impostata.
# Uso:   ./build-libmpv-lgpl.sh
# Esito: app/libs/libmpv-lgpl.aar e app/src/main/assets/licenses/third_party/*.txt
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$HERE/.." && pwd)"
REF="${LIBMPV_ANDROID_REF:-v1.0.0}"   # v1.0.0 = FFmpeg 8.1, mpv 0.41.0 (la versione usata oggi)
WORK="${WORK_DIR:-$HERE/work}"
LICENSES="$APP_ROOT/app/src/main/assets/licenses/third_party"

fail() { echo "ERRORE: $*" >&2; exit 1; }

mkdir -p "$WORK"
cd "$WORK"
[ -d libmpv-android ] || git clone https://github.com/jarnedemeulemeester/libmpv-android.git
cd libmpv-android
git fetch --tags --force
git checkout --force "$REF"
git checkout -- buildscripts/scripts

# 1. FFmpeg senza componenti GPL
f=buildscripts/scripts/ffmpeg.sh
grep -q -- '--enable-{gpl,version3}' "$f" || fail "$f è cambiato: aggiornare la modifica qui sotto"
sed -i 's/--enable-{gpl,version3}/--enable-version3/' "$f"
# libpostproc esiste solo nelle build GPL
sed -i '/libpostproc\.so/d' "$f"

# 2. mpv in modalità LGPL
f=buildscripts/scripts/mpv.sh
grep -q -- '-Dlibmpv=true' "$f" || fail "$f è cambiato: aggiornare la modifica qui sotto"
sed -i 's/-Dlibmpv=true/-Dlibmpv=true -Dgpl=false/' "$f"

# 3. Build, come nella CI del progetto
cd buildscripts
if [ ! -e sdk/android-sdk-linux ]; then
    mkdir -p sdk
    ln -s "${ANDROID_HOME:?ANDROID_HOME non impostata}" sdk/android-sdk-linux
fi
IN_CI=1 ./download.sh
./patch.sh
./build.sh
cd ..

AAR=libmpv/build/outputs/aar/libmpv-release.aar
[ -f "$AAR" ] || fail "AAR non prodotto: $AAR"

# 4. Verifica: nessuna libreria deve dichiararsi GPL, FFmpeg deve dichiararsi LGPL
CHECK="$(mktemp -d)"
unzip -q "$AAR" 'jni/*' -d "$CHECK"
if grep -raoE '(^|[^L])GPL version [0-9]' "$CHECK/jni" >/dev/null; then
    grep -raoE '[a-z]+ license: [^L]?GPL version [0-9][^[:cntrl:]]*' "$CHECK/jni" | sort -u >&2 || true
    fail "nella build c'è ancora codice GPL"
fi
grep -raq 'LGPL version' "$CHECK/jni" || fail "stringa di licenza LGPL di FFmpeg non trovata"
rm -rf "$CHECK"

# 5. Copia nell'app (app/build.gradle.kts usa questo file al posto del pacchetto Maven)
mkdir -p "$APP_ROOT/app/libs"
cp "$AAR" "$APP_ROOT/app/libs/libmpv-lgpl.aar"

# 6. Licenze originali dei sorgenti, mostrate nell'app (Impostazioni → Licenze open source)
mkdir -p "$LICENSES"
copy_license() { # id, file relativi a buildscripts/deps o alla radice del progetto (il primo trovato)
    local id="$1"; shift
    for f in "$@"; do
        if [ -f "$f" ]; then cp "$f" "$LICENSES/$id.txt"; echo "licenza $id <- $f"; return 0; fi
    done
    echo "ATTENZIONE: licenza di $id non trovata" >&2
}
D=buildscripts/deps
copy_license ffmpeg      $D/ffmpeg/LICENSE.md
copy_license mpv         $D/mpv/LICENSE.LGPL $D/mpv/Copyright
copy_license libplacebo  $D/libplacebo/LICENSE
copy_license fribidi     $D/fribidi/COPYING
copy_license libass      $D/libass/COPYING
copy_license freetype    $D/freetype/LICENSE.TXT
copy_license harfbuzz    $D/harfbuzz/COPYING
copy_license libxml2     $D/libxml2/Copyright
copy_license dav1d       $D/dav1d/COPYING
copy_license mbedtls     $D/mbedtls/LICENSE
copy_license fontconfig  $D/fontconfig/COPYING
copy_license libunibreak $D/libunibreak/LICENCE $D/libunibreak/LICENSE
copy_license libmpv-android LICENSE
# Lua: la licenza è in fondo a src/lua.h
if [ -f $D/lua/src/lua.h ]; then
    awk '/Copyright \(C\) 1994/{p=1} p{print} p&&/\*\//{exit}' $D/lua/src/lua.h > "$LICENSES/lua.txt"
else
    echo "ATTENZIONE: licenza di lua non trovata" >&2
fi

# 7. Versioni esatte usate, per l'offerta del sorgente
{
    echo "libmpv-android $REF ($(git rev-parse HEAD))"
    grep '^v_' buildscripts/include/depinfo.sh
} > "$HERE/work/libmpv-versions.txt"

echo
echo "Fatto: $APP_ROOT/app/libs/libmpv-lgpl.aar"
echo "Ora esegui build-media3-ffmpeg-lgpl.sh, poi make-source-offer.sh."
