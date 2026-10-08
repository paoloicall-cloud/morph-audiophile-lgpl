# Build LGPL delle librerie native

Morph Audiophile è un'app chiusa: non può distribuire librerie GPL. Questi script producono le stesse librerie usate oggi, in versione LGPL (motivazioni e obblighi in `../LICENSING.md`).

| Script | Cosa fa | Esito |
|---|---|---|
| `build-libmpv-lgpl.sh` | libmpv-android `v1.0.0` (FFmpeg 8.1, mpv 0.41) senza `--enable-gpl`, mpv con `-Dgpl=false`; verifica che nessuna `.so` si dichiari GPL | `app/libs/libmpv-lgpl.aar`, licenze originali in `app/src/main/assets/licenses/third_party/` |
| `build-media3-ffmpeg-lgpl.sh` | estensione FFmpeg ufficiale di Media3 `1.11.1` con FFmpeg 6.0 LGPL e gli stessi decoder di oggi | `app/libs/media3-decoder-ffmpeg-lgpl.aar` |
| `make-source-offer.sh <URL>` | archivio dei sorgenti esatti + testo dell'offerta mostrato nell'app | `native-lgpl/out/*.tar.gz`, `app/src/main/assets/licenses/SOURCE_OFFER.txt` |

Quando i due `.aar` esistono, `app/build.gradle.kts` li usa al posto dei pacchetti GPL senza altre modifiche.

## Dove eseguirli
Servono Linux e circa 1 ora di compilazione.

**GitHub Actions** (nessun PC Linux):
1. crea un repository GitHub **privato** e caricaci il progetto;
2. copia `github-workflow.yml` in `.github/workflows/`;
3. da GitHub: Actions → *Build LGPL native* → *Run workflow*, indicando l'URL dove pubblicherai l'archivio dei sorgenti;
4. scarica l'artefatto `morph-audiophile-lgpl` e copia i file nelle stesse cartelle del progetto.

**WSL o PC Linux** (Ubuntu):
```
sudo apt-get install -y git wget autoconf pkgconf libtool ninja-build python3-pip python3-jinja2 gperf nasm unzip rsync openjdk-17-jdk
sudo pip3 install --break-system-packages meson
export ANDROID_HOME=~/Android/Sdk          # SDK Android con NDK installato
bash native-lgpl/build-libmpv-lgpl.sh
NDK_PATH=$ANDROID_HOME/ndk/<versione> bash native-lgpl/build-media3-ffmpeg-lgpl.sh
bash native-lgpl/make-source-offer.sh https://<tuo-sito>/morph-audiophile-lgpl-sources.tar.gz
```

## Dopo la build
1. Carica l'archivio di `native-lgpl/out/` all'URL indicato.
2. In `gradle.properties` porta `morph.allowGplNativeForTesting` a `false`.
3. `gradlew assembleRelease`: il controllo `checkReleaseLicenses` deve passare senza avvisi.
4. Prova sul telefono un file per formato. Per i lossless, confronta l'hash del PCM decodificato con quello delle vecchie librerie: deve coincidere.

## Note
- Gli script modificano i file di build di libmpv-android con `sed` e si fermano se il testo atteso non c'è più. Cambiando `LIBMPV_ANDROID_REF` vanno ricontrollati.
- `MEDIA3_REF` deve coincidere con la versione di Media3 in `app/build.gradle.kts`.
- Eseguiti con successo nella run #2 (release `lgpl-2`) di https://github.com/paoloicall-cloud/morph-audiophile-lgpl. Le versioni esatte sono in `build-info/`.
- Le modifiche a questi script vanno ricaricate anche nel repository pubblico prima di rilanciare il workflow.
