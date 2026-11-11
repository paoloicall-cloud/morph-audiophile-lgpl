#!/usr/bin/env bash
# Compila libmpv per Windows x64 (libmpv-2.dll) in versione LGPL per Morph PC.
#
# Cross-compilazione da Linux con mingw-w64 (la CI di GitHub, vedi github-workflow-windows.yml, oppure Ubuntu/WSL).
# Stesse versioni e stesse patch di mpv dell'Android (build-libmpv-lgpl.sh): FFmpeg 8.1, mpv 0.41.0, libplacebo,
# libsoxr, libbs2b. FFmpeg senza --enable-gpl (resta --enable-version3), mpv con -Dgpl=false.
# Tutto statico dentro libmpv-2.dll: l'unica DLL da distribuire. TLS con Schannel di Windows (niente OpenSSL).
# Solo audio: niente uscite video, niente script Lua, niente sottotitoli.
#
# Requisiti (Ubuntu): git wget xz-utils pkgconf cmake ninja-build meson python3-jinja2 python3-mako nasm yasm
#   gcc-mingw-w64-x86-64-win32 g++-mingw-w64-x86-64-win32 binutils-mingw-w64-x86-64 make autoconf automake libtool
# Uso:   ./build-libmpv-windows-lgpl.sh
# Esito: native-lgpl/out-windows/{libmpv-2.dll, licenses/, versions.txt}
set -euo pipefail
trap 'echo "ERRORE alla riga $LINENO: $BASH_COMMAND" >&2' ERR

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${WORK_DIR:-$HERE/work-windows}"
OUT="$HERE/out-windows"
PREFIX="$WORK/prefix"
JOBS="$(nproc)"

V_ZLIB=1.3.1
V_FREETYPE=2.13.3
V_FRIBIDI=1.0.16
V_HARFBUZZ=10.4.0
V_LIBASS=0.17.4
V_SOXR=0.1.3
V_BS2B=3.1.0
V_PLACEBO=v7.360.1
V_FFMPEG=8.1
V_MPV=v0.41.0

TRIPLE=x86_64-w64-mingw32
CC=$TRIPLE-gcc-win32     # thread win32: niente libwinpthread-1.dll a fianco
CXX=$TRIPLE-g++-win32
export CC CXX
export AR=$TRIPLE-gcc-ar RANLIB=$TRIPLE-gcc-ranlib STRIP=$TRIPLE-strip WINDRES=$TRIPLE-windres
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_PATH=
export CFLAGS="-O2 -I$PREFIX/include" CXXFLAGS="-O2 -I$PREFIX/include" LDFLAGS="-L$PREFIX/lib"

fail() { echo "ERRORE: $*" >&2; exit 1; }
for t in $CC $CXX meson ninja cmake pkgconf nasm; do command -v "$t" >/dev/null || fail "manca $t"; done

mkdir -p "$WORK/src" "$PREFIX/include" "$PREFIX/lib/pkgconfig" "$OUT/licenses"
cd "$WORK/src"

fetch() { # nome url
    if [ ! -s "$1" ]; then
        wget -q --tries=3 -O "$1.part" "$2" || fail "download fallito: $2"
        mv -f "$1.part" "$1"
    fi
}

# meson cross file
cat > "$WORK/cross.txt" <<EOF
[binaries]
c = '$CC'
cpp = '$CXX'
ar = '$AR'
strip = '$STRIP'
windres = '$WINDRES'
dlltool = '$TRIPLE-dlltool'
nm = '$TRIPLE-nm'
objdump = '$TRIPLE-objdump'
pkg-config = 'pkgconf'
[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
[properties]
needs_exe_wrapper = true
EOF
cat > "$WORK/toolchain.cmake" <<EOF
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_C_COMPILER $CC)
set(CMAKE_CXX_COMPILER $CXX)
set(CMAKE_RC_COMPILER $WINDRES)
set(CMAKE_FIND_ROOT_PATH $PREFIX)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
EOF

