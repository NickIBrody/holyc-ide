#ifndef HOLYC_AST_H
#define HOLYC_AST_H
#include <stdint.h>

/* ---- Token types ---- */
enum {
    TOK_EOF = 0,
    TOK_INT_LIT,
    TOK_IDENT,
    TOK_STRING,
    TOK_PLUS,        /*  +   */
    TOK_MINUS,       /*  -   */
    TOK_STAR,        /*  *   */
    TOK_SLASH,       /*  /   */
    TOK_ASSIGN,      /*  =   */
    TOK_SEMI,        /*  ;   */
    TOK_LPAREN,      /*  (   */
    TOK_RPAREN,      /*  )   */
    TOK_LBRACE,      /*  {   */
    TOK_RBRACE,      /*  }   */
    TOK_COMMA,       /*  ,   */
    TOK_LT,          /*  <   */
    TOK_GT,          /*  >   */
    TOK_LE,          /* <=   */
    TOK_GE,          /* >=   */
    TOK_EQEQ,        /* ==   */
    TOK_NE,          /* !=   */
    TOK_U0,
    TOK_I64,
    TOK_RETURN,
    TOK_IF,
    TOK_ELSE,
    TOK_WHILE,
    TOK_FOR,
    TOK_PLUSPLUS,    /* ++   */
    TOK_MINUSMINUS,  /* --   */
    TOK_PLUS_EQ,     /* +=   (base op = TOK_PLUS_EQ - 26 = TOK_PLUS)  */
    TOK_MINUS_EQ,    /* -=   */
    TOK_STAR_EQ,     /* *=   */
    TOK_SLASH_EQ,    /* /=   */
    TOK_BANG,        /*  !   */
    TOK_AMP          /*  &   */
};

typedef struct Token {
    int32_t type;
    int32_t start;
    int32_t len;
    int32_t pad;
    int64_t ival;
} Token;  /* 24 bytes */

/* ---- AST node types ---- */
enum {
    NODE_NONE = 0,
    NODE_FUNCDEF,
    NODE_PARAM,
    NODE_BLOCK,
    NODE_RETURN,
    NODE_VARDECL,
    NODE_ASSIGN,
    NODE_IF,
    NODE_WHILE,
    NODE_BINOP,
    NODE_INTLIT,
    NODE_IDENT,
    NODE_CALL,
    NODE_PRINT,
    NODE_EXPRSTMT,
    NODE_FOR,      /* a=init, b=cond, c=step, op=body (int32 reuse) */
    NODE_POST_INC, /* name=var; value = var++ */
    NODE_POST_DEC,
    NODE_PRE_INC,  /* name=var; value = ++var */
    NODE_PRE_DEC,
    NODE_NOT,      /* a=expr; value = !expr  */
    NODE_ADDR,     /* name=var; value = &var */
    NODE_DEREF     /* a=expr;  value = *expr */
};

typedef struct AstNode {
    int32_t type;
    int32_t op;
    int64_t ival;
    int32_t a;
    int32_t b;
    int32_t c;
    int32_t next;
    char    name[32];
} AstNode;  /* 64 bytes */

#endif
