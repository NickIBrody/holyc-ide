// compiler.c — HolyC lexer + parser + ARM64 codegen (replaces lexer.S, parser.S, codegen.S)
#include <stdint.h>
#include <string.h>

// ═══════════════════════════════════════════
// LEXER
// ═══════════════════════════════════════════

typedef enum {
    T_EOF=0, T_INT, T_FLOAT, T_IDENT, T_STRING,
    T_PLUS, T_MINUS, T_STAR, T_SLASH, T_PCT,
    T_AMP, T_PIPE, T_CARET, T_TILDE,
    T_LSHIFT, T_RSHIFT,
    T_ASSIGN,
    T_EQ, T_NE, T_LT, T_LE, T_GT, T_GE,
    T_BANG, T_AND_AND, T_OR_OR,
    T_PLUSPLUS, T_MINUSMINUS,
    T_PLUS_EQ, T_MINUS_EQ, T_STAR_EQ, T_SLASH_EQ, T_PCT_EQ,
    T_SEMI, T_COMMA, T_DOT, T_ARROW,
    T_LPAREN, T_RPAREN, T_LBRACE, T_RBRACE, T_LBRACKET, T_RBRACKET,
    T_COLON, T_QUESTION,
    T_IF, T_ELSE, T_WHILE, T_FOR, T_RETURN,
    T_TYPEDEF, T_STRUCT, T_SIZEOF,
    T_VOID, T_I64, T_U64, T_I32, T_U32, T_I16, T_U16, T_I8, T_U8, T_CH, T_F64,
} TK;

typedef struct { TK kind; int pos; int64_t ival; char sval[64]; } Tok;

#define MAX_TOKS 8192
static Tok g_toks[MAX_TOKS];
static int g_ntoks;

static int is_alpha(char c){ return (c>='a'&&c<='z')||(c>='A'&&c<='Z')||c=='_'; }
static int is_digit(char c){ return c>='0'&&c<='9'; }
static int is_alnum(char c){ return is_alpha(c)||is_digit(c); }
static int is_xdigit(char c){ return is_digit(c)||(c>='a'&&c<='f')||(c>='A'&&c<='F'); }
static int xval(char c){ return is_digit(c)?c-'0':((c|32)-'a'+10); }

static const struct { const char *kw; TK tk; } g_kwds[] = {
    {"if",T_IF},{"else",T_ELSE},{"while",T_WHILE},{"for",T_FOR},{"return",T_RETURN},
    {"typedef",T_TYPEDEF},{"struct",T_STRUCT},{"sizeof",T_SIZEOF},
    {"U0",T_VOID},{"void",T_VOID},
    {"I64",T_I64},{"U64",T_U64},{"I32",T_I32},{"U32",T_U32},
    {"I16",T_I16},{"U16",T_U16},{"I8",T_I8},{"U8",T_U8},
    {"CH",T_CH},{"F64",T_F64},
    {"char",T_CH},{"long",T_I64},{"int",T_I32},{"unsigned",T_U64},
    {0,0}
};

static int is_type_tk(TK t){
    return t==T_I64||t==T_U64||t==T_I32||t==T_U32||t==T_I16||t==T_U16||
           t==T_I8||t==T_U8||t==T_CH||t==T_F64||t==T_VOID;
}

static int lex_all(const char *src){
    int i=0, n=0;
    while(src[i] && n<MAX_TOKS-1){
        while(src[i]==' '||src[i]=='\t'||src[i]=='\r'||src[i]=='\n') i++;
        if(!src[i]) break;
        if(src[i]=='/'&&src[i+1]=='/'){while(src[i]&&src[i]!='\n')i++;continue;}
        if(src[i]=='/'&&src[i+1]=='*'){i+=2;while(src[i]&&!(src[i]=='*'&&src[i+1]=='/'))i++;if(src[i])i+=2;continue;}
        Tok *t=&g_toks[n]; t->pos=i; t->ival=0; t->sval[0]=0;
        char c=src[i];
        if(c=='"'){
            i++; int j=0;
            while(src[i]&&src[i]!='"'){
                char ch=src[i++];
                if(ch=='\\'&&src[i]){ ch=src[i++];
                    if(ch=='n')ch='\n';else if(ch=='t')ch='\t';else if(ch=='r')ch='\r';
                    else if(ch=='0')ch='\0';else if(ch=='"')ch='"';
                }
                if(j<63)t->sval[j++]=ch;
            }
            if(src[i])i++; t->sval[j]=0; t->kind=T_STRING; n++; continue;
        }
        if(c=='\''){
            i++; int64_t v=0;
            if(src[i]=='\\'){i++;char e=src[i++];if(e=='n')v='\n';else if(e=='t')v='\t';else if(e=='0')v=0;else v=(unsigned char)e;}
            else if(src[i])v=(unsigned char)src[i++];
            while(src[i]&&src[i]!='\'')i++; if(src[i])i++;
            t->kind=T_INT; t->ival=v; n++; continue;
        }
        if(is_digit(c)){
            int64_t v=0;
            if(c=='0'&&(src[i+1]=='x'||src[i+1]=='X')){
                i+=2; while(is_xdigit(src[i]))v=v*16+xval(src[i++]);
            } else {
                while(is_digit(src[i]))v=v*10+(src[i++]-'0');
                if(src[i]=='.'&&is_digit(src[i+1])){
                    double d=(double)v; i++; double frac=0.1;
                    while(is_digit(src[i])){d+=(src[i++]-'0')*frac;frac*=0.1;}
                    if(src[i]=='e'||src[i]=='E'){i++;int neg=0;if(src[i]=='-'){neg=1;i++;}else if(src[i]=='+')i++;int exp=0;while(is_digit(src[i]))exp=exp*10+(src[i++]-'0');double base=neg?0.1:10.0;for(int k=0;k<exp;k++)d*=(neg?0.1:10.0);}
                    uint64_t bits; memcpy(&bits,&d,8); t->ival=(int64_t)bits; t->kind=T_FLOAT; n++; continue;
                }
            }
            if(src[i]=='U'||src[i]=='u'||src[i]=='L'||src[i]=='l')i++;
            if(src[i]=='L'||src[i]=='l')i++;
            t->kind=T_INT; t->ival=v; n++; continue;
        }
        if(is_alpha(c)){
            int j=0; while(is_alnum(src[i])&&j<63)t->sval[j++]=src[i++]; t->sval[j]=0;
            t->kind=T_IDENT;
            for(int k=0;g_kwds[k].kw;k++){if(strcmp(t->sval,g_kwds[k].kw)==0){t->kind=g_kwds[k].tk;break;}}
            n++; continue;
        }
        // operators
        switch(c){
        case'+': if(src[i+1]=='+'){t->kind=T_PLUSPLUS;i+=2;}else if(src[i+1]=='='){t->kind=T_PLUS_EQ;i+=2;}else{t->kind=T_PLUS;i++;}break;
        case'-': if(src[i+1]=='-'){t->kind=T_MINUSMINUS;i+=2;}else if(src[i+1]=='='){t->kind=T_MINUS_EQ;i+=2;}else if(src[i+1]=='>'){t->kind=T_ARROW;i+=2;}else{t->kind=T_MINUS;i++;}break;
        case'*': if(src[i+1]=='='){t->kind=T_STAR_EQ;i+=2;}else{t->kind=T_STAR;i++;}break;
        case'/': if(src[i+1]=='='){t->kind=T_SLASH_EQ;i+=2;}else{t->kind=T_SLASH;i++;}break;
        case'%': if(src[i+1]=='='){t->kind=T_PCT_EQ;i+=2;}else{t->kind=T_PCT;i++;}break;
        case'=': if(src[i+1]=='='){t->kind=T_EQ;i+=2;}else{t->kind=T_ASSIGN;i++;}break;
        case'!': if(src[i+1]=='='){t->kind=T_NE;i+=2;}else{t->kind=T_BANG;i++;}break;
        case'<': if(src[i+1]=='='){t->kind=T_LE;i+=2;}else if(src[i+1]=='<'){t->kind=T_LSHIFT;i+=2;}else{t->kind=T_LT;i++;}break;
        case'>': if(src[i+1]=='='){t->kind=T_GE;i+=2;}else if(src[i+1]=='>'){t->kind=T_RSHIFT;i+=2;}else{t->kind=T_GT;i++;}break;
        case'&': if(src[i+1]=='&'){t->kind=T_AND_AND;i+=2;}else{t->kind=T_AMP;i++;}break;
        case'|': if(src[i+1]=='|'){t->kind=T_OR_OR;i+=2;}else{t->kind=T_PIPE;i++;}break;
        case'^': t->kind=T_CARET;i++;break;
        case'~': t->kind=T_TILDE;i++;break;
        case';': t->kind=T_SEMI;i++;break;
        case',': t->kind=T_COMMA;i++;break;
        case'.': t->kind=T_DOT;i++;break;
        case'(': t->kind=T_LPAREN;i++;break;
        case')': t->kind=T_RPAREN;i++;break;
        case'{': t->kind=T_LBRACE;i++;break;
        case'}': t->kind=T_RBRACE;i++;break;
        case'[': t->kind=T_LBRACKET;i++;break;
        case']': t->kind=T_RBRACKET;i++;break;
        case':': t->kind=T_COLON;i++;break;
        case'?': t->kind=T_QUESTION;i++;break;
        default: i++; continue;
        }
        n++;
    }
    g_toks[n].kind=T_EOF; g_ntoks=n; return n;
}

