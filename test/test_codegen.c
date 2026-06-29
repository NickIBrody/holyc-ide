#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include "../app/src/main/jni/ast.h"

int hc_lex(const char *src, Token *out, int max_tokens);
int hc_parse(Token *toks, int count, AstNode *arena, int cap, const char *src);
int hc_codegen(AstNode *arena, int root, unsigned char *buf, int cap,
               const char *src, void *print_str, void *print_int);

static void out_str(const char *p, long len) { fwrite(p, 1, len, stdout); }
static void out_int(long v) { printf("%ld", v); }

static const char *PROG =
    "I64 Add(I64 a, I64 b) {\n"
    "  return a + b;\n"
    "}\n"
    "I64 Fact(I64 n) {\n"
    "  I64 r = 1;\n"
    "  I64 i = 1;\n"
    "  while (i <= n) {\n"
    "    r = r * i;\n"
    "    i = i + 1;\n"
    "  }\n"
    "  return r;\n"
    "}\n"
    "U0 Main() {\n"
    "  I64 x = Add(10, 32);\n"
    "  \"Add(10,32) = %d\\n\", x;\n"
    "  \"5! = %d, 10! = %d\\n\", Fact(5), Fact(10);\n"
    "  if (x > 40) { \"x is big\\n\"; } else { \"x is small\\n\"; }\n"
    "}\n"
    "Main;\n";

int main(void) {
    static Token toks[1024];
    static AstNode arena[2048];
    int n = hc_lex(PROG, toks, 1024);
    if (n < 0) { printf("lex error\n"); return 1; }
    int root = hc_parse(toks, n, arena, 2048, PROG);
    if (root < 0) { printf("parse error\n"); return 1; }

    int cap = 65536;
    unsigned char *buf = mmap(NULL, cap, PROT_READ | PROT_WRITE | PROT_EXEC,
                              MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (buf == MAP_FAILED) { perror("mmap"); return 1; }

    int entry = hc_codegen(arena, root, buf, cap, PROG, out_str, out_int);
    if (entry < 0) { printf("codegen error\n"); return 1; }
    printf("[entry offset = %d]\n", entry);

    __builtin___clear_cache((char *)buf, (char *)buf + cap);
    long (*fn)(void) = (long (*)(void))(buf + entry);
    fn();
    return 0;
}