# ---- zlib (licenza zlib) ----
fetch zlib.tgz "https://github.com/madler/zlib/releases/download/v$V_ZLIB/zlib-$V_ZLIB.tar.gz"
rm -rf zlib && mkdir zlib && tar -xf zlib.tgz -C zlib --strip-components=1
( cd zlib && make -f win32/Makefile.gcc PREFIX=$TRIPLE- CC=$CC AR=$AR RANLIB=$RANLIB \
    -j"$JOBS" libz.a >/dev/null
  install -D libz.a "$PREFIX/lib/libz.a"; cp zlib.h zconf.h "$PREFIX/include/"
  mkdir -p "$PREFIX/lib/pkgconfig"
  cat > "$PREFIX/lib/pkgconfig/zlib.pc" <<EOF
prefix=$PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: zlib
Description: zlib
Version: $V_ZLIB
Libs: -L\${libdir} -lz
Cflags: -I\${includedir}
EOF
)

# ---- libsoxr (LGPL 2.1+) ----
fetch soxr.tgz "https://downloads.sourceforge.net/project/soxr/soxr-$V_SOXR-Source.tar.xz"
rm -rf soxr && mkdir soxr && tar -xf soxr.tgz -C soxr --strip-components=1
cmake -S soxr -B soxr/_b -G Ninja -DCMAKE_TOOLCHAIN_FILE="$WORK/toolchain.cmake" -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTS=OFF -DBUILD_EXAMPLES=OFF -DWITH_OPENMP=OFF \
    -DWITH_LSR_BINDINGS=OFF -DWITH_DEV_TRACE=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5 >/dev/null
cmake --build soxr/_b -j"$JOBS" >/dev/null && cmake --install soxr/_b >/dev/null
cp soxr/LICENCE "$OUT/licenses/libsoxr-LICENCE.txt"

# ---- libbs2b (MIT) ----
fetch bs2b.tgz "https://downloads.sourceforge.net/project/bs2b/libbs2b/$V_BS2B/libbs2b-$V_BS2B.tar.bz2"
rm -rf bs2b && mkdir bs2b && tar -xf bs2b.tgz -C bs2b --strip-components=1
# Il configure di libbs2b pretende libsndfile (serve solo al programma bs2bconvert): si compila a mano il solo
# src/bs2b.c, una libreria C di un file senza dipendenze né macro di esportazione.
( cd bs2b/src && $CC -O2 -c bs2b.c -o bs2b.o && $AR rcs "$PREFIX/lib/libbs2b.a" bs2b.o \
  && mkdir -p "$PREFIX/include/bs2b" && cp bs2b.h bs2btypes.h bs2bversion.h "$PREFIX/include/bs2b/" )
cat > "$PREFIX/lib/pkgconfig/libbs2b.pc" <<EOT
prefix=$PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: libbs2b
Description: Bauer stereophonic-to-binaural DSP library
Version: $V_BS2B
Libs: -L\${libdir} -lbs2b
Libs.private: -lm
Cflags: -I\${includedir}/bs2b
EOT
[ -f "$PREFIX/lib/libbs2b.a" ] || fail "libbs2b non compilata"
[ -f "$PREFIX/lib/pkgconfig/libbs2b.pc" ] || fail "libbs2b.pc mancante"
cp bs2b/COPYING "$OUT/licenses/libbs2b-COPYING.txt"

