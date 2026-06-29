// bridge.c — minimal JNI glue.  All real work lives in the .S files; this
// only marshals the source string, drives the lex -> parse -> codegen -> run
// pipeline, and returns the captured output (or an error message).

#include <jni.h>
#include "ast.h"

int   hc_lex(const char *src, Token *out, int max_tokens);
int   hc_parse(Token *toks, int count, AstNode *arena, int cap, const char *src);
int   hc_codegen(AstNode *arena, int root, unsigned char *buf, int cap,
                 const char *src, void *print_str, void *print_int);
void  hc_print_str(const char *p, long len);
void  hc_print_int(long v);
void  hc_out_reset(void);
long  hc_out_size(void);
char *hc_out_data(void);
void *hc_jit_alloc(long size);
long  hc_run(void *entry);

#define MAX_TOK   8192
#define MAX_NODE  16384
#define JIT_SIZE  (256 * 1024)

static Token    g_toks[MAX_TOK];
static AstNode  g_arena[MAX_NODE];
static unsigned char *g_jit;          // reused across runs

JNIEXPORT jstring JNICALL
Java_com_holyc_HolyCRuntime_compileAndRun(JNIEnv *env, jclass cls, jstring jsrc)
{
    const char *src = (*env)->GetStringUTFChars(env, jsrc, 0);
    const char *msg = 0;

    int n = hc_lex(src, g_toks, MAX_TOK);
    if (n < 0) { msg = "Lexer error: unexpected character or token overflow."; goto done; }

    int root = hc_parse(g_toks, n, g_arena, MAX_NODE, src);
    if (root < 0) { msg = "Parse error: malformed HolyC (check braces, ; and ())."; goto done; }

    if (!g_jit) {
        g_jit = (unsigned char *)hc_jit_alloc(JIT_SIZE);
        if ((long)g_jit == -1) { g_jit = 0; msg = "Runtime error: cannot map executable memory."; goto done; }
    }

    hc_out_reset();
    int entry = hc_codegen(g_arena, root, g_jit, JIT_SIZE, src,
                           (void *)hc_print_str, (void *)hc_print_int);
    if (entry < 0) { msg = "Codegen error: unsupported construct or undefined symbol."; goto done; }

    __builtin___clear_cache((char *)g_jit, (char *)g_jit + JIT_SIZE);
    hc_run(g_jit + entry);

done:
    (*env)->ReleaseStringUTFChars(env, jsrc, src);

    if (msg)
        return (*env)->NewStringUTF(env, msg);

    long sz = hc_out_size();
    char *d = hc_out_data();
    d[sz] = 0;                          // NUL-terminate (buffer has spare room)
    return (*env)->NewStringUTF(env, d);
}