// ═══════════════════════════════════════════
// AST
// ═══════════════════════════════════════════

typedef enum {
    N_PROGRAM=0, N_FUNCDEF, N_TYPEDEF_ST,
    N_BLOCK, N_RETURN, N_VARDECL,
    N_ASSIGN, N_COMP_ASSIGN,
    N_IF, N_WHILE, N_FOR, N_EXPRSTMT,
    N_BINOP, N_UNARY,
    N_INTLIT, N_FLTLIT, N_STRLIT, N_IDENT,
    N_CALL, N_INDEX, N_FIELD, N_PFIELD,
    N_POST_INC, N_POST_DEC,
    N_PRINT,
} NK;

typedef struct {
    NK      kind;
    int     op;      // TK for BINOP/UNARY/COMP_ASSIGN; struct_idx for VARDECL
    int64_t ival;    // INTLIT value; string literal stored in sval
    int     a,b,c;   // children (-1 = none)
    int     next;    // sibling in block/arglist
    char    name[36];// IDENT name, FUNCDEF name, FIELD name, VARDECL type name
    int     arr_len; // for VARDECL: array length (0 = scalar)
    int     is_ptr;  // for VARDECL: pointer level
} Node;

#define MAX_NODES 8192
static Node g_nodes[MAX_NODES];
static int  g_nnodes;

static int node_new(NK k){
    if(g_nnodes>=MAX_NODES)return -1;
    int i=g_nnodes++; Node*n=&g_nodes[i];
    memset(n,0,sizeof(Node));
    n->kind=k; n->a=n->b=n->c=n->next=-1; n->op=0; return i;
}
#define N(i) (&g_nodes[i])

// ═══════════════════════════════════════════
// PARSER
// ═══════════════════════════════════════════

typedef struct { int cur; int err; } P;
static P g_p;

static Tok *peek(void){ int i=g_p.cur; return i<g_ntoks?&g_toks[i]:&g_toks[g_ntoks>0?g_ntoks-1:0]; }
static Tok *peek2(void){ int i=g_p.cur+1; return i<g_ntoks?&g_toks[i]:&g_toks[g_ntoks>0?g_ntoks-1:0]; }
static Tok *peek3(void){ int i=g_p.cur+2; return i<g_ntoks?&g_toks[i]:&g_toks[g_ntoks>0?g_ntoks-1:0]; }
static Tok *adv(void){ return g_p.cur<g_ntoks?&g_toks[g_p.cur++]:&g_toks[g_ntoks>0?g_ntoks-1:0]; }
static int eat(TK k){ if(peek()->kind==k){adv();return 1;}return 0; }
static int expect_tok(TK k){ if(peek()->kind==k){adv();return 1;}g_p.err=1;return 0; }

// struct table (for typedef struct)
#define MAX_STRUCTS 16
#define MAX_FIELDS  24
typedef struct { char name[32]; int off; int size; int struct_idx; int is_ptr; } FldDef;
typedef struct { char name[32]; int nfields; int size; FldDef fields[MAX_FIELDS]; } StructDef;
static StructDef g_structs[MAX_STRUCTS];
static int g_nstructs;

static int struct_find(const char *name){
    for(int i=0;i<g_nstructs;i++)if(strcmp(g_structs[i].name,name)==0)return i;
    return -1;
}
static int field_find(int si, const char *name){
    if(si<0||si>=g_nstructs)return -1;
    for(int i=0;i<g_structs[si].nfields;i++)
        if(strcmp(g_structs[si].fields[i].name,name)==0)return i;
    return -1;
}

// forward declarations
static int parse_expr(void);
static int parse_stmt(void);
static int parse_block(void);

static int parse_typedef_struct(void){
    // typedef struct { fields } Name;
    adv(); // typedef
    if(!eat(T_STRUCT)){g_p.err=1;return -1;}
    if(g_nstructs>=MAX_STRUCTS)return -1;
    int si=g_nstructs++;
    StructDef *sd=&g_structs[si];
    memset(sd,0,sizeof(StructDef));
    if(peek()->kind==T_IDENT){ strncpy(sd->name,peek()->sval,31); adv(); }
    if(!eat(T_LBRACE)){g_p.err=1;return -1;}
    int off=0;
    while(peek()->kind!=T_RBRACE && peek()->kind!=T_EOF && sd->nfields<MAX_FIELDS){
        // type (optional *) field_name;
        int is_type_kw = is_type_tk(peek()->kind);
        int is_ident = peek()->kind==T_IDENT;
        if(!is_type_kw && !is_ident){adv();continue;}
        char type_name[32]=""; int is_ptr=0; int fsi=-1;
        if(peek()->kind==T_IDENT){
            strncpy(type_name,peek()->sval,31);
            fsi=struct_find(type_name);
        }
        adv(); // consume type
        while(eat(T_STAR))is_ptr++;
        if(peek()->kind!=T_IDENT){g_p.err=1;break;}
        FldDef *fd=&sd->fields[sd->nfields++];
        strncpy(fd->name,peek()->sval,31); adv();
        fd->off=off; fd->is_ptr=is_ptr; fd->struct_idx=fsi;
        // array?
        if(eat(T_LBRACKET)){
            int arr_len=1;
            if(peek()->kind==T_INT){arr_len=(int)peek()->ival;adv();}
            eat(T_RBRACKET);
            // total size for this field
            int elem_size = (fsi>=0&&!is_ptr)?g_structs[fsi].size:8;
            fd->size = elem_size * arr_len;
            off += fd->size;
        } else {
            fd->size = (fsi>=0&&!is_ptr)?g_structs[fsi].size:8;
            off += fd->size;
        }
        eat(T_SEMI);
    }
    eat(T_RBRACE);
    // align to 8 bytes
    sd->size = (off+7)&~7;
    if(sd->size==0)sd->size=8;
    // store name from alias after '}'
    if(peek()->kind==T_IDENT){
        strncpy(sd->name,peek()->sval,31); adv();
    }
    eat(T_SEMI);
    int ni=node_new(N_TYPEDEF_ST);
    strncpy(N(ni)->name,sd->name,35);
    N(ni)->op=si;
    return ni;
}

static int parse_primary(void){
    Tok *t=peek();
    if(t->kind==T_INT){
        int ni=node_new(N_INTLIT); N(ni)->ival=t->ival; adv(); return ni;
    }
    if(t->kind==T_FLOAT){
        int ni=node_new(N_FLTLIT); N(ni)->ival=t->ival; adv(); return ni;
    }
    if(t->kind==T_STRING){
        int ni=node_new(N_STRLIT); strncpy(N(ni)->name,t->sval,35); adv(); return ni;
    }
    if(t->kind==T_IDENT){
        // function call or ident?
        if(peek2()->kind==T_LPAREN){
            int ni=node_new(N_CALL); strncpy(N(ni)->name,t->sval,35); adv(); adv();
            int *tail=&N(ni)->a;
            while(peek()->kind!=T_RPAREN&&peek()->kind!=T_EOF){
                int ai=parse_expr();
                *tail=ai; tail=&N(ai)->next;
                if(!eat(T_COMMA))break;
            }
            eat(T_RPAREN);
            return ni;
        }
        int ni=node_new(N_IDENT); strncpy(N(ni)->name,t->sval,35); adv(); return ni;
    }
    if(t->kind==T_SIZEOF){
        adv(); eat(T_LPAREN);
        int64_t sz=8; // default
        if(is_type_tk(peek()->kind)){
            adv(); // consume type keyword
            eat(T_STAR);
            sz=8;
        } else if(peek()->kind==T_IDENT){
            int si=struct_find(peek()->sval);
            if(si>=0)sz=g_structs[si].size;
            adv();
        }
        eat(T_RPAREN);
        int ni=node_new(N_INTLIT); N(ni)->ival=sz; return ni;
    }
    if(t->kind==T_LPAREN){
        adv(); int ni=parse_expr(); eat(T_RPAREN); return ni;
    }
    // fall through
    int ni=node_new(N_INTLIT); N(ni)->ival=0; return ni;
}