# ---- libplacebo (LGPL 2.1+), senza nessun backend grafico: mpv lo vuole comunque anche solo per l'audio ----
[ -d libplacebo ] || git clone --quiet --recursive https://code.videolan.org/videolan/libplacebo.git
( cd libplacebo && git checkout --quiet --force "$V_PLACEBO" && git submodule update --quiet --init --recursive )
rm -rf libplacebo/_b
meson setup libplacebo/_b libplacebo --cross-file "$WORK/cross.txt" --prefix "$PREFIX" --buildtype release \
    --default-library static -Dvulkan=disabled -Dopengl=disabled -Dd3d11=disabled -Dglslang=disabled \
    -Dshaderc=disabled -Dlcms=disabled -Ddemos=false -Dtests=false -Dunwind=disabled -Dxxhash=disabled \
    -Ddovi=disabled -Dlibdovi=disabled -Dgl-proc-addr=disabled -Dvk-proc-addr=disabled -Dfuzz=false \
    -Dbench=false || { tail -60 libplacebo/_b/meson-logs/meson-log.txt; fail "meson di libplacebo"; }
ninja -C libplacebo/_b >/dev/null && ninja -C libplacebo/_b install >/dev/null
cp libplacebo/LICENSE "$OUT/licenses/libplacebo-LICENSE.txt"
# libplacebo usa std::to_chars/from_chars: il link di mpv (fatto con gcc, non g++) deve aggiungere libstdc++ statica
grep -q 'lstdc++' "$PREFIX/lib/pkgconfig/libplacebo.pc" || \
    sed -i 's|^Libs.private:.*|& -Wl,-Bstatic -lstdc++ -Wl,-Bdynamic|' "$PREFIX/lib/pkgconfig/libplacebo.pc"
grep -n 'Libs' "$PREFIX/lib/pkgconfig/libplacebo.pc"

# ---- libass e dipendenze (mpv 0.41 le vuole anche per un uso solo audio): FreeType, FriBidi, HarfBuzz, libass ----
fetch freetype.txz "https://download.savannah.gnu.org/releases/freetype/freetype-$V_FREETYPE.tar.xz"
rm -rf freetype && mkdir freetype && tar -xf freetype.txz -C freetype --strip-components=1
cmake -S freetype -B freetype/_b -G Ninja -DCMAKE_TOOLCHAIN_FILE="$WORK/toolchain.cmake" -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DFT_DISABLE_ZLIB=ON -DFT_DISABLE_BZIP2=ON -DFT_DISABLE_PNG=ON \
    -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_BROTLI=ON >/dev/null
cmake --build freetype/_b -j"$JOBS" >/dev/null && cmake --install freetype/_b >/dev/null
cp freetype/docs/FTL.TXT "$OUT/licenses/freetype-FTL.txt"

fetch fribidi.txz "https://github.com/fribidi/fribidi/releases/download/v$V_FRIBIDI/fribidi-$V_FRIBIDI.tar.xz"
rm -rf fribidi && mkdir fribidi && tar -xf fribidi.txz -C fribidi --strip-components=1
meson setup fribidi/_b fribidi --cross-file "$WORK/cross.txt" --prefix "$PREFIX" --buildtype release \
    --default-library static -Dbin=false -Ddocs=false -Dtests=false >/dev/null
ninja -C fribidi/_b >/dev/null && ninja -C fribidi/_b install >/dev/null
cp fribidi/COPYING "$OUT/licenses/fribidi-COPYING.txt"

fetch harfbuzz.txz "https://github.com/harfbuzz/harfbuzz/releases/download/$V_HARFBUZZ/harfbuzz-$V_HARFBUZZ.tar.xz"
rm -rf harfbuzz && mkdir harfbuzz && tar -xf harfbuzz.txz -C harfbuzz --strip-components=1
meson setup harfbuzz/_b harfbuzz --cross-file "$WORK/cross.txt" --prefix "$PREFIX" --buildtype release \
    --default-library static -Dfreetype=enabled -Dglib=disabled -Dgobject=disabled -Dcairo=disabled -Dicu=disabled \
    -Dtests=disabled -Ddocs=disabled -Dbenchmark=disabled -Dgdi=disabled -Ddirectwrite=disabled \
    -Dcpp_link_args="-static-libgcc -static-libstdc++" >/dev/null \
    || { tail -40 harfbuzz/_b/meson-logs/meson-log.txt; fail "meson di harfbuzz"; }
