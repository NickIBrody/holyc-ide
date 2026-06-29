// lexer.S — HolyC tokenizer in ARM64 assembly.
//
//   int hc_lex(const char *src, Token *out, int max_tokens);
//
// Returns the number of tokens written (including the trailing TOK_EOF),
// or a negative value on error.
//
// Token layout (24 bytes, see ast.h):
//   +0  int32 type
//   +4  int32 start   (byte offset into src)
//   +8  int32 len
//   +12 int32 pad
//   +16 int64 ival    (TOK_INT_LIT only)

.set TOK_EOF,      0
.set TOK_INT_LIT,  1
.set TOK_IDENT,    2
.set TOK_STRING,   3
.set TOK_PLUS,     4
.set TOK_MINUS,    5
.set TOK_STAR,     6
.set TOK_SLASH,    7
.set TOK_ASSIGN,   8
.set TOK_SEMI,     9
.set TOK_LPAREN,   10
.set TOK_RPAREN,   11
.set TOK_LBRACE,   12
.set TOK_RBRACE,   13
.set TOK_COMMA,    14
.set TOK_LT,       15
.set TOK_GT,       16
.set TOK_LE,       17
.set TOK_GE,       18
.set TOK_EQEQ,     19
.set TOK_NE,       20
.set TOK_U0,       21
.set TOK_I64,      22
.set TOK_RETURN,   23
.set TOK_IF,       24
.set TOK_ELSE,     25
.set TOK_WHILE,    26

.set TOKSZ, 24

.text
.global hc_lex
.type hc_lex, %function

// Register allocation (callee-saved, restored on exit):
//   x19 = src base
//   x20 = cursor
//   x21 = out pointer
//   x22 = max_tokens
//   x23 = token count
//   x24 = scratch / token start pointer
hc_lex:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0
    mov     x20, x0
    mov     x21, x1
    mov     x22, x2
    mov     x23, #0

.Lloop:
    // skip whitespace / comments