static int parse_postfix(void){
    int base=parse_primary();
    for(;;){
        TK k=peek()->kind;
        if(k==T_PLUSPLUS){adv();int ni=node_new(N_POST_INC);N(ni)->a=base;return ni;}
        if(k==T_MINUSMINUS){adv();int ni=node_new(N_POST_DEC);N(ni)->a=base;return ni;}
        if(k==T_DOT){
            adv();
            if(peek()->kind!=T_IDENT){g_p.err=1;break;}
            int ni=node_new(N_FIELD); N(ni)->a=base;
            strncpy(N(ni)->name,peek()->sval,35); adv();
            base=ni; continue;
        }
        if(k==T_ARROW){
            adv();
            if(peek()->kind!=T_IDENT){g_p.err=1;break;}
            int ni=node_new(N_PFIELD); N(ni)->a=base;
            strncpy(N(ni)->name,peek()->sval,35); adv();
            base=ni; continue;
        }
        if(k==T_LBRACKET){
            adv(); int idx=parse_expr(); eat(T_RBRACKET);
            int ni=node_new(N_INDEX); N(ni)->a=base; N(ni)->b=idx;
            base=ni; continue;
        }
        break;
    }
    return base;
}

static int parse_unary(void){
    TK k=peek()->kind;
    if(k==T_BANG){adv();int a=parse_unary();int ni=node_new(N_UNARY);N(ni)->op=T_BANG;N(ni)->a=a;return ni;}
    if(k==T_MINUS){adv();int a=parse_unary();int ni=node_new(N_UNARY);N(ni)->op=T_MINUS;N(ni)->a=a;return ni;}
    if(k==T_AMP){adv();int a=parse_unary();int ni=node_new(N_UNARY);N(ni)->op=T_AMP;N(ni)->a=a;return ni;}
    if(k==T_STAR){adv();int a=parse_unary();int ni=node_new(N_UNARY);N(ni)->op=T_STAR;N(ni)->a=a;return ni;}
    if(k==T_TILDE){adv();int a=parse_unary();int ni=node_new(N_UNARY);N(ni)->op=T_TILDE;N(ni)->a=a;return ni;}
    if(k==T_PLUSPLUS){adv();int a=parse_unary();int ni=node_new(N_UNARY);N(ni)->op=T_PLUSPLUS;N(ni)->a=a;return ni;}
    if(k==T_MINUSMINUS){adv();int a=parse_unary();int ni=node_new(N_UNARY);N(ni)->op=T_MINUSMINUS;N(ni)->a=a;return ni;}
    return parse_postfix();
}

static int parse_mul(void){
    int lhs=parse_unary();
    for(;;){
        TK k=peek()->kind;
        if(k!=T_STAR&&k!=T_SLASH&&k!=T_PCT)break;
        adv(); int rhs=parse_unary();
        int ni=node_new(N_BINOP); N(ni)->op=k; N(ni)->a=lhs; N(ni)->b=rhs; lhs=ni;
    }
    return lhs;
}
static int parse_add(void){
    int lhs=parse_mul();
    for(;;){
        TK k=peek()->kind;
        if(k!=T_PLUS&&k!=T_MINUS)break;
        adv(); int rhs=parse_mul();
        int ni=node_new(N_BINOP); N(ni)->op=k; N(ni)->a=lhs; N(ni)->b=rhs; lhs=ni;
    }
    return lhs;
}
static int parse_shift(void){
    int lhs=parse_add();
    for(;;){
        TK k=peek()->kind;
        if(k!=T_LSHIFT&&k!=T_RSHIFT)break;
        adv(); int rhs=parse_add();
        int ni=node_new(N_BINOP); N(ni)->op=k; N(ni)->a=lhs; N(ni)->b=rhs; lhs=ni;
    }
    return lhs;
}
static int parse_cmp(void){
    int lhs=parse_shift();
    for(;;){
        TK k=peek()->kind;
        if(k!=T_LT&&k!=T_LE&&k!=T_GT&&k!=T_GE&&k!=T_EQ&&k!=T_NE)break;
        adv(); int rhs=parse_shift();
        int ni=node_new(N_BINOP); N(ni)->op=k; N(ni)->a=lhs; N(ni)->b=rhs; lhs=ni;
    }
    return lhs;
}
static int parse_bitand(void){
    int lhs=parse_cmp();
    while(peek()->kind==T_AMP&&peek2()->kind!=T_AMP){
        adv(); int rhs=parse_cmp();
        int ni=node_new(N_BINOP); N(ni)->op=T_AMP; N(ni)->a=lhs; N(ni)->b=rhs; lhs=ni;
    }
    return lhs;
}
static int parse_bitxor(void){
    int lhs=parse_bitand();
    while(peek()->kind==T_CARET){
        adv(); int rhs=parse_bitand();
        int ni=node_new(N_BINOP); N(ni)->op=T_CARET; N(ni)->a=lhs; N(ni)->b=rhs; lhs=ni;
    }
    return lhs;
}
static int parse_bitor(void){
    int lhs=parse_bitxor();
    while(peek()->kind==T_PIPE&&peek2()->kind!=T_PIPE){
        adv(); int rhs=parse_bitxor();
        int ni=node_new(N_BINOP); N(ni)->op=T_PIPE; N(ni)->a=lhs; N(ni)->b=rhs; lhs=ni;
    }
    return lhs;
}
static int parse_logand(void){
    int lhs=parse_bitor();
    while(peek()->kind==T_AND_AND){
        adv(); int rhs=parse_bitor();
        int ni=node_new(N_BINOP); N(ni)->op=T_AND_AND; N(ni)->a=lhs; N(ni)->b=rhs; lhs=ni;
    }
    return lhs;
}
static int parse_logor(void){
    int lhs=parse_logand();
    while(peek()->kind==T_OR_OR){
        adv(); int rhs=parse_logand();
        int ni=node_new(N_BINOP); N(ni)->op=T_OR_OR; N(ni)->a=lhs; N(ni)->b=rhs; lhs=ni;
    }
    return lhs;
}
static int parse_expr(void){
    // parse lvalue candidates for assignment
    int lhs=parse_logor();
    TK k=peek()->kind;
    if(k==T_ASSIGN){
        adv(); int rhs=parse_expr();
        int ni=node_new(N_ASSIGN); N(ni)->a=lhs; N(ni)->b=rhs; return ni;
    }
    if(k==T_PLUS_EQ||k==T_MINUS_EQ||k==T_STAR_EQ||k==T_SLASH_EQ||k==T_PCT_EQ){
        adv(); int rhs=parse_expr();
        int ni=node_new(N_COMP_ASSIGN); N(ni)->op=(int)k; N(ni)->a=lhs; N(ni)->b=rhs; return ni;
    }
    return lhs;
}

// Detect start of a declaration: type (possibly followed by * or ident)
static int at_decl(void){
    TK k=peek()->kind;
    if(is_type_tk(k))return 1;
    if(k==T_IDENT){
        // could be a struct type name used as declaration
        if(struct_find(peek()->sval)>=0)return 1;
    }
    return 0;
}

static int parse_vardecl(int allow_multi){
    // type [*]* name [= expr] [, name [= expr]] ;
    // type can be keyword or struct name
    TK type_tk=peek()->kind;
    char type_name[32]="";
    int struct_idx=-1;
    if(type_tk==T_IDENT){
        strncpy(type_name,peek()->sval,31);
        struct_idx=struct_find(type_name);
    }
    adv(); // consume type

    int first=-1, *tail=&first;
    for(;;){
        int is_ptr=0; while(eat(T_STAR))is_ptr++;
        if(peek()->kind!=T_IDENT){g_p.err=1;break;}
        int ni=node_new(N_VARDECL);
        strncpy(N(ni)->name,peek()->sval,35); adv();
        strncpy(N(ni)->name+0,N(ni)->name,35); // name already set
        N(ni)->op=struct_idx;  // struct type index
        N(ni)->is_ptr=is_ptr;
        // array?
        if(eat(T_LBRACKET)){
            if(peek()->kind==T_INT){N(ni)->arr_len=(int)peek()->ival;adv();}
            else N(ni)->arr_len=1;
            eat(T_RBRACKET);
        }
        // optional initializer
        if(eat(T_ASSIGN)){
            N(ni)->a=parse_expr();
        }
        *tail=ni; tail=&N(ni)->next;
        if(!allow_multi||!eat(T_COMMA))break;
    }
    eat(T_SEMI);
    return first;
}

