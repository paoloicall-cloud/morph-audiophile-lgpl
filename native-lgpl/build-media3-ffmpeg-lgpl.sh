#!/usr/bin/env bash
# Compila l'estensione FFmpeg ufficiale di Media3 (androidx/media) con FFmpeg LGPL, al posto di
# org.jellyfin.media3:media3-ffmpeg-decoder (GPL v3). È lo stesso codice da cui deriva quella di
# Jellyfin: cambia solo la configurazione di FFmpeg (build_ffmpeg.sh di Google non usa --enable-gpl).
#
# Requisiti: Linux, git, make, Android NDK (NDK_PATH), JDK 17+, ANDROID_HOME impostata.
# Uso:   NDK_PATH=/percorso/ndk ./build-media3-ffmpeg-lgpl.sh
# Esito: app/libs/media3-decoder-ffmpeg-lgpl.aar
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$HERE/.." && pwd)"
MEDIA3_REF="${MEDIA3_REF:-1.11.1}"          # deve coincidere con la versione di Media3 dell'app
FFMPEG_BRANCH="${FFMPEG_BRANCH:-release/6.0}" # versione raccomandata da Google per l'estensione
NDK_PATH="${NDK_PATH:?imposta NDK_PATH (es. \$ANDROID_HOME/ndk/<versione>)}"
HOST_PLATFORM="${HOST_PLATFORM:-linux-x86_64}"
ANDROID_ABI=28                               # = minSdk dell'app
# Gli stessi formati che oggi ExoPlayer decodifica via FFmpeg (vedi README dell'app)
ENABLED_DECODERS=(vorbis opus flac alac pcm_mulaw pcm_alaw mp3 amrnb amrwb aac ac3 eac3 dca mlp truehd)
WORK="${WORK_DIR:-$HERE/work}"

fail() { echo "ERRORE: $*" >&2; exit 1; }

mkdir -p "$WORK"
cd "$WORK"
[ -d media ] || git clone https://github.com/androidx/media.git
cd media
git fetch --tags --force
git checkout --force "$MEDIA3_REF"

MODULE="$(pwd)/libraries/decoder_ffmpeg/src/main"
cd "$MODULE/jni"
[ -d ffmpeg ] || git clone https://git.ffmpeg.org/ffmpeg.git --branch="$FFMPEG_BRANCH" --depth=1 ffmpeg
grep -q -- '--enable-gpl' build_ffmpeg.sh && fail "build_ffmpeg.sh abilita la GPL: controllare"
# iconv (solo per i sottotitoli) esiste in Android dalla API 28, ma il modulo JNI si collega per una
# API più bassa: senza questa opzione il link di libffmpegJNI.so fallisce su iconv_open/iconv/iconv_close
git checkout -- build_ffmpeg.sh
grep -q -- '--disable-vulkan' build_ffmpeg.sh || fail "build_ffmpeg.sh è cambiato: aggiornare la modifica qui sotto"
sed -i 's/--disable-vulkan/--disable-vulkan\n    --disable-iconv/' build_ffmpeg.sh
./build_ffmpeg.sh "$MODULE" "$NDK_PATH" "$HOST_PLATFORM" "$ANDROID_ABI" "${ENABLED_DECODERS[@]}"

# Verifica sulle librerie statiche prodotte: FFmpeg deve dichiararsi LGPL
grep -raq 'LGPL version' ffmpeg/android-libs || fail "stringa di licenza LGPL di FFmpeg non trovata"
if grep -raoE '(^|[^L])GPL version [0-9]' ffmpeg/android-libs >/dev/null; then fail "FFmpeg risulta GPL"; fi

cd "$WORK/media"
./gradlew :lib-decoder-ffmpeg:assembleRelease
AAR="$(find . -path '*outputs/aar/*' -name 'lib-decoder-ffmpeg-release.aar' | head -n 1)"
[ -n "$AAR" ] || fail "AAR dell'estensione non trovato"

mkdir -p "$APP_ROOT/app/libs"
cp "$AAR" "$APP_ROOT/app/libs/media3-decoder-ffmpeg-lgpl.aar"
{
    echo "androidx/media $MEDIA3_REF ($(git rev-parse HEAD))"
    echo "FFmpeg $FFMPEG_BRANCH ($(git -C "$MODULE/jni/ffmpeg" rev-parse HEAD))"
    echo "decoder: ${ENABLED_DECODERS[*]}"
} > "$WORK/media3-ffmpeg-versions.txt"

echo
echo "Fatto: $APP_ROOT/app/libs/media3-decoder-ffmpeg-lgpl.aar"
