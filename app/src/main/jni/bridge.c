// bridge.c — JNI glue.  Drives the C compiler pipeline, returns output string.
#include <jni.h>
#include <stdint.h>

// Compiler entry point (compiler.c)
int hc_compile(const char *src, uint8_t *buf, int cap, void *extra);

// Runtime helpers (runtime.S)
void  hc_print_str(const char *p, long len);
void  hc_print_int(long v);
void  hc_print_char(long c);
void  hc_print_uint(unsigned long v);
void  hc_print_cstr(const char *s);
void  hc_print_ptr(unsigned long p);
void *hc_malloc(long size);
void  hc_free(void *ptr);
long  hc_strlen(const char *s);
char *hc_strcpy(char *dst, const char *src);
char *hc_strcat(char *dst, const char *src);
long  hc_get_tsc(void);
void  hc_out_reset(void);
long  hc_out_size(void);
char *hc_out_data(void);
void *hc_jit_alloc(long size);
long  hc_run(void *entry);

typedef struct { void *print_char; void *print_uint; void *print_cstr; void *print_ptr; void *builtins; } HolyCExtra;
typedef struct { char name[32]; void *fn; } BuiltinEntry;

static BuiltinEntry g_builtins[] = {
    {"MAlloc",  (void*)hc_malloc},
    {"Free",    (void*)hc_free},
    {"StrLen",  (void*)hc_strlen},
    {"StrCpy",  (void*)hc_strcpy},
    {"StrCat",  (void*)hc_strcat},
    {"GetTSC",  (void*)hc_get_tsc},
    {"",        (void*)0}  // sentinel
};

#define JIT_SIZE (512 * 1024)
static unsigned char *g_jit;

JNIEXPORT jstring JNICALL
Java_com_holyc_HolyCRuntime_compileAndRun(JNIEnv *env, jclass cls, jstring jsrc)
{
    const char *src = (*env)->GetStringUTFChars(env, jsrc, 0);
    const char *msg = 0;

    if (!g_jit) {
        g_jit = (unsigned char *)hc_jit_alloc(JIT_SIZE);
        if ((long)g_jit <= 0) { g_jit = 0; msg = "Runtime error: cannot map executable memory."; goto done; }
    }

    hc_out_reset();

    HolyCExtra extra = {
        (void*)hc_print_char,
        (void*)hc_print_uint,
        (void*)hc_print_cstr,
        (void*)hc_print_ptr,
        (void*)g_builtins
    };

    int entry = hc_compile(src, g_jit, JIT_SIZE, &extra);
    if (entry < 0) {
        if (entry == -1)      msg = "Lexer error: empty or invalid source.";
        else if (entry == -2) msg = "Parse error: check syntax (braces, semicolons, types).";
        else                  msg = "Codegen error: unsupported construct or buffer overflow.";
        goto done;
    }

    __builtin___clear_cache((char *)g_jit, (char *)g_jit + JIT_SIZE);
    hc_run(g_jit + entry);

done:
    (*env)->ReleaseStringUTFChars(env, jsrc, src);

    if (msg)
        return (*env)->NewStringUTF(env, msg);

    long sz = hc_out_size();
    char *d = hc_out_data();
    d[sz] = 0;
    return (*env)->NewStringUTF(env, d);
}