static int parse_stmt(void){
    TK k=peek()->kind;
    if(k==T_LBRACE) return parse_block();
    if(k==T_IF){
        adv(); eat(T_LPAREN); int cond=parse_expr(); eat(T_RPAREN);
        int then_b=parse_stmt();
        int else_b=-1; if(eat(T_ELSE))else_b=parse_stmt();
        int ni=node_new(N_IF); N(ni)->a=cond; N(ni)->b=then_b; N(ni)->c=else_b; return ni;
    }
    if(k==T_WHILE){
        adv(); eat(T_LPAREN); int cond=parse_expr(); eat(T_RPAREN);
        int body=parse_stmt();
        int ni=node_new(N_WHILE); N(ni)->a=cond; N(ni)->b=body; return ni;
    }
    if(k==T_FOR){
        adv(); eat(T_LPAREN);
        // init: can be vardecl or expr or empty
        int init=-1;
        if(peek()->kind!=T_SEMI){
            if(at_decl())init=parse_vardecl(0);
            else { init=parse_expr(); eat(T_SEMI); }
        } else eat(T_SEMI);
        // cond
        int cond=-1; if(peek()->kind!=T_SEMI)cond=parse_expr(); eat(T_SEMI);
        // step
        int step=-1; if(peek()->kind!=T_RPAREN)step=parse_expr(); eat(T_RPAREN);
        int body=parse_stmt();
        int ni=node_new(N_FOR); N(ni)->a=init; N(ni)->b=cond; N(ni)->c=step;
        N(ni)->op=body; // reuse op field as body
        return ni;
    }
    if(k==T_RETURN){
        adv(); int ni=node_new(N_RETURN);
        if(peek()->kind!=T_SEMI)N(ni)->a=parse_expr();
        eat(T_SEMI); return ni;
    }
    // declaration
    if(at_decl()){
        return parse_vardecl(1);
    }
    // print stmt: string literal followed by comma-args or just semicolon
    if(k==T_STRING){
        Tok *st=adv();
        int ni=node_new(N_PRINT); strncpy(N(ni)->name,st->sval,35);
        int *tail=&N(ni)->a;
        while(eat(T_COMMA)){
            int ai=parse_expr(); *tail=ai; tail=&N(ai)->next;
        }
        eat(T_SEMI); return ni;
    }
    // expression statement
    int ei=parse_expr();
    eat(T_SEMI);
    int ni=node_new(N_EXPRSTMT); N(ni)->a=ei; return ni;
}

static int parse_block(void){
    eat(T_LBRACE);
    int bi=node_new(N_BLOCK);
    int *tail=&N(bi)->a;
    while(peek()->kind!=T_RBRACE&&peek()->kind!=T_EOF){
        int si=parse_stmt();
        if(si<0){g_p.err=1;break;}
        // chain multiple vardecls
        int last=si;
        while(N(last)->next>=0)last=N(last)->next;
        *tail=si; tail=&N(last)->next;
    }
    eat(T_RBRACE);
    return bi;
}

static int parse_funcdef(void){
    // type [*] name ( params ) block
    TK ret_type=peek()->kind;
    adv(); // consume return type
    int is_ptr=0; while(eat(T_STAR))is_ptr++;
    if(peek()->kind!=T_IDENT){g_p.err=1;return -1;}
    int ni=node_new(N_FUNCDEF);
    strncpy(N(ni)->name,peek()->sval,35); adv();
    N(ni)->is_ptr=ret_type==T_VOID?0:1; // non-void return
    eat(T_LPAREN);
    // parse params
    int nparam=0, *ptail=&N(ni)->a;
    while(peek()->kind!=T_RPAREN&&peek()->kind!=T_EOF){
        if(peek()->kind==T_VOID&&peek2()->kind==T_RPAREN){adv();break;}
        TK ptype=peek()->kind;
        char ptype_name[32]="";
        int psi=-1;
        if(peek()->kind==T_IDENT){strncpy(ptype_name,peek()->sval,31);psi=struct_find(ptype_name);}
        adv(); // type
        int pp=0; while(eat(T_STAR))pp++;
        if(peek()->kind!=T_IDENT){g_p.err=1;break;}
        int pi=node_new(N_VARDECL);
        strncpy(N(pi)->name,peek()->sval,35); adv();
        N(pi)->op=psi; N(pi)->is_ptr=pp;
        eat(T_LBRACKET);eat(T_RBRACKET); // optional []
        *ptail=pi; ptail=&N(pi)->next; nparam++;
        if(!eat(T_COMMA))break;
    }
    eat(T_RPAREN);
    N(ni)->ival=nparam;
    // body
    if(peek()->kind==T_LBRACE){
        N(ni)->b=parse_block();
    } else {
        // bare call form: just semicolon (shouldn't happen for funcdef)
        eat(T_SEMI);
    }
    return ni;
}

static int parse_program(void){
    int prog=node_new(N_PROGRAM);
    int *tail=&N(prog)->a;
    while(peek()->kind!=T_EOF){
        int si=-1;
        TK k=peek()->kind;
        // skip stray semicolons
        if(eat(T_SEMI)) continue;
        if(k==T_TYPEDEF){
            si=parse_typedef_struct();
        } else if(is_type_tk(k)||
                  (k==T_IDENT&&struct_find(peek()->sval)>=0)){
            // Look ahead to see if this is funcdef or vardecl
            // funcdef: type [*] ident '('
            int saved=g_p.cur;
            adv(); // skip type
            while(peek()->kind==T_STAR)adv();
            int is_fn=(peek()->kind==T_IDENT&&peek2()->kind==T_LPAREN);
            g_p.cur=saved;
            if(is_fn) si=parse_funcdef();
            else si=parse_vardecl(1);
        } else if(k==T_IDENT){
            // bare call like "Main;" or funcdef
            if(peek2()->kind==T_LPAREN){
                si=parse_funcdef();
            } else if(peek2()->kind==T_SEMI){
                // bare call
                int ni=node_new(N_EXPRSTMT);
                int ci=node_new(N_CALL); strncpy(N(ci)->name,peek()->sval,35); adv();
                N(ni)->a=ci; eat(T_SEMI); si=ni;
            } else {
                si=parse_stmt();
            }
        } else {
            si=parse_stmt();
        }
        if(si<0){g_p.err=1;break;}
        int last=si;
        while(N(last)->next>=0)last=N(last)->next;
        *tail=si; tail=&N(last)->next;
    }
    return prog;
}

// ═══════════════════════════════════════════
// ARM64 CODE GENERATOR
// ═══════════════════════════════════════════

// ARM64 instruction encodings
#define A64_ADD(d,n,m)    (0x8B000000|((m)<<16)|((n)<<5)|(d))
#define A64_SUB(d,n,m)    (0xCB000000|((m)<<16)|((n)<<5)|(d))
#define A64_AND(d,n,m)    (0x8A000000|((m)<<16)|((n)<<5)|(d))
#define A64_ORR(d,n,m)    (0xAA000000|((m)<<16)|((n)<<5)|(d))
#define A64_EOR(d,n,m)    (0xCA000000|((m)<<16)|((n)<<5)|(d))
#define A64_MUL(d,n,m)    (0x9B007C00|((m)<<16)|((n)<<5)|(d))
#define A64_SDIV(d,n,m)   (0x9AC10C00|((m)<<16)|((n)<<5)|(d))
#define A64_LSLV(d,n,m)   (0x9AC12000|((m)<<16)|((n)<<5)|(d))
#define A64_LSRV(d,n,m)   (0x9AC12400|((m)<<16)|((n)<<5)|(d))
#define A64_NEG(d,m)      (0xCB0003E0|((m)<<16)|(d))
#define A64_MVN(d,m)      (0xAA2003E0|((m)<<16)|(d))
#define A64_MOV(d,m)      (0xAA0003E0|((m)<<16)|(d))
#define A64_CMP(n,m)      (0xEB00001F|((m)<<16)|((n)<<5))
#define A64_STR_U(rt,rn,off)  (0xF9000000|(((off)>>3)<<10)|((rn)<<5)|(rt))
#define A64_LDR_U(rt,rn,off)  (0xF9400000|(((off)>>3)<<10)|((rn)<<5)|(rt))
#define A64_STRB_U(rt,rn,off) (0x39000000|((off)<<10)|((rn)<<5)|(rt))
#define A64_LDRB_U(rt,rn,off) (0x39400000|((off)<<10)|((rn)<<5)|(rt))
// Pre-indexed store (push): str xrt, [sp, #-16]!
#define A64_PUSH(rt)      (0xF81F0FE0|(rt))
// Post-indexed load (pop): ldr xrt, [sp], #16
#define A64_POP(rt)       (0xF84107E0|(rt))
// Branch
#define A64_B(off26)      (0x14000000|((off26)&0x3FFFFFF))
#define A64_BL(off26)     (0x94000000|((off26)&0x3FFFFFF))
#define A64_BCOND(c,off19)(0x54000000|(((off19)&0x7FFFF)<<5)|(c))
#define A64_BLR(rn)       (0xD63F0000|((rn)<<5))
#define A64_RET           0xD65F03C0
// Immediate arithmetic
#define A64_ADD_I(d,n,i)  (0x91000000|((i)<<10)|((n)<<5)|(d))
#define A64_SUB_I(d,n,i)  (0xD1000000|((i)<<10)|((n)<<5)|(d))
// MOVZ/MOVK
#define A64_MOVZ(d,v,sh)  (0xD2800000|(((sh)/16)<<21)|((v)<<5)|(d))
#define A64_MOVK(d,v,sh)  (0xF2800000|(((sh)/16)<<21)|((v)<<5)|(d))
// Frame setup
#define A64_STP_X29X30_SP 0xA9007BFD   // stp x29, x30, [sp]
#define A64_LDP_X29X30_SP 0xA9407BFD   // ldp x29, x30, [sp]
#define A64_MOV_X29_SP    0x910003FD   // add x29, sp, #0
// Shifted add: add xd, xn, xm, lsl #3
#define A64_ADD_LSL3(d,n,m) (0x8B000C00|((m)<<16)|((n)<<5)|(d))
// Load from pointer: ldr xrt, [xrn, #0]
#define A64_LDR_BASE(rt,rn) (0xF9400000|((rn)<<5)|(rt))
// Store to pointer: str xrt, [xrn, #0]
#define A64_STR_BASE(rt,rn) (0xF9000000|((rn)<<5)|(rt))
// NOP
#define A64_NOP           0xD503201F
// CSET: csinc xd, xzr, xzr, inv_cond
static uint32_t a64_cset(int rd, int cond){
    static const int inv[]={1,0,3,2,5,4,7,6,9,8,11,10,13,12,15,14};
    return 0x9A9F07E0|(inv[cond]<<12)|rd;
}
// ARM64 condition codes
#define C_EQ 0
#define C_NE 1
#define C_GE 10
#define C_LT 11
#define C_GT 12
#define C_LE 13

