#!/usr/bin/env bash
# Compila libmpv (mpv + FFmpeg + dipendenze) in versione LGPL per Morph Audiophile.
#
# Parte da libmpv-android (lo stesso progetto del pacchetto dev.jdtech.mpv:libmpv usato oggi) e
# cambia solo due cose:
#   - FFmpeg senza --enable-gpl (resta --enable-version3, necessario per mbedtls: licenza LGPL v3);
#   - mpv con -Dgpl=false (licenza LGPL v2.1+).
# In più (rispetto a libmpv-android) abilita i filtri audio usati da Morph e aggiunge libsoxr e libbs2b:
# libmpv-android compila FFmpeg con --disable-filters e il DSP di Morph su libmpv non funzionava.
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
git checkout -- buildscripts/scripts buildscripts/include

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

# 2b. Filtri audio e resampler usati da Morph su libmpv (AudioFx.mpvAudioFilter, MpvEngine.applyResampler).
#     libmpv-android compila FFmpeg con --disable-filters: restano solo aresample/aformat e mpv rifiuta in
#     silenzio EQ, crossfeed, FIR, HDCD, de-enfasi, accordatura e limitatore (verificato 2026-10-17).
#     Si riabilitano solo i filtri che servono, più libsoxr (LGPL 2.1+) e libbs2b (MIT): niente GPL.
f=buildscripts/scripts/ffmpeg.sh
grep -q -- '--disable-v4l2-m2m' "$f" || fail "$f è cambiato: aggiornare la modifica dei filtri"
FILTERS="aformat,aresample,anull,abuffer,abuffersink,volume,equalizer,bass,treble,bs2b,afir,amovie,hdcd,aemphasis,alimiter,asetrate,atempo"
sed -i "s/--disable-v4l2-m2m/--disable-v4l2-m2m --enable-filter=$FILTERS --enable-libsoxr --enable-libbs2b --extra-libs=-lm/" "$f"

f=buildscripts/include/depinfo.sh
grep -q '^dep_ffmpeg=(mbedtls dav1d libxml2)$' "$f" || fail "$f è cambiato: aggiornare le dipendenze di FFmpeg"
sed -i 's/^dep_ffmpeg=(mbedtls dav1d libxml2)$/dep_ffmpeg=(mbedtls dav1d libxml2 soxr libbs2b)/' "$f"
cat >> "$f" <<'EOF'

# Aggiunte da Morph (build-libmpv-lgpl.sh)
v_soxr=0.1.3
v_libbs2b=3.1.0
dep_soxr=()
dep_libbs2b=()
EOF

# libsoxr: CMake con il toolchain dell'NDK, libreria statica (finisce dentro libswresample.so)
cat > buildscripts/scripts/soxr.sh <<'EOF'
#!/bin/bash -e

. ../../include/depinfo.sh
. ../../include/path.sh

if [ "$1" == "build" ]; then
	true
elif [ "$1" == "clean" ]; then
	rm -rf _build$ndk_suffix
	exit 0
else
	exit 255
fi

cmake_bin="$ANDROID_HOME/cmake/$v_cmake/bin/cmake"
[ -x "$cmake_bin" ] || cmake_bin=cmake

rm -rf _build$ndk_suffix
mkdir -p _build$ndk_suffix
cd _build$ndk_suffix

# CMake 4 rifiuta cmake_minimum_required < 3.5 (soxr dichiara 3.1). Si installa direttamente nel prefisso:
# con prefisso "/" più DESTDIR CMake costruisce "//share/doc" e lo rifiuta come percorso di rete.
# FFmpeg cerca soxr con soxr.h e -lsoxr, non con pkg-config: il percorso assoluto nel soxr.pc non conta.
"$cmake_bin" .. -G Ninja \
	-DCMAKE_TOOLCHAIN_FILE="$ANDROID_HOME/ndk/$v_ndk/build/cmake/android.toolchain.cmake" \
	-DANDROID_ABI="$(basename "$prefix_dir")" -DANDROID_PLATFORM=android-26 \
	-DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix_dir" -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
	-DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=OFF \
	-DBUILD_TESTS=OFF -DBUILD_EXAMPLES=OFF -DWITH_OPENMP=OFF -DWITH_LSR_BINDINGS=OFF -DWITH_DEV_TRACE=OFF

"$cmake_bin" --build . -j$cores
"$cmake_bin" --install .
EOF