ninja -C harfbuzz/_b >/dev/null && ninja -C harfbuzz/_b install >/dev/null
cp harfbuzz/COPYING "$OUT/licenses/harfbuzz-COPYING.txt"

fetch libass.txz "https://github.com/libass/libass/releases/download/$V_LIBASS/libass-$V_LIBASS.tar.xz"
rm -rf libass && mkdir libass && tar -xf libass.txz -C libass --strip-components=1
( cd libass && PKG_CONFIG=pkgconf ./configure --host=$TRIPLE --prefix="$PREFIX" --disable-shared --enable-static \
    --disable-asm --disable-fontconfig --disable-directwrite --disable-coretext \
    --disable-require-system-font-provider >/dev/null \
  && make -j"$JOBS" >/dev/null && make install >/dev/null ) || fail "libass"
cp libass/COPYING "$OUT/licenses/libass-COPYING.txt"

# ---- FFmpeg (LGPL, senza --enable-gpl) ----
fetch ffmpeg.txz "https://ffmpeg.org/releases/ffmpeg-$V_FFMPEG.tar.xz"
rm -rf ffmpeg && mkdir ffmpeg && tar -xf ffmpeg.txz -C ffmpeg --strip-components=1
# stessi filtri dell'Android (AudioFx / sezione DSP) più quelli che mpv chiede per il video e l'instradamento
FILTERS="aformat,aresample,anull,abuffer,abuffersink,volume,equalizer,bass,treble,bs2b,afir,amovie,hdcd,aemphasis,alimiter,asetrate,atempo,adelay,aeval,stereotools,haas,highpass,lowpass,acompressor,anequalizer,biquad,pan,channelsplit,join,asplit,amerge,amix,buffer,buffersink,format,scale,null,nullsink"
( cd ffmpeg && ./configure --prefix="$PREFIX" --arch=x86_64 --target-os=mingw32 --cross-prefix=$TRIPLE- \
    --cc=$CC --cxx=$CXX --pkg-config=pkgconf --pkg-config-flags=--static \
    --enable-cross-compile --disable-shared --enable-static --disable-debug --disable-doc --disable-programs \
    --disable-autodetect --enable-version3 --enable-zlib --enable-schannel --enable-libsoxr --enable-libbs2b \
    --enable-network --disable-filters --enable-filter="$FILTERS" \
    --extra-cflags="-I$PREFIX/include" --extra-ldflags="-L$PREFIX/lib" >/dev/null )
grep -q '^#define CONFIG_GPL 0' ffmpeg/config.h || fail "FFmpeg si è configurato come GPL"
grep -q '^#define CONFIG_NONFREE 0' ffmpeg/config.h || fail "FFmpeg si è configurato come nonfree"
make -C ffmpeg -j"$JOBS" >/dev/null && make -C ffmpeg install >/dev/null
cp ffmpeg/COPYING.LGPLv2.1 ffmpeg/COPYING.LGPLv3 "$OUT/licenses/"

# ---- mpv (LGPL 2.1+) con le patch di Morph ----
[ -d mpv ] || git clone --quiet https://github.com/mpv-player/mpv.git
( cd mpv && git checkout --quiet --force "$V_MPV" && git clean -fdxq )
for p in mpv-unknown-layouts mpv-pcm-small-blocks; do
    patch -d mpv -p1 --forward < "$HERE/patches/$p.patch" || fail "patch $p non applicata: i sorgenti di mpv sono cambiati"