// ADR: adr xd, #off (PC-relative, signed 21-bit)
static uint32_t a64_adr(int rd, int off){
    return 0x10000000|((off&3)<<29)|(((off>>2)&0x7FFFF)<<5)|rd;
}

// CG state (static globals to avoid large stack frame)
#define MAX_SYMS   256
#define MAX_FNS    64
#define MAX_FIXUPS 512
#define DATA_SIZE  65536

typedef struct { char name[32]; int off; int is_ptr; int struct_idx; int arr_len; int elem_size; } Sym;
typedef struct { char name[32]; int off; } FnEntry;
typedef struct { int site; char name[32]; } Fixup;
typedef struct { int site; int data_off; } StrFixup;

static uint8_t   *g_buf;
static int        g_pos, g_cap;
static int        g_err;
static void      *g_pstr, *g_pint;
static void      *g_pchar, *g_puint, *g_pcstr, *g_pptr;
static void      *g_builtins;

static Sym        g_syms[MAX_SYMS];
static int        g_nsyms, g_nparams, g_frame_bytes;
static FnEntry    g_fns[MAX_FNS]; static int g_nfns;
static Fixup      g_fixups[MAX_FIXUPS]; static int g_nfixups;
static StrFixup   g_str_fixups[256]; static int g_nstrfixups;
static uint8_t    g_data[DATA_SIZE]; static int g_datapos, g_datastart;

static void emit32(uint32_t ins){
    if(g_pos+4>g_cap){g_err=1;return;}
    g_buf[g_pos]=(uint8_t)(ins);
    g_buf[g_pos+1]=(uint8_t)(ins>>8);
    g_buf[g_pos+2]=(uint8_t)(ins>>16);
    g_buf[g_pos+3]=(uint8_t)(ins>>24);
    g_pos+=4;
}
static void patch32(int pos, uint32_t ins){
    g_buf[pos]=(uint8_t)(ins);
    g_buf[pos+1]=(uint8_t)(ins>>8);
    g_buf[pos+2]=(uint8_t)(ins>>16);
    g_buf[pos+3]=(uint8_t)(ins>>24);
}
static void emit_movimm(int rd, int64_t v){
    emit32(A64_MOVZ(rd,(uint16_t)(v),0));
    if(v&0xFFFF0000)        emit32(A64_MOVK(rd,(uint16_t)(v>>16),16));
    if(v&0xFFFF00000000LL)  emit32(A64_MOVK(rd,(uint16_t)(v>>32),32));
    if(v&0xFFFF000000000000LL) emit32(A64_MOVK(rd,(uint16_t)(v>>48),48));
}
static void emit_call_abs(uint64_t addr){
    emit_movimm(16,(int64_t)addr);
    emit32(A64_BLR(16));
}
// Load/store from x29 frame
static void emit_ldr_fp(int rt, int off){  emit32(A64_LDR_U(rt,29,off)); }
static void emit_str_fp(int rt, int off){  emit32(A64_STR_U(rt,29,off)); }

static int sym_find(const char *name){
    for(int i=g_nsyms-1;i>=0;i--)if(strcmp(g_syms[i].name,name)==0)return i;
    return -1;
}
static int sym_add(const char *name, int size, int is_ptr, int struct_idx, int arr_len, int elem_size){
    if(g_nsyms>=MAX_SYMS)return -1;
    int i=g_nsyms++;
    strncpy(g_syms[i].name,name,31);
    g_syms[i].off=g_frame_bytes;
    g_syms[i].is_ptr=is_ptr;
    g_syms[i].struct_idx=struct_idx;
    g_syms[i].arr_len=arr_len;
    g_syms[i].elem_size=elem_size;
    g_frame_bytes+=size;
    return i;
}
static int fn_find(const char *name){
    for(int i=0;i<g_nfns;i++)if(strcmp(g_fns[i].name,name)==0)return i;
    return -1;
}
static void fn_add(const char *name, int off){
    if(g_nfns>=MAX_FNS)return;
    strncpy(g_fns[g_nfns].name,name,31); g_fns[g_nfns].off=off; g_nfns++;
}
static void fixup_add(int site, const char *name){
    if(g_nfixups>=MAX_FIXUPS)return;
    g_fixups[g_nfixups].site=site; strncpy(g_fixups[g_nfixups].name,name,31); g_nfixups++;
}
static void resolve_fixups(void){
    for(int i=0;i<g_nfixups;i++){
        int fi=fn_find(g_fixups[i].name); if(fi<0)continue;
        int off=(g_fns[fi].off - g_fixups[i].site)/4;
        patch32(g_fixups[i].site, A64_BL(off));
    }
}
static void strfixup_add(int site, int data_off){
    if(g_nstrfixups>=256)return;
    g_str_fixups[g_nstrfixups].site=site;
    g_str_fixups[g_nstrfixups].data_off=data_off; g_nstrfixups++;
}
static int data_add_str(const char *s){
    int off=g_datapos; int len=0;
    while(s[len]&&g_datapos<DATA_SIZE-1){g_data[g_datapos++]=s[len++];}
    g_data[g_datapos++]=0; // null terminator
    return off;
}

// Builtin lookup: builtins is BuiltinEntry[] {char name[32]; void *fn;} null-terminated
static uint64_t builtin_find(const char *name){
    if(!g_builtins)return 0;
    uint8_t *p=(uint8_t*)g_builtins;
    while(p[0]){ // name[0] != 0
        if(strcmp((char*)p,name)==0){
            uint64_t fn; memcpy(&fn,p+32,8); return fn;
        }
        p+=40; // sizeof BuiltinEntry
    }
    return 0;
}

// forward decl
static void gen_expr(int ni);
static void gen_stmt(int ni);
static void gen_lvalue_addr(int ni); // put address of lvalue in x1

// ── Emit call to a named function (user-defined or builtin) ──
static void emit_named_call(const char *name, int n_args){
    uint64_t baddr=builtin_find(name);
    if(baddr){ emit_call_abs(baddr); return; }
    int fi=fn_find(name);
    if(fi>=0){
        int off=(g_fns[fi].off-g_pos)/4;
        emit32(A64_BL(off));
    } else {
        // forward reference: emit BL placeholder, patch later
        fixup_add(g_pos,name);
        emit32(A64_BL(1));
    }
}

