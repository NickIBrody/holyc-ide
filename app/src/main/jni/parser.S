// parser.S — recursive-descent HolyC parser in ARM64 assembly.
//
//   int hc_parse(Token *toks, int count, AstNode *arena, int arena_cap,
//                const char *src);
//
// Returns the arena index of the program root (a NODE_BLOCK whose `a`
// field heads a `next`-linked list of top-level items), or -1 on error.
//
// Conventions:
//   * x19 holds the parser context pointer for the whole parse.
//   * Leaf helpers clobber only x0 and x9..x15 (never x16+ / x19+).
//   * Each non-leaf parse function saves x29,x30 plus whatever callee-saved
//     registers (x20..x25) it uses, and returns a node index in x0.
//   * On error ctx.err is set; every loop bails on err so parsing terminates.

// ---- Token types (mirror ast.h) ----
.set TOK_EOF,0
.set TOK_INT_LIT,1
.set TOK_IDENT,2
.set TOK_STRING,3
.set TOK_PLUS,4
.set TOK_MINUS,5
.set TOK_STAR,6
.set TOK_SLASH,7
.set TOK_ASSIGN,8
.set TOK_SEMI,9
.set TOK_LPAREN,10
.set TOK_RPAREN,11
.set TOK_LBRACE,12
.set TOK_RBRACE,13
.set TOK_COMMA,14
.set TOK_LT,15
.set TOK_GT,16
.set TOK_LE,17
.set TOK_GE,18
.set TOK_EQEQ,19
.set TOK_NE,20
.set TOK_U0,21
.set TOK_I64,22
.set TOK_RETURN,23
.set TOK_IF,24
.set TOK_ELSE,25
.set TOK_WHILE,26

// ---- Node types ----
.set NODE_FUNCDEF,1
.set NODE_PARAM,2
.set NODE_BLOCK,3
.set NODE_RETURN,4
.set NODE_VARDECL,5
.set NODE_ASSIGN,6
.set NODE_IF,7
.set NODE_WHILE,8
.set NODE_BINOP,9
.set NODE_INTLIT,10
.set NODE_IDENT,11
.set NODE_CALL,12
.set NODE_PRINT,13
.set NODE_EXPRSTMT,14

// ---- struct offsets ----
.set TOKSZ,24
.set T_TYPE,0
.set T_START,4
.set T_LEN,8
.set T_IVAL,16

.set NODESZ,64
.set N_TYPE,0
.set N_OP,4
.set N_IVAL,8
.set N_A,16
.set N_B,20
.set N_C,24
.set N_NEXT,28
.set N_NAME,32

.set C_TOKS,0
.set C_ARENA,8
.set C_COUNT,16
.set C_CUR,20
.set C_NARENA,24
.set C_CAP,28
.set C_ERR,32
.set C_SRC,40
.set CTXSZ,48

