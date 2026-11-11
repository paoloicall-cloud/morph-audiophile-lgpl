#!/usr/bin/env bash
# Archivio dei sorgenti esatti di libmpv-2.dll (Windows): FFmpeg, mpv con le patch, libplacebo, libsoxr, libbs2b, zlib
# più gli script di build. È l'offerta del sorgente richiesta dalla LGPL.
# Uso: ARCHIVE_NAME=nome ./make-source-offer-windows.sh nome   (dopo build-libmpv-windows-lgpl.sh)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/work-windows/src"; OUT="$HERE/out-windows"
NAME="${1:-morph-pc-lgpl-sources-$(date +%Y%m%d)}"
[ -f "$SRC/ffmpeg.txz" ] || { echo "Esegui prima build-libmpv-windows-lgpl.sh" >&2; exit 1; }
STAGE="$(mktemp -d)/$NAME"; mkdir -p "$STAGE"
cp "$SRC"/zlib.tgz "$SRC"/soxr.tgz "$SRC"/bs2b.tgz "$SRC"/ffmpeg.txz "$SRC"/freetype.txz "$SRC"/fribidi.txz "$SRC"/harfbuzz.txz "$SRC"/libass.txz "$STAGE/"
for d in mpv libplacebo; do
    rsync -a --exclude '.git' --exclude '_b' "$SRC/$d/" "$STAGE/$d/"
done
cp -r "$HERE/patches" "$STAGE/patches"
cp "$HERE/build-libmpv-windows-lgpl.sh" "$HERE/make-source-offer-windows.sh" "$HERE/github-workflow-windows.yml" "$STAGE/"
cp "$HERE/tests/libmpv_smoke.c" "$OUT/versions.txt" "$STAGE/"
tar -C "$(dirname "$STAGE")" -czf "$OUT/$NAME.tar.gz" "$NAME"
echo "Archivio: $OUT/$NAME.tar.gz"; sha256sum "$OUT/$NAME.tar.gz"