// Generate code for printf-style print
static void gen_print(const char *fmt, int first_arg_ni){
    // Iterate format string, emit calls to print helpers
    const char *p=fmt;
    char seg[64]; int slen=0;
    while(*p){
        if(*p!='%'){if(slen<63)seg[slen]=*p;slen++;p++;continue;}
        // flush segment
        if(slen>0){
            int seglen=slen; if(seglen>63)seglen=63; seg[seglen]=0; slen=0;
            int doff=data_add_str(seg);
            int site=g_pos; emit32(A64_NOP); // placeholder for adr x0, #data
            strfixup_add(site,doff);
            emit_movimm(1,(int64_t)seglen);
            emit_call_abs((uint64_t)g_pstr);
        }
        p++; // skip %
        // skip flags/width/precision
        while(*p=='-'||*p=='+'||*p==' '||*p=='0'||*p=='#')p++;
        while(*p>='0'&&*p<='9')p++;
        if(*p=='.'){p++;while(*p>='0'&&*p<='9')p++;}
        while(*p=='l'||*p=='h'||*p=='z'||*p=='j')p++;
        char spec=*p; if(spec)p++;
        // evaluate the corresponding argument
        if(first_arg_ni>=0){
            gen_expr(first_arg_ni);
            first_arg_ni=N(first_arg_ni)->next;
        } else {
            emit_movimm(0,0);
        }
        // call appropriate print function
        if(spec=='d'||spec=='i'){
            emit_call_abs((uint64_t)g_pint);
        } else if(spec=='u'||spec=='U'){
            emit_call_abs((uint64_t)g_puint);
        } else if(spec=='c'||spec=='C'){
            emit_call_abs((uint64_t)g_pchar);
        } else if(spec=='s'||spec=='S'){
            emit_call_abs((uint64_t)g_pcstr);
        } else if(spec=='p'||spec=='P'){
            emit_call_abs((uint64_t)g_pptr);
        } else if(spec=='x'||spec=='X'){
            emit_call_abs((uint64_t)g_pptr); // reuse ptr printer for hex
        } else if(spec=='f'||spec=='F'){
            // treat as int for now (wrong for floats, but won't crash)
            emit_call_abs((uint64_t)g_pint);
        } else if(spec=='%'){
            // literal percent - print it
            seg[slen++]='%'; // add to next segment
        }
    }
    if(slen>0){
        int seglen=slen; if(seglen>63)seglen=63; seg[seglen]=0;
        int doff=data_add_str(seg);
        int site=g_pos; emit32(A64_NOP);
        strfixup_add(site,doff);
        emit_movimm(1,(int64_t)seglen);
        emit_call_abs((uint64_t)g_pstr);
    }
}

// Generate address of lvalue into x1
static void gen_lvalue_addr(int ni){
    if(ni<0){emit_movimm(1,0);return;}
    Node *n=N(ni);
    if(n->kind==N_IDENT){
        int si=sym_find(n->name);
        if(si<0){emit_movimm(1,0);return;}
        emit32(A64_ADD_I(1,29,g_syms[si].off)); // add x1, x29, #off
    } else if(n->kind==N_INDEX){
        // addr of arr[i]: base_addr + i * elem_size
        // base sym
        if(N(n->a)->kind==N_IDENT){
            int si=sym_find(N(n->a)->name);
            if(si<0){emit_movimm(1,0);return;}
            gen_expr(n->b); // index in x0
            // x1 = x29 + sym_off
            emit32(A64_ADD_I(1,29,g_syms[si].off));
            int esz = g_syms[si].elem_size;
            if(esz==8){
                emit32(A64_ADD_LSL3(1,1,0)); // x1 += x0*8
            } else {
                // generic: mul x0, x0, esz; add x1, x1, x0
                emit_movimm(2,(int64_t)esz);
                emit32(A64_MUL(0,0,2));
                emit32(A64_ADD(1,1,0));
            }
        } else {
            gen_expr(n->a); emit32(A64_MOV(1,0)); // array base in x1
            gen_expr(n->b); // index in x0
            emit32(A64_ADD_LSL3(1,1,0));
        }
    } else if(n->kind==N_FIELD){
        // &(p.field)
        if(N(n->a)->kind==N_IDENT){
            int si=sym_find(N(n->a)->name);
            if(si<0){emit_movimm(1,0);return;}
            int struct_idx=g_syms[si].struct_idx;
            int fi=field_find(struct_idx,n->name);
            int foff=(fi>=0)?g_structs[struct_idx].fields[fi].off:0;
            emit32(A64_ADD_I(1,29,g_syms[si].off+foff));
        }
    } else if(n->kind==N_PFIELD){
        // &(ptr->field)
        gen_expr(n->a); emit32(A64_MOV(1,0)); // ptr value in x1
        // find field offset
        if(N(n->a)->kind==N_IDENT){
            int si=sym_find(N(n->a)->name);
            int struct_idx=(si>=0)?g_syms[si].struct_idx:-1;
            // search all structs for this field name
            if(struct_idx<0){
                for(int s=0;s<g_nstructs&&struct_idx<0;s++){
                    if(field_find(s,n->name)>=0)struct_idx=s;
                }
            }
            int fi=field_find(struct_idx,n->name);
            int foff=(fi>=0)?g_structs[struct_idx].fields[fi].off:0;
            if(foff>0)emit32(A64_ADD_I(1,1,foff));
        }
    } else if(n->kind==N_UNARY&&n->op==T_STAR){
        gen_expr(n->a); emit32(A64_MOV(1,0));
    } else {
        emit_movimm(1,0); // unknown lvalue — treat as null addr
    }
}