.Lskip:
    ldrb    w9, [x20]
    cmp     w9, #' '
    b.eq    .Ladv
    cmp     w9, #9          // \t
    b.eq    .Ladv
    cmp     w9, #10         // \n
    b.eq    .Ladv
    cmp     w9, #13         // \r
    b.eq    .Ladv
    cmp     w9, #'/'
    b.ne    .Lskipdone
    ldrb    w10, [x20, #1]
    cmp     w10, #'/'
    b.eq    .Llinecomment
    cmp     w10, #'*'
    b.eq    .Lblockcomment
    b       .Lskipdone
.Ladv:
    add     x20, x20, #1
    b       .Lskip
.Llinecomment:
    add     x20, x20, #2
.Llc1:
    ldrb    w9, [x20]
    cbz     w9, .Lskipdone
    cmp     w9, #10
    b.eq    .Ladv           // consume newline, keep skipping
    add     x20, x20, #1
    b       .Llc1
.Lblockcomment:
    add     x20, x20, #2
.Lbc1:
    ldrb    w9, [x20]
    cbz     w9, .Lskipdone
    cmp     w9, #'*'
    b.ne    .Lbcadv
    ldrb    w10, [x20, #1]
    cmp     w10, #'/'
    b.eq    .Lbcend
.Lbcadv:
    add     x20, x20, #1
    b       .Lbc1
.Lbcend:
    add     x20, x20, #2
    b       .Lskip
.Lskipdone:

    // out of room? (need a slot for this token plus the final EOF)
    add     x9, x23, #1
    cmp     x9, x22
    b.ge    .Lerr

    ldrb    w9, [x20]
    cbz     w9, .Lemit_eof

    // ---- digit? ----
    sub     w10, w9, #'0'
    cmp     w10, #9
    b.hi    .Lnot_digit
    // parse integer literal
    mov     x24, x20        // start
    mov     x11, #0         // value
.Lnumloop:
    ldrb    w9, [x20]
    sub     w10, w9, #'0'
    cmp     w10, #9
    b.hi    .Lnumdone
    mov     x12, #10
    mul     x11, x11, x12
    add     x11, x11, w10, uxtw
    add     x20, x20, #1
    b       .Lnumloop
.Lnumdone:
    mov     w0, #TOK_INT_LIT
    str     w0, [x21, #0]
    sub     x9, x24, x19
    str     w9, [x21, #4]
    sub     x9, x20, x24
    str     w9, [x21, #8]
    str     wzr, [x21, #12]
    str     x11, [x21, #16]
    add     x21, x21, #TOKSZ
    add     x23, x23, #1
    b       .Lloop

.Lnot_digit:
    // ---- identifier / keyword? ----  [A-Za-z_]
    bl      .Lis_idstart
    cbz     w0, .Lnot_ident
    mov     x24, x20
.Lidloop:
    ldrb    w9, [x20]
    bl      .Lis_idcont
    cbz     w0, .Lidend
    add     x20, x20, #1
    b       .Lidloop
.Lidend:
    sub     w13, w20, w24   // length (fits in 32 bits)
    mov     w0, #TOK_IDENT  // default
    cmp     w13, #2
    b.eq    .Lkw2
    cmp     w13, #3
    b.eq    .Lkw3
    cmp     w13, #4
    b.eq    .Lkw4
    cmp     w13, #5
    b.eq    .Lkw5
    cmp     w13, #6
    b.eq    .Lkw6
    b       .Lid_emit
.Lkw2:
    ldrb    w9, [x24]
    ldrb    w10, [x24, #1]
    // "U0"
    cmp     w9, #'U'
    b.ne    .Lkw2_if
    cmp     w10, #'0'
    b.ne    .Lkw2_if
    mov     w0, #TOK_U0
    b       .Lid_emit
.Lkw2_if:
    cmp     w9, #'i'
    b.ne    .Lid_emit
    cmp     w10, #'f'
    b.ne    .Lid_emit
    mov     w0, #TOK_IF
    b       .Lid_emit
.Lkw3:
    // "I64"
    ldrb    w9, [x24]
    cmp     w9, #'I'
    b.ne    .Lid_emit
    ldrb    w9, [x24, #1]
    cmp     w9, #'6'
    b.ne    .Lid_emit
    ldrb    w9, [x24, #2]
    cmp     w9, #'4'
    b.ne    .Lid_emit
    mov     w0, #TOK_I64
    b       .Lid_emit
.Lkw4:
    // "else"
    ldrb    w9, [x24]
    cmp     w9, #'e'
    b.ne    .Lid_emit
    ldrb    w9, [x24, #1]
    cmp     w9, #'l'
    b.ne    .Lid_emit
    ldrb    w9, [x24, #2]
    cmp     w9, #'s'
    b.ne    .Lid_emit
    ldrb    w9, [x24, #3]
    cmp     w9, #'e'
    b.ne    .Lid_emit
    mov     w0, #TOK_ELSE
    b       .Lid_emit
.Lkw5:
    // "while"
    ldrb    w9, [x24]
    cmp     w9, #'w'
    b.ne    .Lid_emit
    ldrb    w9, [x24, #1]
    cmp     w9, #'h'
    b.ne    .Lid_emit
    ldrb    w9, [x24, #2]
    cmp     w9, #'i'
    b.ne    .Lid_emit
    ldrb    w9, [x24, #3]
    cmp     w9, #'l'
    b.ne    .Lid_emit
    ldrb    w9, [x24, #4]
    cmp     w9, #'e'
    b.ne    .Lid_emit
    mov     w0, #TOK_WHILE
    b       .Lid_emit
.Lkw6:
    // "return"
    ldrb    w9, [x24]
    cmp     w9, #'r'
    b.ne    .Lid_emit
    ldrb    w9, [x24, #1]
    cmp     w9, #'e'
    b.ne    .Lid_emit
    ldrb    w9, [x24, #2]
    cmp     w9, #'t'
    b.ne    .Lid_emit
    ldrb    w9, [x24, #3]
    cmp     w9, #'u'
    b.ne    .Lid_emit
    ldrb    w9, [x24, #4]
    cmp     w9, #'r'
    b.ne    .Lid_emit
    ldrb    w9, [x24, #5]
    cmp     w9, #'n'
    b.ne    .Lid_emit
    mov     w0, #TOK_RETURN
    b       .Lid_emit
.Lid_emit:
    str     w0, [x21, #0]
    sub     x9, x24, x19
    str     w9, [x21, #4]
    str     w13, [x21, #8]
    str     wzr, [x21, #12]
    add     x21, x21, #TOKSZ
    add     x23, x23, #1
    b       .Lloop

.Lnot_ident:
    // ---- string literal ----
    cmp     w9, #'"'
    b.ne    .Lpunct
    add     x20, x20, #1    // skip opening quote
    mov     x24, x20        // content start
.Lstrloop:
    ldrb    w9, [x20]
    cbz     w9, .Lerr       // unterminated
    cmp     w9, #'"'
    b.eq    .Lstrend
    cmp     w9, #'\\'
    b.ne    .Lstrnorm
    ldrb    w10, [x20, #1]  // escaped char
    cbz     w10, .Lerr
    add     x20, x20, #2
    b       .Lstrloop
.Lstrnorm:
    add     x20, x20, #1
    b       .Lstrloop
.Lstrend:
    mov     w0, #TOK_STRING
    str     w0, [x21, #0]
    sub     x9, x24, x19
    str     w9, [x21, #4]
    sub     x9, x20, x24
    str     w9, [x21, #8]
    str     wzr, [x21, #12]
    add     x21, x21, #TOKSZ
    add     x23, x23, #1
    add     x20, x20, #1    // skip closing quote
    b       .Lloop

.Lpunct:
    ldrb    w9, [x20]
    cmp     w9, #'+'
    mov     w0, #TOK_PLUS
    b.eq    .Lp1
    cmp     w9, #'-'
    mov     w0, #TOK_MINUS
    b.eq    .Lp1
    cmp     w9, #'*'
    mov     w0, #TOK_STAR
    b.eq    .Lp1
    cmp     w9, #'/'
    mov     w0, #TOK_SLASH
    b.eq    .Lp1
    cmp     w9, #';'
    mov     w0, #TOK_SEMI
    b.eq    .Lp1
    cmp     w9, #'('
    mov     w0, #TOK_LPAREN
    b.eq    .Lp1
    cmp     w9, #')'
    mov     w0, #TOK_RPAREN
    b.eq    .Lp1
    cmp     w9, #'{'
    mov     w0, #TOK_LBRACE
    b.eq    .Lp1
    cmp     w9, #'}'
    mov     w0, #TOK_RBRACE
    b.eq    .Lp1
    cmp     w9, #','
    mov     w0, #TOK_COMMA
    b.eq    .Lp1
    // two-char-capable operators
    cmp     w9, #'<'
    b.eq    .Lp_lt
    cmp     w9, #'>'
    b.eq    .Lp_gt
    cmp     w9, #'='
    b.eq    .Lp_eq
    cmp     w9, #'!'
    b.eq    .Lp_ne
    b       .Lerr           // unknown character

.Lp_lt:
    ldrb    w10, [x20, #1]
    cmp     w10, #'='
    mov     w0, #TOK_LE
    b.eq    .Lp2
    mov     w0, #TOK_LT
    b       .Lp1
.Lp_gt:
    ldrb    w10, [x20, #1]
    cmp     w10, #'='
    mov     w0, #TOK_GE
    b.eq    .Lp2
    mov     w0, #TOK_GT
    b       .Lp1
.Lp_eq:
    ldrb    w10, [x20, #1]
    cmp     w10, #'='
    mov     w0, #TOK_EQEQ
    b.eq    .Lp2
    mov     w0, #TOK_ASSIGN
    b       .Lp1
.Lp_ne:
    ldrb    w10, [x20, #1]
    cmp     w10, #'='
    mov     w0, #TOK_NE
    b.eq    .Lp2
    b       .Lerr           // bare '!' unsupported

.Lp1:
    str     w0, [x21, #0]
    sub     x9, x20, x19
    str     w9, [x21, #4]
    mov     w9, #1
    str     w9, [x21, #8]
    str     wzr, [x21, #12]
    add     x21, x21, #TOKSZ
    add     x23, x23, #1
    add     x20, x20, #1
    b       .Lloop
.Lp2:
    str     w0, [x21, #0]
    sub     x9, x20, x19
    str     w9, [x21, #4]
    mov     w9, #2
    str     w9, [x21, #8]
    str     wzr, [x21, #12]
    add     x21, x21, #TOKSZ
    add     x23, x23, #1
    add     x20, x20, #2
    b       .Lloop

.Lemit_eof:
    mov     w0, #TOK_EOF
    str     w0, [x21, #0]
    sub     x9, x20, x19
    str     w9, [x21, #4]
    str     wzr, [x21, #8]
    str     wzr, [x21, #12]
    add     x23, x23, #1
    mov     x0, x23         // return count
    b       .Lret

.Lerr:
    mov     x0, #-1

.Lret:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// w0 = 1 if w9 is [A-Za-z_], else 0
.Lis_idstart:
    orr     w11, w9, #0x20      // lowercase
    cmp     w11, #'a'
    b.lo    1f
    cmp     w11, #'z'
    b.hi    1f
    mov     w0, #1
    ret
1:
    cmp     w9, #'_'
    cset    w0, eq
    ret

// w0 = 1 if w9 is [A-Za-z0-9_], else 0
.Lis_idcont:
    sub     w11, w9, #'0'
    cmp     w11, #9
    b.hi    2f
    mov     w0, #1
    ret
2:
    b       .Lis_idstart
