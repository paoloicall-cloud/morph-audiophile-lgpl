/* Prova di base di libmpv-2.dll: carica la DLL, riproduce un WAV con un filtro audio di Morph e con l'uscita
   PCM (patch dei blocchi piccoli), verifica fine file regolare. Uso: libmpv_smoke.exe libmpv-2.dll prova.wav out.pcm */
#include <windows.h>
#include <stdio.h>
#include <stdint.h>
typedef struct { int event_id; int error; uint64_t reply_userdata; void *data; } ev_t;
typedef struct { int reason; int error; } endfile_t;
typedef void *(*create_t)(void); typedef int (*init_t)(void *);
typedef int (*setopt_t)(void *, const char *, const char *); typedef int (*cmd_t)(void *, const char **);
typedef ev_t *(*wait_t)(void *, double); typedef void (*destroy_t)(void *);
typedef unsigned long (*ver_t)(void);
static int run(HMODULE m, const char *wav, const char *ao, const char *extra_name, const char *extra_val) {
    create_t create = (create_t)GetProcAddress(m, "mpv_create"); init_t init = (init_t)GetProcAddress(m, "mpv_initialize");
    setopt_t setopt = (setopt_t)GetProcAddress(m, "mpv_set_option_string"); cmd_t cmd = (cmd_t)GetProcAddress(m, "mpv_command");
    wait_t waitev = (wait_t)GetProcAddress(m, "mpv_wait_event"); destroy_t destroy = (destroy_t)GetProcAddress(m, "mpv_terminate_destroy");
    if (!create || !init || !setopt || !cmd || !waitev || !destroy) { puts("simboli mancanti"); return 2; }
    void *h = create(); if (!h) return 3;
    setopt(h, "vo", "null"); setopt(h, "video", "no"); setopt(h, "ao", ao); setopt(h, "config", "no");
    if (extra_name) setopt(h, extra_name, extra_val);
    if (init(h) < 0) { puts("initialize fallita"); return 4; }
    const char *args[] = { "loadfile", wav, NULL }; if (cmd(h, args) < 0) { puts("loadfile fallito"); return 5; }
    for (int i = 0; i < 400; i++) {
        ev_t *e = waitev(h, 0.1);
        if (e->event_id == 7) { int reason = ((endfile_t *)e->data)->reason; int err = ((endfile_t *)e->data)->error;
            printf("fine file: motivo=%d errore=%d (ao=%s)\n", reason, err, ao); destroy(h); return reason == 0 ? 0 : 6; }
        if (e->event_id == 1) break;
    }
    puts("nessuna fine file"); return 7;
}
int main(int argc, char **argv) {
    if (argc < 4) return 1;
    HMODULE m = LoadLibraryA(argv[1]); if (!m) { printf("LoadLibrary fallita %lu\n", GetLastError()); return 1; }
    ver_t ver = (ver_t)GetProcAddress(m, "mpv_client_api_version"); printf("client api %lx\n", ver ? ver() : 0);
    int r = run(m, argv[2], "null", "af", "lavfi=[equalizer=f=1000:width_type=o:w=1:g=3,alimiter]"); if (r) return r;
    char opt[600]; snprintf(opt, sizeof opt, "%s", argv[3]);
    r = run(m, argv[2], "pcm", "ao-pcm-file", opt); if (r) return r;
    FILE *f = fopen(argv[3], "rb"); if (!f) { puts("file pcm assente"); return 8; }
    fseek(f, 0, SEEK_END); long n = ftell(f); fclose(f); printf("pcm scritto: %ld byte\n", n);
    return n > 10000 ? 0 : 9;
}