static void gen_expr(int ni){
    if(ni<0||g_err){return;}
    Node *n=N(ni);
    switch(n->kind){
    case N_INTLIT:
    case N_FLTLIT:
        emit_movimm(0,n->ival); break;
    case N_STRLIT:{
        int doff=data_add_str(n->name);
        int site=g_pos; emit32(A64_NOP);
        strfixup_add(site,doff);
        break;
    }
    case N_IDENT:{
        int si=sym_find(n->name);
        if(si>=0){
            if(g_syms[si].arr_len>0&&!g_syms[si].is_ptr){
                // array: give address not value
                emit32(A64_ADD_I(0,29,g_syms[si].off));
            } else {
                emit_ldr_fp(0,g_syms[si].off);
            }
        } else {
            // might be a constant (PAGE_SIZE etc.)
            if(strcmp(n->name,"PAGE_SIZE")==0)emit_movimm(0,4096);
            else emit_movimm(0,0);
        }
        break;
    }
    case N_CALL:{
        // Evaluate args left to right, push each
        int nargs=0;
        for(int ai=n->a;ai>=0;ai=N(ai)->next){
            gen_expr(ai);
            emit32(A64_PUSH(0)); // str x0, [sp, #-16]!
            nargs++;
        }
        // Pop args in reverse into x0..x{n-1}
        // After pushing n args: [sp] = arg_{n-1}, [sp+16]=arg_{n-2},...,[sp+(n-1)*16]=arg0
        // We want x0=arg0, x1=arg1, ..., x{n-1}=arg_{n-1}
        for(int i=0;i<nargs&&i<8;i++){
            emit32(A64_LDR_U(i,31,(nargs-1-i)*16)); // ldr xi, [sp, #off]
        }
        if(nargs>0)emit32(A64_ADD_I(31,31,nargs*16)); // add sp, sp, #n*16
        emit_named_call(n->name,nargs);
        break;
    }
    case N_BINOP:{
        // Evaluate left, push, evaluate right, pop left to x1
        gen_expr(n->a); emit32(A64_PUSH(0));
        gen_expr(n->b); emit32(A64_MOV(1,0)); // right in x1
        emit32(A64_POP(0)); // left in x0
        int op=n->op;
        if(op==T_PLUS) emit32(A64_ADD(0,0,1));
        else if(op==T_MINUS) emit32(A64_SUB(0,0,1));
        else if(op==T_STAR) emit32(A64_MUL(0,0,1));
        else if(op==T_SLASH) emit32(A64_SDIV(0,0,1));
        else if(op==T_PCT){ // modulo: a - (a/b)*b
            emit32(A64_PUSH(0)); emit32(A64_PUSH(1)); // save a,b
            emit32(A64_SDIV(2,0,1)); // x2=a/b
            emit32(A64_MUL(2,2,1)); // x2=(a/b)*b
            emit32(A64_POP(1)); emit32(A64_POP(0));
            emit32(A64_SUB(0,0,2));
        }
        else if(op==T_AMP) emit32(A64_AND(0,0,1));
        else if(op==T_PIPE) emit32(A64_ORR(0,0,1));
        else if(op==T_CARET) emit32(A64_EOR(0,0,1));
        else if(op==T_LSHIFT) emit32(A64_LSLV(0,0,1));
        else if(op==T_RSHIFT) emit32(A64_LSRV(0,0,1));
        else if(op==T_LT)  { emit32(A64_CMP(0,1)); emit32(a64_cset(0,C_LT)); }
        else if(op==T_LE)  { emit32(A64_CMP(0,1)); emit32(a64_cset(0,C_LE)); }
        else if(op==T_GT)  { emit32(A64_CMP(0,1)); emit32(a64_cset(0,C_GT)); }
        else if(op==T_GE)  { emit32(A64_CMP(0,1)); emit32(a64_cset(0,C_GE)); }
        else if(op==T_EQ)  { emit32(A64_CMP(0,1)); emit32(a64_cset(0,C_EQ)); }
        else if(op==T_NE)  { emit32(A64_CMP(0,1)); emit32(a64_cset(0,C_NE)); }
        else if(op==T_AND_AND){
            // a&&b: if a==0 return 0, else return b!=0
            emit32(A64_CMP(0,1)); // nope — a is in x0, b in x1
            // actually: 0=false, nonzero=true
            // result = (x0!=0) & (x1!=0)
            emit32(A64_MOVZ(2,0,0));
            int site1=g_pos; emit32(A64_BCOND(C_EQ,0)); // if x0==0, skip
            emit32(A64_MOVZ(2,0,0));
            int site2=g_pos; emit32(A64_BCOND(C_EQ,0)); // if x1==0, skip  wait x1 isn't compared yet
            emit32(A64_MOVZ(2,1,0));
            // patch sites
            patch32(site1, A64_BCOND(C_EQ, (g_pos-site1)/4));
            patch32(site2, A64_BCOND(C_EQ, (g_pos-site2)/4));
            // Hmm, this is wrong. Let me just do: result = (x0!=0)&(x1!=0)
            // Redo: just AND them
            g_pos-=20; // undo the mess
            // simple: return x0 != 0 && x1 != 0
            // cmp x0, #0; cset x0, ne → x0 = (x0!=0)
            emit32(A64_MOVZ(2,0,0)); // x2=0
            emit32(A64_CMP(0,2)); emit32(a64_cset(0,C_NE));
            emit32(A64_CMP(1,2)); emit32(a64_cset(1,C_NE));
            emit32(A64_AND(0,0,1));
        }
        else if(op==T_OR_OR){
            emit32(A64_MOVZ(2,0,0));
            emit32(A64_CMP(0,2)); emit32(a64_cset(0,C_NE));
            emit32(A64_CMP(1,2)); emit32(a64_cset(1,C_NE));
            emit32(A64_ORR(0,0,1));
        }
        break;
    }
    case N_UNARY:{
        int op=n->op;
        if(op==T_MINUS){ gen_expr(n->a); emit32(A64_NEG(0,0)); }
        else if(op==T_BANG){
            gen_expr(n->a);
            emit32(A64_MOVZ(1,0,0));
            emit32(A64_CMP(0,1));
            emit32(a64_cset(0,C_EQ)); // x0 = (x0==0)
        }
        else if(op==T_TILDE){ gen_expr(n->a); emit32(A64_MVN(0,0)); }
        else if(op==T_AMP){ // address-of
            gen_lvalue_addr(n->a); emit32(A64_MOV(0,1));
        }
        else if(op==T_STAR){ // dereference
            gen_expr(n->a); emit32(A64_LDR_BASE(0,0));
        }
        else if(op==T_PLUSPLUS){ // pre-increment
            gen_lvalue_addr(n->a);
            emit32(A64_LDR_BASE(0,1)); // load current
            emit32(A64_ADD_I(0,0,1));  // increment
            emit32(A64_STR_BASE(0,1)); // store back
        }
        else if(op==T_MINUSMINUS){ // pre-decrement
            gen_lvalue_addr(n->a);
            emit32(A64_LDR_BASE(0,1));
            emit32(A64_SUB_I(0,0,1));
            emit32(A64_STR_BASE(0,1));
        }
        break;
    }
    case N_POST_INC:{
        gen_lvalue_addr(n->a);
        emit32(A64_LDR_BASE(0,1)); // load current value (return this)
        emit32(A64_PUSH(0));        // save for return
        emit32(A64_ADD_I(2,0,1));  // x2 = old+1
        emit32(A64_STR_BASE(2,1)); // store back
        emit32(A64_POP(0));         // return old value
        break;
    }
    case N_POST_DEC:{
        gen_lvalue_addr(n->a);
        emit32(A64_LDR_BASE(0,1));
        emit32(A64_PUSH(0));
        emit32(A64_SUB_I(2,0,1));
        emit32(A64_STR_BASE(2,1));
        emit32(A64_POP(0));
        break;
    }
    case N_ASSIGN:{
        gen_expr(n->b);   // value in x0
        emit32(A64_PUSH(0));
        gen_lvalue_addr(n->a); // addr in x1
        emit32(A64_POP(0));
        emit32(A64_STR_BASE(0,1)); // str x0, [x1]
        break;
    }
    case N_COMP_ASSIGN:{
        // x [op]= rhs  →  x = x [op] rhs
        gen_lvalue_addr(n->a); emit32(A64_PUSH(1)); // save addr
        emit32(A64_LDR_BASE(0,1));                  // load current
        emit32(A64_PUSH(0));                         // save lhs
        gen_expr(n->b);                              // rhs in x0
        emit32(A64_MOV(1,0));                        // rhs in x1
        emit32(A64_POP(0));                          // lhs in x0
        int op=n->op;
        if(op==T_PLUS_EQ) emit32(A64_ADD(0,0,1));
        else if(op==T_MINUS_EQ) emit32(A64_SUB(0,0,1));
        else if(op==T_STAR_EQ) emit32(A64_MUL(0,0,1));
        else if(op==T_SLASH_EQ) emit32(A64_SDIV(0,0,1));
        else if(op==T_PCT_EQ){
            emit32(A64_PUSH(0)); emit32(A64_PUSH(1));
            emit32(A64_SDIV(2,0,1)); emit32(A64_MUL(2,2,1));
            emit32(A64_POP(1)); emit32(A64_POP(0)); emit32(A64_SUB(0,0,2));
        }
        // result in x0, now load addr from stack and store
        emit32(A64_POP(1)); // restore addr
        emit32(A64_PUSH(0)); // save result
        emit32(A64_STR_BASE(0,1));
        emit32(A64_POP(0)); // return new value
        break;
    }
    case N_INDEX:{
        gen_lvalue_addr(ni); // addr in x1
        emit32(A64_LDR_BASE(0,1));
        break;
    }
    case N_FIELD:{
        gen_lvalue_addr(ni);
        emit32(A64_LDR_BASE(0,1));
        break;
    }
    case N_PFIELD:{
        gen_lvalue_addr(ni);
        emit32(A64_LDR_BASE(0,1));
        break;
    }
    case N_PRINT:{
        gen_print(n->name, n->a);
        break;
    }
    default: emit_movimm(0,0); break;
    }
}

static void gen_vardecl_stmt(int ni){
    if(ni<0)return;
    Node *n=N(ni);
    // figure out size
    int struct_idx=n->op;
    int is_ptr=n->is_ptr;
    int arr_len=n->arr_len;
    int elem_size=8;
    if(struct_idx>=0&&!is_ptr)elem_size=g_structs[struct_idx].size;
    int total_size;
    if(arr_len>0) total_size=((arr_len*elem_size+15)&~15);
    else total_size=16; // always align to 16 for simplicity
    sym_add(n->name,total_size,is_ptr,struct_idx,arr_len,elem_size);
    int si=sym_find(n->name);
    if(arr_len>0){
        // zero-init array
        // TODO: not strictly necessary but cleaner
    }
    if(n->a>=0){
        // has initializer
        gen_expr(n->a);
        if(si>=0)emit_str_fp(0,g_syms[si].off);
    }
}

