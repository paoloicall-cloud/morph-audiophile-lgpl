#!/usr/bin/env bash
# Prepara il pacchetto dei sorgenti LGPL e l'offerta del codice sorgente mostrata nell'app.
#
# La LGPL chiede di rendere disponibile il sorgente esatto delle librerie distribuite (con le
# modifiche e gli script di build). Questo script crea l'archivio da pubblicare e il testo
# app/src/main/assets/licenses/SOURCE_OFFER.txt che dice dove trovarlo.
#
# Uso:   ./make-source-offer.sh https://indirizzo/dove/pubblicherai/archivio.tar.gz
# Esito: native-lgpl/out/morph-audiophile-lgpl-sources-<data>.tar.gz + SOURCE_OFFER.txt
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$HERE/.." && pwd)"
WORK="${WORK_DIR:-$HERE/work}"
URL="${1:?indica l'URL pubblico dove caricherai l'archivio dei sorgenti}"
NAME="${ARCHIVE_NAME:-morph-audiophile-lgpl-sources-$(date +%Y%m%d)}"
OUT="$HERE/out"

[ -d "$WORK/libmpv-android/buildscripts/deps" ] || { echo "Esegui prima build-libmpv-lgpl.sh" >&2; exit 1; }
[ -d "$WORK/media/libraries/decoder_ffmpeg" ] || { echo "Esegui prima build-media3-ffmpeg-lgpl.sh" >&2; exit 1; }

mkdir -p "$OUT"
STAGE="$(mktemp -d)/$NAME"
mkdir -p "$STAGE"

# Sorgenti di libmpv-android (con le dipendenze scaricate e le modifiche applicate), senza binari
rsync -a --exclude '.git' --exclude '_build*' --exclude 'prefix' --exclude 'sdk' \
    --exclude 'build' --exclude '*.aar' --exclude '*.so' --exclude '*.o' --exclude '*.a' \
    "$WORK/libmpv-android/" "$STAGE/libmpv-android/"
# Estensione FFmpeg di Media3 con il suo FFmpeg
rsync -a --exclude '.git' --exclude 'android-libs' --exclude '*.o' --exclude '*.a' --exclude '*.so' \
    "$WORK/media/libraries/decoder_ffmpeg/" "$STAGE/media3-decoder_ffmpeg/"
# Gli script con cui sono state compilate le librerie distribuite
cp "$HERE"/*.sh "$HERE"/*.yml "$HERE"/README.md "$STAGE/"
cp "$WORK"/*-versions.txt "$STAGE/" 2>/dev/null || true

tar -C "$(dirname "$STAGE")" -czf "$OUT/$NAME.tar.gz" "$NAME"
SHA="$(sha256sum "$OUT/$NAME.tar.gz" | cut -d' ' -f1)"

mkdir -p "$APP_ROOT/app/src/main/assets/licenses"
cat > "$APP_ROOT/app/src/main/assets/licenses/SOURCE_OFFER.txt" <<EOF
Morph Audiophile uses FFmpeg, mpv and other libraries licensed under the GNU Lesser General
Public License (LGPL). They are dynamically linked shared libraries (.so) that you may replace
with modified versions. The complete corresponding source code of these libraries, including
the build scripts and the changes made, is available at:

$URL
SHA-256: $SHA

The source code is offered for at least three years from the distribution of this version.
EOF

echo "Archivio: $OUT/$NAME.tar.gz"
echo "SHA-256:  $SHA"
echo "Carica l'archivio all'indirizzo indicato PRIMA di pubblicare l'app."