# libbs2b: il configure pretende libsndfile (solo per i programmi di esempio), quindi si compila a mano
# l'unico sorgente della libreria e si scrive il .pc che il configure di FFmpeg cerca
cat > buildscripts/scripts/libbs2b.sh <<'EOF'
#!/bin/bash -e

. ../../include/depinfo.sh
. ../../include/path.sh

if [ "$1" == "build" ]; then
	true
elif [ "$1" == "clean" ]; then
	rm -rf _build$ndk_suffix
	exit 0
else
	exit 255
fi

rm -rf _build$ndk_suffix
mkdir -p _build$ndk_suffix

$CC -O2 -fPIC -Isrc -c src/bs2b.c -o _build$ndk_suffix/bs2b.o
$AR rcs _build$ndk_suffix/libbs2b.a _build$ndk_suffix/bs2b.o

mkdir -p "$prefix_dir/lib/pkgconfig" "$prefix_dir/include/bs2b"
cp _build$ndk_suffix/libbs2b.a "$prefix_dir/lib/"
cp src/bs2b.h src/bs2bversion.h src/bs2btypes.h "$prefix_dir/include/bs2b/"
cat > "$prefix_dir/lib/pkgconfig/libbs2b.pc" <<PC
prefix=/
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libbs2b
Description: Bauer stereophonic-to-binaural DSP library
Version: $v_libbs2b
Libs: -L\${libdir} -lbs2b
Libs.private: -lm
Cflags: -I\${includedir}/bs2b
PC
EOF
chmod +x buildscripts/scripts/soxr.sh buildscripts/scripts/libbs2b.sh

# 3. Build, come nella CI del progetto
cd buildscripts
if [ ! -e sdk/android-sdk-linux ]; then
    mkdir -p sdk
    ln -s "${ANDROID_HOME:?ANDROID_HOME non impostata}" sdk/android-sdk-linux
fi
IN_CI=1 ./download.sh

# Sorgenti di libsoxr e libbs2b: archivi originali dal mirror Debian (stabile), SourceForge come riserva
fetch_tarball() { # cartella, URL...
    local dir="deps/$1"; shift
    [ -d "$dir" ] && return 0
    mkdir -p "$dir"
    local tmp
    tmp="$(mktemp)"
    for url in "$@"; do
        # tar riconosce la compressione (xz/gz) solo da un file, non da una pipe
        if wget -q -O "$tmp" "$url" && tar -xf "$tmp" -C "$dir" --strip-components=1; then rm -f "$tmp"; return 0; fi
        rm -rf "$dir"; mkdir -p "$dir"
    done
    rm -f "$tmp"
    fail "download di $dir non riuscito"
}
fetch_tarball soxr \
    "http://deb.debian.org/debian/pool/main/libs/libsoxr/libsoxr_0.1.3.orig.tar.xz" \
    "https://downloads.sourceforge.net/project/soxr/soxr-0.1.3-Source.tar.xz"
fetch_tarball libbs2b \
    "http://deb.debian.org/debian/pool/main/libb/libbs2b/libbs2b_3.1.0+dfsg.orig.tar.gz" \
    "https://downloads.sourceforge.net/project/bs2b/libbs2b/3.1.0/libbs2b-3.1.0.tar.gz"

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
# I filtri e il resampler che l'app usa devono esserci per ogni ABI: i nomi dei filtri sono testo in libavfilter,
# libsoxr (statica in libswresample) lascia il messaggio d'errore di soxr_create
for abi_dir in "$CHECK"/jni/*/; do
    for flt in ${FILTERS//,/ }; do
        grep -aq -- "$flt" "$abi_dir/libavfilter.so" || fail "filtro $flt assente in $abi_dir"
    done
    grep -aq 'invalid io datatype(s)' "$abi_dir/libswresample.so" || fail "libsoxr assente in $abi_dir"
done
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
copy_license soxr        $D/soxr/LICENCE $D/soxr/COPYING.LGPL
copy_license libbs2b     $D/libbs2b/COPYING
# Lua: la licenza è in fondo a src/lua.h
if [ -f $D/lua/src/lua.h ]; then
    # il blocco di licenza inizia con "* Copyright (C) 1994-…" (non la #define LUA_COPYRIGHT)
    awk '/^\* Copyright \(C\) 1994/{p=1} p{print} p&&/\*\//{exit}' $D/lua/src/lua.h > "$LICENSES/lua.txt"
    [ -s "$LICENSES/lua.txt" ] || echo "ATTENZIONE: licenza di lua non estratta" >&2
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