static void gen_stmt(int ni){
    if(ni<0||g_err)return;
    Node *n=N(ni);
    switch(n->kind){
    case N_BLOCK:{
        for(int ci=n->a;ci>=0;ci=N(ci)->next)gen_stmt(ci);
        break;
    }
    case N_RETURN:{
        if(n->a>=0)gen_expr(n->a);
        // Epilogue
        emit32(A64_LDP_X29X30_SP);
        emit32(A64_ADD_I(31,31,0)); // add sp, sp, #frame — will be patched
        emit32(A64_RET);
        break;
    }
    case N_VARDECL:
        gen_vardecl_stmt(ni);
        break;
    case N_IF:{
        gen_expr(n->a); // condition in x0
        emit32(A64_MOVZ(1,0,0));
        emit32(A64_CMP(0,1));
        int site_else=g_pos; emit32(A64_BCOND(C_EQ,0)); // jump if false
        gen_stmt(n->b); // then branch
        if(n->c>=0){
            int site_end=g_pos; emit32(A64_B(0)); // jump over else
            patch32(site_else, A64_BCOND(C_EQ,(g_pos-site_else)/4));
            gen_stmt(n->c); // else branch
            patch32(site_end, A64_B((g_pos-site_end)/4));
        } else {
            patch32(site_else, A64_BCOND(C_EQ,(g_pos-site_else)/4));
        }
        break;
    }
    case N_WHILE:{
        int loop_top=g_pos;
        gen_expr(n->a); // condition
        emit32(A64_MOVZ(1,0,0));
        emit32(A64_CMP(0,1));
        int site_end=g_pos; emit32(A64_BCOND(C_EQ,0));
        gen_stmt(n->b); // body
        emit32(A64_B((loop_top-g_pos)/4)); // back to top
        patch32(site_end, A64_BCOND(C_EQ,(g_pos-site_end)/4));
        break;
    }
    case N_FOR:{
        // init
        if(n->a>=0){
            if(N(n->a)->kind==N_VARDECL)gen_stmt(n->a);
            else{gen_expr(n->a);} // expr init
        }
        int loop_top=g_pos;
        // cond
        int site_end=-1;
        if(n->b>=0){
            gen_expr(n->b);
            emit32(A64_MOVZ(1,0,0));
            emit32(A64_CMP(0,1));
            site_end=g_pos; emit32(A64_BCOND(C_EQ,0));
        }
        // body (stored in n->op)
        if(n->op>=0)gen_stmt(n->op);
        // step
        if(n->c>=0)gen_expr(n->c);
        emit32(A64_B((loop_top-g_pos)/4));
        if(site_end>=0)patch32(site_end, A64_BCOND(C_EQ,(g_pos-site_end)/4));
        break;
    }
    case N_EXPRSTMT:{
        if(n->a>=0)gen_expr(n->a);
        break;
    }
    case N_PRINT:{
        gen_print(n->name, n->a);
        break;
    }
    case N_ASSIGN:
    case N_COMP_ASSIGN:
        gen_expr(ni);
        break;
    case N_TYPEDEF_ST: break; // nothing to emit
    default: break;
    }
}

static void gen_func(int ni){
    if(ni<0)return;
    Node *n=N(ni);
    if(n->kind!=N_FUNCDEF)return;
    // Record function
    fn_add(n->name,g_pos);
    // Save sym count for scope cleanup
    int saved_nsyms=g_nsyms;
    int saved_frame=g_frame_bytes;
    // Allocate frame (placeholder)
    int prologue_site=g_pos; emit32(A64_NOP); // sub sp, sp, #frame — patched later
    emit32(A64_STP_X29X30_SP);
    emit32(A64_MOV_X29_SP);
    // store params
    int pi=0;
    for(int ai=n->a;ai>=0&&pi<8;ai=N(ai)->next,pi++){
        if(N(ai)->kind!=N_VARDECL)break;
        sym_add(N(ai)->name,16,N(ai)->is_ptr,N(ai)->op,0,8);
        int si=sym_find(N(ai)->name);
        if(si>=0)emit_str_fp(pi,g_syms[si].off);
    }
    g_nparams=pi;
    // body
    if(n->b>=0)gen_stmt(n->b);
    // Epilogue
    emit32(A64_LDP_X29X30_SP);
    int frame_aligned=(g_frame_bytes+15)&~15;
    emit32(A64_ADD_I(31,31,frame_aligned));
    emit32(A64_RET);
    // Patch frame size
    patch32(prologue_site, A64_SUB_I(31,31,frame_aligned));
    // Now patch any return epilogues inside the body
    // (They were emitted with add sp,sp,#0 — need to fix)
    // Scan and patch: we emitted A64_ADD_I(31,31,0) as placeholder
    // 0xD1000000|( 0 << 10)|(31<<5)|31 = 0x910003FF (add sp,sp,#0)
    // We want: 0xD1000000|(frame_aligned<<10)|(31<<5)|31... wait that's SUB. ADD uses 0x91.
    // For epilogue add sp, sp, #frame: 0x910003FF | (frame_aligned<<10)
    // Scan the function body for these placeholders
    uint32_t add_placeholder=A64_ADD_I(31,31,0); // 0x910003FF
    uint32_t add_real=A64_ADD_I(31,31,frame_aligned);
    int func_end=g_pos;
    // The prologue was emitted at prologue_site. Scan from prologue_site+12 to func_end
    for(int p=prologue_site+12;p<func_end;p+=4){
        uint32_t ins;
        ins = g_buf[p] | (g_buf[p+1]<<8) | (g_buf[p+2]<<16) | (g_buf[p+3]<<24);
        if(ins==add_placeholder)patch32(p,add_real);
    }
    // Restore scope
    g_nsyms=saved_nsyms;
    g_frame_bytes=saved_frame;
}

// Generate a "wrapper" function that calls all top-level calls
static int gen_entry(int prog_ni){
    // fn_add("__entry", g_pos);
    int entry=g_pos;
    // Prologue for entry function
    int prologue_site=g_pos; emit32(A64_NOP);
    emit32(A64_STP_X29X30_SP);
    emit32(A64_MOV_X29_SP);
    g_frame_bytes=16; g_nsyms=0;
    for(int ni=N(prog_ni)->a;ni>=0;ni=N(ni)->next){
        Node *n=N(ni);
        if(n->kind==N_FUNCDEF)continue;
        if(n->kind==N_TYPEDEF_ST)continue;
        // top-level statement / call
        gen_stmt(ni);
    }
    emit32(A64_LDP_X29X30_SP);
    int frame_aligned=(g_frame_bytes+15)&~15;
    emit32(A64_ADD_I(31,31,frame_aligned));
    emit32(A64_RET);
    patch32(prologue_site, A64_SUB_I(31,31,frame_aligned));
    // Patch entry return placeholders
    uint32_t add_ph=A64_ADD_I(31,31,0);
    uint32_t add_real=A64_ADD_I(31,31,frame_aligned);
    for(int p=prologue_site+12;p<g_pos;p+=4){
        uint32_t ins=g_buf[p]|(g_buf[p+1]<<8)|(g_buf[p+2]<<16)|(g_buf[p+3]<<24);
        if(ins==add_ph)patch32(p,add_real);
    }
    return entry;
}

// Public API
typedef struct {
    void *print_str;
    void *print_int;
    void *print_char;
    void *print_uint;
    void *print_cstr;
    void *print_ptr;
    void *builtins;
} HolyCExtra;

int hc_compile(const char *src, uint8_t *buf, int cap, void *extra){
    // Reset state
    g_nnodes=0; g_ntoks=0; g_nstructs=0;
    g_nfns=0; g_nfixups=0; g_nstrfixups=0;
    g_datapos=0; g_datastart=0;
    g_nsyms=0; g_nparams=0; g_frame_bytes=16;
    g_buf=buf; g_pos=0; g_cap=cap; g_err=0;
    if(extra){
        HolyCExtra *e=(HolyCExtra*)extra;
        g_pstr=e->print_str; g_pint=e->print_int;
        g_pchar=e->print_char; g_puint=e->print_uint;
        g_pcstr=e->print_cstr; g_pptr=e->print_ptr;
        g_builtins=e->builtins;
    }

    // Lex
    lex_all(src);
    if(g_ntoks<=0)return -1;

    // Parse
    g_p.cur=0; g_p.err=0;
    int prog=parse_program();
    if(g_p.err)return -2;

    // Codegen: first pass — generate all user-defined functions
    for(int ni=N(prog)->a;ni>=0;ni=N(ni)->next){
        if(N(ni)->kind==N_FUNCDEF){
            g_frame_bytes=16; g_nsyms=0;
            gen_func(ni);
        }
    }

    // Generate entry point (top-level statements)
    int entry=gen_entry(prog);

    // Resolve forward calls
    resolve_fixups();

    // Append string data section
    g_datastart=g_pos;
    if(g_datapos>0){
        if(g_pos+g_datapos<=g_cap){
            memcpy(g_buf+g_pos,g_data,g_datapos);
            g_pos+=g_datapos;
        }
    }

    // Patch string literal ADR instructions
    for(int i=0;i<g_nstrfixups;i++){
        int site=g_str_fixups[i].site;
        int off=(g_datastart+g_str_fixups[i].data_off)-site;
        patch32(site, a64_adr(0,off));
    }

    if(g_err)return -3;
    return entry;
}

// Keep old API for bridge.c compatibility
// The old signature: hc_codegen(arena, root, buf, cap, src, print_str, print_int)
// We'll expose a thin wrapper. But actually bridge.c now calls hc_compile directly.
// Dummy stubs so old object files link (they won't be used):
int hc_lex(const char *src, void *out, int max){ (void)src;(void)out;(void)max; return lex_all(src); }
