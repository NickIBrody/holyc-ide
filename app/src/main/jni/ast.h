#ifndef HOLYC_AST_H
#define HOLYC_AST_H
#include <stdint.h>

/* ---- Token types ---- */
enum {
    TOK_EOF = 0,
    TOK_INT_LIT,
    TOK_IDENT,
    TOK_STRING,
    TOK_PLUS,     /* +  */
    TOK_MINUS,    /* -  */
    TOK_STAR,     /* *  */
    TOK_SLASH,    /* /  */
    TOK_ASSIGN,   /* =  */
    TOK_SEMI,     /* ;  */
    TOK_LPAREN,   /* (  */
    TOK_RPAREN,   /* )  */
    TOK_LBRACE,   /* {  */
    TOK_RBRACE,   /* }  */
    TOK_COMMA,    /* ,  */
    TOK_LT,       /* <  */
    TOK_GT,       /* >  */
    TOK_LE,       /* <= */
    TOK_GE,       /* >= */
    TOK_EQEQ,     /* == */
    TOK_NE,       /* != */
    TOK_U0,
    TOK_I64,
    TOK_RETURN,
    TOK_IF,
    TOK_ELSE,
    TOK_WHILE
};

/* A token references the source by [start,len) so the lexer copies nothing. */
typedef struct Token {
    int32_t type;
    int32_t start;   /* byte offset into source */
    int32_t len;     /* length in bytes         */
    int32_t pad;
    int64_t ival;    /* value for TOK_INT_LIT   */
} Token;             /* 24 bytes */

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
    NODE_EXPRSTMT
};

/* Arena-allocated node. Children are *indices* into the arena (0 == none). */
typedef struct AstNode {
    int32_t type;
    int32_t op;      /* operator token type for BINOP                       */
    int64_t ival;    /* INTLIT value; STRING source offset                  */
    int32_t a;       /* child / lhs / cond / func-body / decl-init          */
    int32_t b;       /* child / rhs / then-branch                           */
    int32_t c;       /* else-branch; STRING length                          */
    int32_t next;    /* sibling index (statement lists, params, call args)  */
    char    name[32];/* IDENT / CALL / FUNCDEF / VARDECL name               */
} AstNode;           /* 56 bytes */

#endif