done
grep -q 'Morph Audiophile: an unknown layout' mpv/audio/chmap_sel.c || fail "patch layout assente"
grep -q 'ao->device_buffer = 4096;' mpv/audio/out/ao_pcm.c || fail "patch blocchi piccoli assente"
rm -rf mpv/_b
meson setup mpv/_b mpv --cross-file "$WORK/cross.txt" --prefix "$PREFIX" --buildtype release --prefer-static \
    -Dgpl=false -Dlibmpv=true -Dcplayer=false -Dbuild-date=false -Dtests=false -Dmanpage-build=disabled \
    -Dhtml-build=disabled -Dpdf-build=disabled -Dlua=disabled -Djavascript=disabled -Dlibarchive=disabled \
    -Dlcms2=disabled -Drubberband=disabled -Duchardet=disabled -Diconv=disabled \
    -Dvapoursynth=disabled -Dzimg=disabled -Dlibbluray=disabled -Ddvdnav=disabled -Dcdda=disabled \
    -Dsdl2-gamepad=disabled -Dsdl2-audio=disabled -Dsdl2-video=disabled -Dgl=disabled -Dvulkan=disabled -Dd3d11=disabled -Dgl-win32=disabled -Degl-angle=disabled \
    -Dwasapi=enabled -Dcaca=disabled -Djpeg=disabled -Dwin32-smtc=disabled -Dwin32-threads=enabled -Dplain-gl=disabled -Dd3d-hwaccel=disabled -Dd3d9-hwaccel=disabled -Dgl-dxinterop=disabled -Dlibavdevice=disabled \
    -Dc_link_args="-static-libgcc -Wl,--no-insert-timestamp" -Dcpp_link_args="-static-libgcc -static-libstdc++" \
    || { tail -60 mpv/_b/meson-logs/meson-log.txt; fail "configurazione di mpv fallita"; }
ninja -C mpv/_b
DLL="$(find mpv/_b -name 'libmpv-2.dll' | head -n 1)"
[ -n "$DLL" ] || fail "libmpv-2.dll non prodotta"
cp "$DLL" "$OUT/libmpv-2.dll"
$STRIP --strip-unneeded "$OUT/libmpv-2.dll"
cp mpv/LICENSE.LGPL "$OUT/licenses/mpv-LICENSE.LGPL.txt"
cp mpv/Copyright "$OUT/licenses/mpv-Copyright.txt"
cp -r mpv/include/mpv "$OUT/include" 2>/dev/null || cp -r mpv/libmpv "$OUT/include" 2>/dev/null || true
cp "$HERE/patches/mpv-unknown-layouts.patch" "$HERE/patches/mpv-pcm-small-blocks.patch" "$OUT/licenses/"

# ---- controlli di licenza e di dipendenze ----
echo "== DLL importate"; $TRIPLE-objdump -p "$OUT/libmpv-2.dll" | grep 'DLL Name' | sort -u | tee "$WORK/imports.txt"
if grep -i -E 'pthread|libgcc|libstdc|libgomp' "$WORK/imports.txt"; then fail "la DLL dipende da librerie di runtime non di sistema"; fi
if strings -a "$OUT/libmpv-2.dll" | grep -q -E 'libavutil license: (GPL|nonfree)|--enable-gpl|--enable-nonfree'; then
    fail "la DLL si dichiara GPL o nonfree"; fi
strings -a "$OUT/libmpv-2.dll" | grep -m1 -E 'LGPL version [23]' || fail "FFmpeg non si dichiara LGPL"
{
    echo "libmpv-windows-lgpl"
    echo "v_mpv=$V_MPV ($(git -C mpv rev-parse HEAD))"
    echo "v_ffmpeg=$V_FFMPEG"; echo "v_libplacebo=$V_PLACEBO ($(git -C libplacebo rev-parse HEAD))"
    echo "v_soxr=$V_SOXR"; echo "v_libbs2b=$V_BS2B"; echo "v_zlib=$V_ZLIB"
    echo "compiler=$($CC --version | head -n 1)"
    echo "sha256=$(sha256sum "$OUT/libmpv-2.dll" | cut -d' ' -f1)"
} > "$OUT/versions.txt"
cat "$OUT/versions.txt"
echo "Fatto: $OUT/libmpv-2.dll"
