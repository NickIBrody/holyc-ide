#include <stdio.h>
#include "../app/src/main/jni/ast.h"

int hc_lex(const char *src, Token *out, int max_tokens);

static const char *NAMES[] = {
    "EOF","INT","IDENT","STR","+","-","*","/","=",";","(",")","{","}",",",
    "<",">","<=",">=","==","!=","U0","I64","return","if","else","while"
};

int main(void) {
    const char *src =
        "I64 Add(I64 a, I64 b) {\n"
        "  return a + b;\n"
        "}\n"
        "U0 Main() {\n"
        "  I64 x = Add(10, 32);\n"
        "  \"x = %d\\n\", x;\n"
        "}\n"
        "Main;\n";

    Token toks[256];
    int n = hc_lex(src, toks, 256);
    printf("count=%d\n", n);
    if (n < 0) return 1;
    for (int i = 0; i < n; i++) {
        Token *t = &toks[i];
        printf("%2d: %-7s '%.*s'", i, NAMES[t->type], t->len, src + t->start);
        if (t->type == TOK_INT_LIT) printf("  ival=%lld", (long long)t->ival);
        printf("\n");
    }
    return 0;
}
