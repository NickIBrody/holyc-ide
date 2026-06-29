#include <stdio.h>
#include "../app/src/main/jni/ast.h"

int hc_lex(const char *src, Token *out, int max_tokens);
int hc_parse(Token *toks, int count, AstNode *arena, int cap, const char *src);

static const char *NT[] = {"none","FUNCDEF","PARAM","BLOCK","RETURN","VARDECL",
    "ASSIGN","IF","WHILE","BINOP","INTLIT","IDENT","CALL","PRINT","EXPRSTMT"};

static AstNode *AR;
static const char *SRC;

static void dump(int idx, int depth) {
    if (!idx) return;
    AstNode *n = &AR[idx];
    for (int i = 0; i < depth; i++) printf("  ");
    printf("%s", NT[n->type]);
    if (n->name[0]) printf(" name=%s", n->name);
    if (n->type == NODE_INTLIT) printf(" ival=%lld", (long long)n->ival);
    if (n->type == NODE_BINOP) printf(" op=%d", n->op);
    if (n->type == NODE_PRINT) printf(" str=\"%.*s\"", (int)n->c, SRC + n->ival);
    printf("\n");
    if (n->a) { for(int i=0;i<depth;i++)printf("  "); printf(" a:\n"); dump(n->a, depth+2); }
    if (n->b) { for(int i=0;i<depth;i++)printf("  "); printf(" b:\n"); dump(n->b, depth+2); }
    if (n->c && n->type != NODE_PRINT) { for(int i=0;i<depth;i++)printf("  "); printf(" c:\n"); dump(n->c, depth+2); }
    if (n->next) dump(n->next, depth);
}

int main(void) {
    SRC =
        "I64 Add(I64 a, I64 b) {\n"
        "  return a + b * 2;\n"
        "}\n"
        "U0 Main() {\n"
        "  I64 x = Add(10, 32);\n"
        "  while (x < 100) { x = x + 1; }\n"
        "  \"x = %d\\n\", x;\n"
        "}\n"
        "Main;\n";

    static Token toks[512];
    static AstNode arena[1024];
    int n = hc_lex(SRC, toks, 512);
    printf("tokens=%d\n", n);
    if (n < 0) return 1;
    int root = hc_parse(toks, n, arena, 1024, SRC);
    printf("root=%d\n", root);
    if (root < 0) return 1;
    AR = arena;
    dump(arena[root].a, 0);
    return 0;
}