.text
.global hc_parse
.type hc_parse, %function
hc_parse:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    sub     sp, sp, #CTXSZ
    mov     x19, sp
    str     x0, [x19, #C_TOKS]
    str     x2, [x19, #C_ARENA]
    str     w1, [x19, #C_COUNT]
    str     wzr, [x19, #C_CUR]
    mov     w9, #1                  // node index 0 reserved as "none"
    str     w9, [x19, #C_NARENA]
    str     w3, [x19, #C_CAP]
    str     wzr, [x19, #C_ERR]
    str     x4, [x19, #C_SRC]

    bl      parse_program
    mov     x9, x0                  // root
    ldr     w10, [x19, #C_ERR]
    cbz     w10, 1f
    mov     x9, #-1
1:  mov     x0, x9
    add     sp, sp, #CTXSZ
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// ============================================================
//  Leaf helpers (x19 = ctx)
// ============================================================
pt_type:                            // w0 = type of current token
    ldrsw   x10, [x19, #C_CUR]
    ldrsw   x11, [x19, #C_COUNT]
    cmp     x10, x11
    b.ge    1f
    ldr     x9, [x19, #C_TOKS]
    mov     x12, #TOKSZ
    madd    x9, x10, x12, x9
    ldr     w0, [x9, #T_TYPE]
    ret
1:  mov     w0, #TOK_EOF
    ret

pt_type_ahead:                      // w0 = type of token at cur+w0
    sxtw    x13, w0
    ldrsw   x10, [x19, #C_CUR]
    add     x10, x10, x13
    ldrsw   x11, [x19, #C_COUNT]
    cmp     x10, x11
    b.ge    1f
    ldr     x9, [x19, #C_TOKS]
    mov     x12, #TOKSZ
    madd    x9, x10, x12, x9
    ldr     w0, [x9, #T_TYPE]
    ret
1:  mov     w0, #TOK_EOF
    ret

pt_addr:                            // x0 = address of current token
    ldrsw   x10, [x19, #C_CUR]
    ldr     x9, [x19, #C_TOKS]
    mov     x12, #TOKSZ
    madd    x0, x10, x12, x9
    ret

padv:                               // cursor++
    ldr     w9, [x19, #C_CUR]
    add     w9, w9, #1
    str     w9, [x19, #C_CUR]
    ret

pexpect:                            // expect type w0, advance or set err
    ldrsw   x10, [x19, #C_CUR]
    ldrsw   x11, [x19, #C_COUNT]
    cmp     x10, x11
    b.ge    1f
    ldr     x9, [x19, #C_TOKS]
    mov     x12, #TOKSZ
    madd    x9, x10, x12, x9
    ldr     w13, [x9, #T_TYPE]
    cmp     w13, w0
    b.ne    1f
    add     w10, w10, #1
    str     w10, [x19, #C_CUR]
    ret
1:  mov     w13, #1
    str     w13, [x19, #C_ERR]
    ret

new_node:                           // w0 = type -> x0 = index
    ldr     w9, [x19, #C_NARENA]
    ldr     w10, [x19, #C_CAP]
    cmp     w9, w10
    b.ge    1f
    ldr     x11, [x19, #C_ARENA]
    sxtw    x14, w9
    mov     x12, #NODESZ
    madd    x13, x14, x12, x11
    stp     xzr, xzr, [x13, #0]
    stp     xzr, xzr, [x13, #16]
    stp     xzr, xzr, [x13, #32]
    stp     xzr, xzr, [x13, #48]
    str     w0, [x13, #N_TYPE]
    add     w14, w9, #1
    str     w14, [x19, #C_NARENA]
    mov     w0, w9
    ret
1:  mov     w13, #1
    str     w13, [x19, #C_ERR]
    mov     w0, #0
    ret

node_addr:                          // w0 = index -> x0 = address
    ldr     x11, [x19, #C_ARENA]
    sxtw    x14, w0
    mov     x12, #NODESZ
    madd    x0, x14, x12, x11
    ret

copy_name:                          // x0 = node addr, x1 = token addr
    ldr     w9, [x1, #T_START]
    ldr     w10, [x1, #T_LEN]
    ldr     x11, [x19, #C_SRC]
    add     x11, x11, w9, sxtw
    add     x12, x0, #N_NAME
    mov     w13, #31
    cmp     w10, w13
    csel    w10, w10, w13, le
    mov     w14, #0
1:  cmp     w14, w10
    b.ge    2f
    ldrb    w15, [x11, w14, uxtw]
    strb    w15, [x12, w14, uxtw]
    add     w14, w14, #1
    b       1b
2:  strb    wzr, [x12, w14, uxtw]
    ret

// ============================================================
//  parse_program -> x0 = program block index
//    x20 = program, x21 = last item
// ============================================================
parse_program:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x20, x21, [sp, #16]
    stp     x22, x23, [sp, #32]
    mov     w0, #NODE_BLOCK
    bl      new_node
    mov     x20, x0
    mov     x21, #0
1:  ldr     w9, [x19, #C_ERR]
    cbnz    w9, 3f
    bl      pt_type
    cmp     w0, #TOK_EOF
    b.eq    3f
    bl      parse_item
    mov     x22, x0                 // item idx
    cbz     w21, 2f
    mov     w0, w21
    bl      node_addr
    str     w22, [x0, #N_NEXT]
    mov     x21, x22
    b       1b
2:  mov     w0, w20
    bl      node_addr
    str     w22, [x0, #N_A]
    mov     x21, x22
    b       1b
3:  mov     x0, x20
    ldp     x22, x23, [sp, #32]
    ldp     x20, x21, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// ============================================================
//  parse_item -> x0 = node idx
// ============================================================
parse_item:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    bl      pt_type
    cmp     w0, #TOK_I64
    b.eq    1f
    cmp     w0, #TOK_U0
    b.eq    1f
    bl      parse_stmt
    b       2f
1:  mov     w0, #1
    bl      pt_type_ahead
    cmp     w0, #TOK_IDENT
    b.ne    3f
    mov     w0, #2
    bl      pt_type_ahead
    cmp     w0, #TOK_LPAREN
    b.ne    3f
    bl      parse_funcdef
    b       2f
3:  bl      parse_stmt
2:  ldp     x29, x30, [sp], #16
    ret

// ============================================================
//  parse_funcdef -> x0 = NODE_FUNCDEF idx
//    x20 = funcdef, x21 = last param, x22 = scratch, x23 = new param idx
// ============================================================
parse_funcdef:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x20, x21, [sp, #16]
    stp     x22, x23, [sp, #32]
    bl      padv                    // consume return type
    mov     w0, #NODE_FUNCDEF
    bl      new_node
    mov     x20, x0
    bl      pt_addr                 // ident token addr
    mov     x1, x0
    mov     w0, w20
    bl      node_addr
    bl      copy_name
    bl      padv                    // consume ident
    mov     w0, #TOK_LPAREN
    bl      pexpect
    mov     x21, #0
1:  ldr     w9, [x19, #C_ERR]
    cbnz    w9, 4f
    bl      pt_type
    cmp     w0, #TOK_RPAREN
    b.eq    4f
    bl      padv                    // consume param type
    bl      pt_addr
    mov     x22, x0                 // ident token addr
    mov     w0, #NODE_PARAM
    bl      new_node
    mov     x23, x0
    mov     w0, w23
    bl      node_addr
    mov     x1, x22
    bl      copy_name
    cbz     w21, 2f
    mov     w0, w21
    bl      node_addr
    str     w23, [x0, #N_NEXT]
    b       3f
2:  mov     w0, w20
    bl      node_addr
    str     w23, [x0, #N_A]
3:  mov     x21, x23
    bl      padv                    // consume param ident
    bl      pt_type
    cmp     w0, #TOK_COMMA
    b.ne    1b
    bl      padv
    b       1b
4:  mov     w0, #TOK_RPAREN
    bl      pexpect
    bl      parse_block
    mov     x22, x0                 // body
    mov     w0, w20
    bl      node_addr
    str     w22, [x0, #N_B]
    mov     x0, x20
    ldp     x22, x23, [sp, #32]
    ldp     x20, x21, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// ============================================================
//  parse_block -> x0 = NODE_BLOCK idx
//    x20 = block, x21 = last stmt, x22 = scratch
// ============================================================
parse_block:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x20, x21, [sp, #16]
    stp     x22, x23, [sp, #32]
    mov     w0, #TOK_LBRACE
    bl      pexpect
    mov     w0, #NODE_BLOCK
    bl      new_node
    mov     x20, x0
    mov     x21, #0
1:  ldr     w9, [x19, #C_ERR]
    cbnz    w9, 4f
    bl      pt_type
    cmp     w0, #TOK_RBRACE
    b.eq    4f
    cmp     w0, #TOK_EOF
    b.eq    4f
    bl      parse_stmt
    mov     x22, x0
    cbz     w21, 2f
    mov     w0, w21
    bl      node_addr
    str     w22, [x0, #N_NEXT]
    b       3f
2:  mov     w0, w20
    bl      node_addr
    str     w22, [x0, #N_A]
3:  mov     x21, x22
    b       1b
4:  mov     w0, #TOK_RBRACE
    bl      pexpect
    mov     x0, x20
    ldp     x22, x23, [sp, #32]
    ldp     x20, x21, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// ============================================================
//  parse_stmt -> x0 = node idx
//    x20 = node, x21 = scratch child, x22 = scratch
// ============================================================
parse_stmt:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x20, x21, [sp, #16]
    stp     x22, x23, [sp, #32]
    bl      pt_type
    mov     w23, w0                 // first token type
    cmp     w23, #TOK_RETURN
    b.eq    .Lst_return
    cmp     w23, #TOK_IF
    b.eq    .Lst_if
    cmp     w23, #TOK_WHILE
    b.eq    .Lst_while
    cmp     w23, #TOK_LBRACE
    b.eq    .Lst_block
    cmp     w23, #TOK_I64
    b.eq    .Lst_vardecl
    cmp     w23, #TOK_U0
    b.eq    .Lst_vardecl
    cmp     w23, #TOK_STRING
    b.eq    .Lst_print
    cmp     w23, #TOK_IDENT
    b.eq    .Lst_ident
    // fallback: expression statement
    b       .Lst_expr

.Lst_return:
    bl      padv
    mov     w0, #NODE_RETURN
    bl      new_node
    mov     x20, x0
    bl      parse_expr
    mov     x21, x0
    mov     w0, w20
    bl      node_addr
    str     w21, [x0, #N_A]
    mov     w0, #TOK_SEMI
    bl      pexpect
    b       .Lst_done

.Lst_if:
    bl      padv
    mov     w0, #TOK_LPAREN
    bl      pexpect
    mov     w0, #NODE_IF
    bl      new_node
    mov     x20, x0
    bl      parse_expr              // cond
    mov     x21, x0
    mov     w0, w20
    bl      node_addr
    str     w21, [x0, #N_A]
    mov     w0, #TOK_RPAREN
    bl      pexpect
    bl      parse_stmt              // then
    mov     x21, x0
    mov     w0, w20
    bl      node_addr
    str     w21, [x0, #N_B]
    bl      pt_type
    cmp     w0, #TOK_ELSE
    b.ne    .Lst_done
    bl      padv
    bl      parse_stmt              // else
    mov     x21, x0
    mov     w0, w20
    bl      node_addr
    str     w21, [x0, #N_C]
    b       .Lst_done

.Lst_while:
    bl      padv
    mov     w0, #TOK_LPAREN
    bl      pexpect
    mov     w0, #NODE_WHILE
    bl      new_node
    mov     x20, x0
    bl      parse_expr
    mov     x21, x0
    mov     w0, w20
    bl      node_addr
    str     w21, [x0, #N_A]
    mov     w0, #TOK_RPAREN
    bl      pexpect
    bl      parse_stmt
    mov     x21, x0
    mov     w0, w20
    bl      node_addr
    str     w21, [x0, #N_B]
    b       .Lst_done

.Lst_block:
    bl      parse_block
    mov     x20, x0
    b       .Lst_done

.Lst_vardecl:
    bl      padv                    // consume type
    mov     w0, #NODE_VARDECL
    bl      new_node
    mov     x20, x0
    bl      pt_addr                 // ident token
    mov     x1, x0
    mov     w0, w20
    bl      node_addr
    bl      copy_name
    bl      padv                    // consume ident
    bl      pt_type
    cmp     w0, #TOK_ASSIGN
    b.ne    .Lst_vd_semi
    bl      padv
    bl      parse_expr
    mov     x21, x0
    mov     w0, w20
    bl      node_addr
    str     w21, [x0, #N_A]
.Lst_vd_semi:
    mov     w0, #TOK_SEMI
    bl      pexpect
    b       .Lst_done

.Lst_print:
    mov     w0, #NODE_PRINT
    bl      new_node
    mov     x20, x0
    bl      pt_addr                 // string token
    ldr     w9, [x0, #T_START]
    ldr     w10, [x0, #T_LEN]
    mov     w0, w20
    bl      node_addr
    str     w9, [x0, #N_IVAL]       // string start offset
    str     w10, [x0, #N_C]         // string length
    bl      padv                    // consume string
    mov     x21, #0                 // last arg
.Lst_pr_args:
    ldr     w9, [x19, #C_ERR]
    cbnz    w9, .Lst_pr_semi
    bl      pt_type
    cmp     w0, #TOK_COMMA
    b.ne    .Lst_pr_semi
    bl      padv
    bl      parse_expr
    mov     x22, x0
    cbz     w21, .Lst_pr_first
    mov     w0, w21
    bl      node_addr
    str     w22, [x0, #N_NEXT]
    b       .Lst_pr_link
.Lst_pr_first:
    mov     w0, w20
    bl      node_addr
    str     w22, [x0, #N_A]
.Lst_pr_link:
    mov     x21, x22
    b       .Lst_pr_args
.Lst_pr_semi:
    mov     w0, #TOK_SEMI
    bl      pexpect
    b       .Lst_done

.Lst_ident:
    mov     w0, #1
    bl      pt_type_ahead
    cmp     w0, #TOK_ASSIGN
    b.eq    .Lst_assign
    cmp     w0, #TOK_SEMI
    b.eq    .Lst_barecall
    b       .Lst_expr

.Lst_assign:
    mov     w0, #NODE_ASSIGN
    bl      new_node
    mov     x20, x0
    bl      pt_addr
    mov     x1, x0
    mov     w0, w20
    bl      node_addr
    bl      copy_name
    bl      padv                    // ident
    bl      padv                    // '='
    bl      parse_expr
    mov     x21, x0
    mov     w0, w20
    bl      node_addr
    str     w21, [x0, #N_A]
    mov     w0, #TOK_SEMI
    bl      pexpect
    b       .Lst_done

.Lst_barecall:
    mov     w0, #NODE_CALL
    bl      new_node
    mov     x21, x0                 // call node
    bl      pt_addr
    mov     x1, x0
    mov     w0, w21
    bl      node_addr
    bl      copy_name
    bl      padv                    // ident
    // wrap in exprstmt
    mov     w0, #NODE_EXPRSTMT
    bl      new_node
    mov     x20, x0
    mov     w0, w20
    bl      node_addr
    str     w21, [x0, #N_A]
    mov     w0, #TOK_SEMI
    bl      pexpect
    b       .Lst_done

.Lst_expr:
    mov     w0, #NODE_EXPRSTMT
    bl      new_node
    mov     x20, x0
    bl      parse_expr
    mov     x21, x0
    mov     w0, w20
    bl      node_addr
    str     w21, [x0, #N_A]
    mov     w0, #TOK_SEMI
    bl      pexpect
    b       .Lst_done

.Lst_done:
    mov     x0, x20
    ldp     x22, x23, [sp, #32]
    ldp     x20, x21, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// ============================================================
//  Expression grammar (precedence climbing)
//    parse_expr -> parse_cmp -> parse_add -> parse_term -> parse_factor
//  Each binop level: x20 = left node, x23 = op type, x22 = binop node
// ============================================================
parse_expr:
    b       parse_cmp

parse_cmp:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x20, x21, [sp, #16]
    stp     x22, x23, [sp, #32]
    bl      parse_add
    mov     x20, x0
1:  ldr     w9, [x19, #C_ERR]
    cbnz    w9, 2f
    bl      pt_type
    sub     w9, w0, #TOK_LT         // LT..NE == 15..20
    cmp     w9, #5
    b.hi    2f
    mov     w23, w0                 // op
    bl      padv
    bl      parse_add
    mov     x21, x0                 // right
    mov     w0, #NODE_BINOP
    bl      new_node
    mov     x22, x0
    mov     w0, w22
    bl      node_addr
    str     w23, [x0, #N_OP]
    str     w20, [x0, #N_A]
    str     w21, [x0, #N_B]
    mov     x20, x22
    b       1b
2:  mov     x0, x20
    ldp     x22, x23, [sp, #32]
    ldp     x20, x21, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

parse_add:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x20, x21, [sp, #16]
    stp     x22, x23, [sp, #32]
    bl      parse_term
    mov     x20, x0
1:  ldr     w9, [x19, #C_ERR]
    cbnz    w9, 2f
    bl      pt_type
    sub     w9, w0, #TOK_PLUS       // PLUS..MINUS == 4..5
    cmp     w9, #1
    b.hi    2f
    mov     w23, w0
    bl      padv
    bl      parse_term
    mov     x21, x0
    mov     w0, #NODE_BINOP
    bl      new_node
    mov     x22, x0
    mov     w0, w22
    bl      node_addr
    str     w23, [x0, #N_OP]
    str     w20, [x0, #N_A]
    str     w21, [x0, #N_B]
    mov     x20, x22
    b       1b
2:  mov     x0, x20
    ldp     x22, x23, [sp, #32]
    ldp     x20, x21, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

parse_term:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x20, x21, [sp, #16]
    stp     x22, x23, [sp, #32]
    bl      parse_factor
    mov     x20, x0
1:  ldr     w9, [x19, #C_ERR]
    cbnz    w9, 2f
    bl      pt_type
    sub     w9, w0, #TOK_STAR       // STAR..SLASH == 6..7
    cmp     w9, #1
    b.hi    2f
    mov     w23, w0
    bl      padv
    bl      parse_factor
    mov     x21, x0
    mov     w0, #NODE_BINOP
    bl      new_node
    mov     x22, x0
    mov     w0, w22
    bl      node_addr
    str     w23, [x0, #N_OP]
    str     w20, [x0, #N_A]
    str     w21, [x0, #N_B]
    mov     x20, x22
    b       1b
2:  mov     x0, x20
    ldp     x22, x23, [sp, #32]
    ldp     x20, x21, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// ============================================================
//  parse_factor -> x0 = node idx
//    x20 = node, x21 = scratch (call args), x22 = scratch
// ============================================================
parse_factor:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x20, x21, [sp, #16]
    stp     x22, x23, [sp, #32]
    bl      pt_type
    mov     w23, w0
    cmp     w23, #TOK_INT_LIT
    b.eq    .Lf_int
    cmp     w23, #TOK_MINUS
    b.eq    .Lf_neg
    cmp     w23, #TOK_LPAREN
    b.eq    .Lf_paren
    cmp     w23, #TOK_IDENT
    b.eq    .Lf_ident
    // error
    mov     w9, #1
    str     w9, [x19, #C_ERR]
    mov     x20, #0
    b       .Lf_done

.Lf_int:
    mov     w0, #NODE_INTLIT
    bl      new_node
    mov     x20, x0
    bl      pt_addr
    ldr     x9, [x0, #T_IVAL]
    mov     w0, w20
    bl      node_addr
    str     x9, [x0, #N_IVAL]
    bl      padv
    b       .Lf_done

.Lf_neg:                            // unary minus => 0 - factor
    bl      padv
    mov     w0, #NODE_INTLIT
    bl      new_node
    mov     x21, x0                 // zero literal (ival already 0)
    bl      parse_factor
    mov     x22, x0                 // operand
    mov     w0, #NODE_BINOP
    bl      new_node
    mov     x20, x0
    mov     w0, w20
    bl      node_addr
    mov     w9, #TOK_MINUS
    str     w9, [x0, #N_OP]
    str     w21, [x0, #N_A]
    str     w22, [x0, #N_B]
    b       .Lf_done

.Lf_paren:
    bl      padv
    bl      parse_expr
    mov     x20, x0
    mov     w0, #TOK_RPAREN
    bl      pexpect
    b       .Lf_done

.Lf_ident:
    mov     w0, #1
    bl      pt_type_ahead
    cmp     w0, #TOK_LPAREN
    b.eq    .Lf_call
    // plain identifier reference
    mov     w0, #NODE_IDENT
    bl      new_node
    mov     x20, x0
    bl      pt_addr
    mov     x1, x0
    mov     w0, w20
    bl      node_addr
    bl      copy_name
    bl      padv
    b       .Lf_done

.Lf_call:
    mov     w0, #NODE_CALL
    bl      new_node
    mov     x20, x0
    bl      pt_addr
    mov     x1, x0
    mov     w0, w20
    bl      node_addr
    bl      copy_name
    bl      padv                    // ident
    bl      padv                    // '('
    mov     x21, #0                 // last arg
1:  ldr     w9, [x19, #C_ERR]
    cbnz    w9, 4f
    bl      pt_type
    cmp     w0, #TOK_RPAREN
    b.eq    4f
    bl      parse_expr
    mov     x22, x0
    cbz     w21, 2f
    mov     w0, w21
    bl      node_addr
    str     w22, [x0, #N_NEXT]
    b       3f
2:  mov     w0, w20
    bl      node_addr
    str     w22, [x0, #N_A]
3:  mov     x21, x22
    bl      pt_type
    cmp     w0, #TOK_COMMA
    b.ne    1b
    bl      padv
    b       1b
4:  mov     w0, #TOK_RPAREN
    bl      pexpect
    b       .Lf_done

.Lf_done:
    mov     x0, x20
    ldp     x22, x23, [sp, #32]
    ldp     x20, x21, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
