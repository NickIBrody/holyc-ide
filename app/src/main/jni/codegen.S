// codegen.S — emits ARM64 machine code from the AST, directly into the
// final executable buffer so that absolute addresses are correct.
//
//   int hc_codegen(AstNode *arena, int root, uint8_t *buf, int cap,
//                  const char *src, void *print_str, void *print_int);
//
// Returns the byte offset of the program entry point inside buf, or -1.
//
// Generated code uses AAPCS64: args in x0..x7, result in x0.  Each function
// gets a stack frame; locals (params + vardecls) live in frame slots at
// [x29, #16 + i*8].  Expressions evaluate into x0, using x1 and the stack.
// String literals are materialised in a data region at the top of buf.

// ---- token / node types ----
.set TOK_PLUS,4
.set TOK_MINUS,5
.set TOK_STAR,6
.set TOK_SLASH,7
.set TOK_LT,15
.set TOK_GT,16
.set TOK_LE,17
.set TOK_GE,18
.set TOK_EQEQ,19
.set TOK_NE,20

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

.set NODESZ,64
.set N_TYPE,0
.set N_OP,4
.set N_IVAL,8
.set N_A,16
.set N_B,20
.set N_C,24
.set N_NEXT,28
.set N_NAME,32

// ---- codegen context offsets ----
.set CG_ARENA,0
.set CG_BUF,8
.set CG_SRC,16
.set CG_PSTR,24
.set CG_PINT,32
.set CG_POS,40
.set CG_CAP,44
.set CG_ERR,48
.set CG_DATAPOS,52
.set CG_DATASTART,56
.set CG_FRAME,60
.set CG_NPARAM,64
.set CG_SYMCOUNT,68
.set CG_FNCOUNT,72
.set CG_FIXCOUNT,76
.set CG_SYMNAMES,80
.set CG_SYMOFFS,88
.set CG_FNNAMES,96
.set CG_FNOFFS,104
.set CG_FIXSITE,112
.set CG_FIXNAMES,120

// load a 32-bit assembler-time constant into a w register
.macro LDW reg, val
    movz    \reg, #((\val) & 0xffff)
    movk    \reg, #(((\val) >> 16) & 0xffff), lsl #16
.endm

.text

// ============================================================
//  Leaf helpers (x19 = ctx)
// ============================================================
getnode:                            // w0 = idx -> x0 = node addr
    ldr     x9, [x19, #CG_ARENA]
    sxtw    x10, w0
    mov     x11, #NODESZ
    madd    x0, x10, x11, x9
    ret

emit32:                             // w0 = instruction word
    ldr     w9, [x19, #CG_POS]
    ldr     w10, [x19, #CG_DATASTART]
    add     w11, w9, #4
    cmp     w11, w10
    b.gt    1f
    ldr     x12, [x19, #CG_BUF]
    str     w0, [x12, w9, uxtw]
    str     w11, [x19, #CG_POS]
    ret
1:  mov     w13, #1
    str     w13, [x19, #CG_ERR]
    ret

patch_at:                           // w0 = site offset, w1 = word
    ldr     x9, [x19, #CG_BUF]
    str     w1, [x9, w0, uxtw]
    ret

emit_data:                          // x0 = src ptr, w1 = len -> w0 = data off
    ldr     w9, [x19, #CG_DATAPOS]
    mov     w14, w9
    ldr     w10, [x19, #CG_CAP]
    add     w11, w9, w1
    cmp     w11, w10
    b.gt    1f
    ldr     x12, [x19, #CG_BUF]
    add     x12, x12, w9, uxtw
    mov     w13, #0
2:  cmp     w13, w1
    b.ge    3f
    ldrb    w15, [x0, w13, uxtw]
    strb    w15, [x12, w13, uxtw]
    add     w13, w13, #1
    b       2b
3:  str     w11, [x19, #CG_DATAPOS]
    mov     w0, w14
    ret
1:  mov     w13, #1
    str     w13, [x19, #CG_ERR]
    mov     w0, w14
    ret

emit_str_x_fp:                      // w0 = Rt, w1 = byte offset (mult of 8)
    lsr     w9, w1, #3
    lsl     w9, w9, #10
    LDW     w10, 0xF9000000
    orr     w10, w10, w9
    mov     w11, #0x3A0             // 29 << 5
    orr     w10, w10, w11
    and     w0, w0, #0x1f
    orr     w0, w10, w0
    b       emit32

emit_ldr_x_fp:                      // w0 = Rt, w1 = byte offset
    lsr     w9, w1, #3
    lsl     w9, w9, #10
    LDW     w10, 0xF9400000
    orr     w10, w10, w9
    mov     w11, #0x3A0
    orr     w10, w10, w11
    and     w0, w0, #0x1f
    orr     w0, w10, w0
    b       emit32

name_eq:                            // x0,x1 -> w0 = 1 if 32 bytes equal
    ldp     x9, x10, [x0, #0]
    ldp     x11, x12, [x1, #0]
    cmp     x9, x11
    b.ne    1f
    cmp     x10, x12
    b.ne    1f
    ldp     x9, x10, [x0, #16]
    ldp     x11, x12, [x1, #16]
    cmp     x9, x11
    b.ne    1f
    cmp     x10, x12
    b.ne    1f
    mov     w0, #1
    ret
1:  mov     w0, #0
    ret

fn_add:                             // x0 = name addr, w1 = offset
    ldr     w9, [x19, #CG_FNCOUNT]
    ldr     x10, [x19, #CG_FNNAMES]
    mov     x11, #32
    madd    x10, x9, x11, x10
    ldp     x12, x13, [x0, #0]
    stp     x12, x13, [x10, #0]
    ldp     x12, x13, [x0, #16]
    stp     x12, x13, [x10, #16]
    ldr     x11, [x19, #CG_FNOFFS]
    str     w1, [x11, w9, uxtw #2]
    add     w9, w9, #1
    str     w9, [x19, #CG_FNCOUNT]
    ret

fix_add:                            // w0 = site, x1 = name addr
    ldr     w9, [x19, #CG_FIXCOUNT]
    ldr     x10, [x19, #CG_FIXSITE]
    str     w0, [x10, w9, uxtw #2]
    ldr     x10, [x19, #CG_FIXNAMES]
    mov     x11, #32
    madd    x10, x9, x11, x10
    ldp     x12, x13, [x1, #0]
    stp     x12, x13, [x10, #0]
    ldp     x12, x13, [x1, #16]
    stp     x12, x13, [x10, #16]
    add     w9, w9, #1
    str     w9, [x19, #CG_FIXCOUNT]
    ret

// ============================================================
//  emit_mov_imm64 : w0 = reg (0-31), x1 = value
// ============================================================
emit_mov_imm64:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x20, x21, [sp, #16]
    and     w20, w0, #0x1f
    mov     x21, x1
    // movz reg, val[0:16]
    and     x9, x21, #0xffff
    LDW     w0, 0xD2800000
    orr     w0, w0, w20
    orr     w0, w0, w9, lsl #5
    bl      emit32
    // movk reg, val[16:32], lsl 16
    lsr     x9, x21, #16
    and     x9, x9, #0xffff
    cbz     x9, 1f
    LDW     w0, 0xF2800000
    LDW     w10, 0x00200000
    orr     w0, w0, w10
    orr     w0, w0, w20
    orr     w0, w0, w9, lsl #5
    bl      emit32
1:  lsr     x9, x21, #32
    and     x9, x9, #0xffff
    cbz     x9, 2f
    LDW     w0, 0xF2800000
    LDW     w10, 0x00400000
    orr     w0, w0, w10
    orr     w0, w0, w20
    orr     w0, w0, w9, lsl #5
    bl      emit32
2:  lsr     x9, x21, #48
    and     x9, x9, #0xffff
    cbz     x9, 3f
    LDW     w0, 0xF2800000
    LDW     w10, 0x00600000
    orr     w0, w0, w10
    orr     w0, w0, w20
    orr     w0, w0, w9, lsl #5
    bl      emit32
3:  ldp     x20, x21, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

emit_call:                          // x1 = absolute helper address
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     w0, #16
    bl      emit_mov_imm64          // mov x16, addr
    LDW     w0, 0xD63F0200          // blr x16
    bl      emit32
    ldp     x29, x30, [sp], #16
    ret

// ============================================================
//  sym_find : x0 = name addr -> w0 = frame offset or -1
// ============================================================
sym_find:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x20, x21, [sp, #16]
    str     x22, [sp, #32]
    mov     x20, x0
    ldr     w21, [x19, #CG_SYMCOUNT]
    mov     w22, #0
1:  cmp     w22, w21
    b.ge    2f
    ldr     x0, [x19, #CG_SYMNAMES]
    mov     x10, #32
    madd    x0, x22, x10, x0
    mov     x1, x20
    bl      name_eq
    cbnz    w0, 3f
    add     w22, w22, #1
    b       1b
2:  mov     w0, #-1
    b       4f
3:  ldr     x10, [x19, #CG_SYMOFFS]
    ldr     w0, [x10, w22, uxtw #2]
4:  ldr     x22, [sp, #32]
    ldp     x20, x21, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// ============================================================
//  sym_add : x0 = name addr  (dedups via sym_find)
// ============================================================
sym_add:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x20, [sp, #16]
    mov     x20, x0
    bl      sym_find
    cmn     w0, #1
    b.ne    1f                      // already present
    ldr     w9, [x19, #CG_SYMCOUNT]
    ldr     x10, [x19, #CG_SYMNAMES]
    mov     x11, #32
    madd    x10, x9, x11, x10
    ldp     x12, x13, [x20, #0]
    stp     x12, x13, [x10, #0]
    ldp     x12, x13, [x20, #16]
    stp     x12, x13, [x10, #16]
    ldr     x11, [x19, #CG_SYMOFFS]
    lsl     w12, w9, #3
    add     w12, w12, #16
    str     w12, [x11, w9, uxtw #2]
    add     w9, w9, #1
    str     w9, [x19, #CG_SYMCOUNT]
1:  ldr     x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// ============================================================
//  fn_find : x0 = name addr -> w0 = offset or -1
// ============================================================
fn_find:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x20, x21, [sp, #16]
    str     x22, [sp, #32]
    mov     x20, x0
    ldr     w21, [x19, #CG_FNCOUNT]
    mov     w22, #0
1:  cmp     w22, w21
    b.ge    2f
    ldr     x0, [x19, #CG_FNNAMES]
    mov     x10, #32
    madd    x0, x22, x10, x0
    mov     x1, x20
    bl      name_eq
    cbnz    w0, 3f
    add     w22, w22, #1
    b       1b
2:  mov     w0, #-1
    b       4f
3:  ldr     x10, [x19, #CG_FNOFFS]
    ldr     w0, [x10, w22, uxtw #2]
4:  ldr     x22, [sp, #32]
    ldp     x20, x21, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// ============================================================
//  collect_locals : w0 = node idx (adds PARAM/VARDECL names)
// ============================================================
collect_locals:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x20, x21, [sp, #16]
    mov     w20, w0
.Lcl_loop:
    cbz     w20, .Lcl_ret
    mov     w0, w20
    bl      getnode
    mov     x21, x0
    ldr     w9, [x21, #N_TYPE]
    cmp     w9, #NODE_FUNCDEF
    b.eq    .Lcl_next               // do not descend into nested funcs
    cmp     w9, #NODE_VARDECL
    b.eq    .Lcl_add
    cmp     w9, #NODE_PARAM
    b.eq    .Lcl_add
    b       .Lcl_recurse
.Lcl_add:
    add     x0, x21, #N_NAME
    bl      sym_add
.Lcl_recurse:
    ldr     w0, [x21, #N_A]
    bl      collect_locals
    ldr     w0, [x21, #N_B]
    bl      collect_locals
    ldr     w0, [x21, #N_C]
    bl      collect_locals
.Lcl_next:
    ldr     w20, [x21, #N_NEXT]
    b       .Lcl_loop
.Lcl_ret:
    ldp     x20, x21, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// ============================================================
//  gen_expr : w0 = node idx ; result code leaves value in x0
// ============================================================
gen_expr:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x20, x21, [sp, #16]
    stp     x22, x23, [sp, #32]
    stp     x24, x25, [sp, #48]
    mov     w20, w0
    cbz     w20, .Lge_done
    mov     w0, w20
    bl      getnode
    mov     x21, x0
    ldr     w9, [x21, #N_TYPE]
    cmp     w9, #NODE_INTLIT
    b.eq    .Lge_int
    cmp     w9, #NODE_IDENT
    b.eq    .Lge_ident
    cmp     w9, #NODE_BINOP
    b.eq    .Lge_binop
    cmp     w9, #NODE_CALL
    b.eq    .Lge_call
    mov     w9, #1
    str     w9, [x19, #CG_ERR]
    b       .Lge_done

.Lge_int:
    ldr     x1, [x21, #N_IVAL]
    mov     w0, #0
    bl      emit_mov_imm64
    b       .Lge_done

.Lge_ident:
    add     x0, x21, #N_NAME
    bl      sym_find
    cmn     w0, #1
    b.eq    .Lge_undef
    mov     w1, w0
    mov     w0, #0
    bl      emit_ldr_x_fp
    b       .Lge_done
.Lge_undef:
    mov     w9, #1
    str     w9, [x19, #CG_ERR]
    b       .Lge_done

.Lge_binop:
    ldr     w0, [x21, #N_A]
    bl      gen_expr
    LDW     w0, 0xF81F0FE0          // str x0, [sp, #-16]!
    bl      emit32
    ldr     w0, [x21, #N_B]
    bl      gen_expr
    LDW     w0, 0xAA0003E1          // mov x1, x0   (right)
    bl      emit32
    LDW     w0, 0xF84107E0          // ldr x0, [sp], #16   (left)
    bl      emit32
    ldr     w22, [x21, #N_OP]
    cmp     w22, #TOK_PLUS
    b.eq    .Lop_add
    cmp     w22, #TOK_MINUS
    b.eq    .Lop_sub
    cmp     w22, #TOK_STAR
    b.eq    .Lop_mul
    cmp     w22, #TOK_SLASH
    b.eq    .Lop_div
    LDW     w0, 0xEB01001F          // cmp x0, x1
    bl      emit32
    cmp     w22, #TOK_LT
    b.eq    .Lcs_lt
    cmp     w22, #TOK_LE
    b.eq    .Lcs_le
    cmp     w22, #TOK_GT
    b.eq    .Lcs_gt
    cmp     w22, #TOK_GE
    b.eq    .Lcs_ge
    cmp     w22, #TOK_EQEQ
    b.eq    .Lcs_eq
    cmp     w22, #TOK_NE
    b.eq    .Lcs_ne
    b       .Lge_done
.Lop_add:
    LDW     w0, 0x8B010000
    bl      emit32
    b       .Lge_done
.Lop_sub:
    LDW     w0, 0xCB010000
    bl      emit32
    b       .Lge_done
.Lop_mul:
    LDW     w0, 0x9B017C00
    bl      emit32
    b       .Lge_done
.Lop_div:
    LDW     w0, 0x9AC10C00
    bl      emit32
    b       .Lge_done
.Lcs_lt:
    LDW     w0, 0x9A9FA7E0
    bl      emit32
    b       .Lge_done
.Lcs_le:
    LDW     w0, 0x9A9FC7E0
    bl      emit32
    b       .Lge_done
.Lcs_gt:
    LDW     w0, 0x9A9FD7E0
    bl      emit32
    b       .Lge_done
.Lcs_ge:
    LDW     w0, 0x9A9FB7E0
    bl      emit32
    b       .Lge_done
.Lcs_eq:
    LDW     w0, 0x9A9F17E0
    bl      emit32
    b       .Lge_done
.Lcs_ne:
    LDW     w0, 0x9A9F07E0
    bl      emit32
    b       .Lge_done

.Lge_call:
    ldr     w23, [x21, #N_A]        // first arg
    mov     w24, #0                 // count
    mov     w9, w23
1:  cbz     w9, 2f
    add     w24, w24, #1
    mov     w0, w9
    bl      getnode
    ldr     w9, [x0, #N_NEXT]
    b       1b
2:  mov     w25, w23                // iterate args, push each
3:  cbz     w25, 4f
    mov     w0, w25
    bl      gen_expr
    LDW     w0, 0xF81F0FE0          // push x0
    bl      emit32
    mov     w0, w25
    bl      getnode
    ldr     w25, [x0, #N_NEXT]
    b       3b
4:  sub     w23, w24, #1            // pop into x{count-1..0}
5:  cmp     w23, #0
    b.lt    6f
    LDW     w0, 0xF84107E0          // ldr x{i}, [sp], #16
    orr     w0, w0, w23
    bl      emit32
    sub     w23, w23, #1
    b       5b
6:  ldr     w0, [x19, #CG_POS]      // bl site
    add     x1, x21, #N_NAME
    bl      fix_add
    LDW     w0, 0x94000000          // bl 0 (placeholder)
    bl      emit32

.Lge_done:
    ldp     x24, x25, [sp, #48]
    ldp     x22, x23, [sp, #32]
    ldp     x20, x21, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// ============================================================
//  gen_print : w0 = PRINT node idx
// ============================================================
gen_print:
    stp     x29, x30, [sp, #-352]!
    mov     x29, sp
    stp     x20, x21, [sp, #16]
    stp     x22, x23, [sp, #32]
    stp     x24, x25, [sp, #48]
    stp     x26, x27, [sp, #64]
    mov     w20, w0
    bl      getnode
    mov     x21, x0
    ldr     w22, [x21, #N_IVAL]     // string start offset
    ldr     w23, [x21, #N_C]        // string length
    ldr     x24, [x19, #CG_SRC]
    add     x24, x24, w22, uxtw     // fmt pointer
    ldr     w27, [x21, #N_A]        // first arg idx
    mov     w25, #0                 // i
    mov     w26, #0                 // runlen
.Lgp_loop:
    cmp     w25, w23
    b.ge    .Lgp_end
    ldrb    w9, [x24, w25, uxtw]
    cmp     w9, #'%'
    b.ne    .Lgp_esc
    add     w10, w25, #1
    cmp     w10, w23
    b.ge    .Lgp_lit
    ldrb    w11, [x24, w10, uxtw]
    cmp     w11, #'d'
    b.ne    .Lgp_lit
    // %d : flush run, print integer argument
    bl      gp_flush
    cbz     w27, .Lgp_d_done
    mov     w0, w27
    bl      gen_expr
    ldr     x1, [x19, #CG_PINT]
    bl      emit_call
    mov     w0, w27
    bl      getnode
    ldr     w27, [x0, #N_NEXT]
.Lgp_d_done:
    add     w25, w25, #2
    b       .Lgp_loop
.Lgp_esc:
    cmp     w9, #'\\'
    b.ne    .Lgp_lit
    add     w10, w25, #1
    cmp     w10, w23
    b.ge    .Lgp_lit
    ldrb    w11, [x24, w10, uxtw]
    cmp     w11, #'n'
    b.ne    1f
    mov     w11, #10
    b       .Lgp_app
1:  cmp     w11, #'t'
    b.ne    2f
    mov     w11, #9
    b       .Lgp_app
2:  cmp     w11, #'r'
    b.ne    3f
    mov     w11, #13
    b       .Lgp_app
3:  cmp     w11, #'0'
    b.ne    .Lgp_app                // default keeps the char as-is
    mov     w11, #0
.Lgp_app:
    cmp     w26, #255
    b.ge    4f
    add     x12, sp, #96
    strb    w11, [x12, w26, uxtw]
    add     w26, w26, #1
4:  add     w25, w25, #2
    b       .Lgp_loop
.Lgp_lit:
    cmp     w26, #255
    b.ge    5f
    add     x12, sp, #96
    strb    w9, [x12, w26, uxtw]
    add     w26, w26, #1
5:  add     w25, w25, #1
    b       .Lgp_loop
.Lgp_end:
    bl      gp_flush
    ldp     x26, x27, [sp, #64]
    ldp     x24, x25, [sp, #48]
    ldp     x22, x23, [sp, #32]
    ldp     x20, x21, [sp, #16]
    ldp     x29, x30, [sp], #352
    ret

// gp_flush: emit print_str(runbuf,runlen) when runlen>0; runbuf at
// [x29,#96], runlen in w26.  Resets w26.  Preserves w26 semantics.
gp_flush:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    cbz     w26, 1f
    // caller's runbuf lives at caller_x29 + 96; reach it via the fp chain
    ldr     x9, [x29, #0]           // caller x29
    add     x0, x9, #96
    mov     w1, w26
    bl      emit_data               // w0 = data offset
    ldr     x9, [x19, #CG_BUF]
    add     x9, x9, w0, uxtw
    mov     x1, x9
    mov     w0, #0
    bl      emit_mov_imm64          // x0 = ptr
    uxtw    x1, w26
    mov     w0, #1
    bl      emit_mov_imm64          // x1 = len
    ldr     x1, [x19, #CG_PSTR]
    bl      emit_call
    mov     w26, #0
1:  ldp     x29, x30, [sp], #16
    ret

// ============================================================
//  gen_stmt : w0 = node idx
// ============================================================
gen_stmt:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x20, x21, [sp, #16]
    stp     x22, x23, [sp, #32]
    stp     x24, x25, [sp, #48]
    mov     w20, w0
    cbz     w20, .Lgs_done
    mov     w0, w20
    bl      getnode
    mov     x21, x0
    ldr     w22, [x21, #N_TYPE]
    cmp     w22, #NODE_BLOCK
    b.eq    .Lgs_block
    cmp     w22, #NODE_VARDECL
    b.eq    .Lgs_vardecl
    cmp     w22, #NODE_ASSIGN
    b.eq    .Lgs_assign
    cmp     w22, #NODE_EXPRSTMT
    b.eq    .Lgs_exprstmt
    cmp     w22, #NODE_PRINT
    b.eq    .Lgs_print
    cmp     w22, #NODE_RETURN
    b.eq    .Lgs_return
    cmp     w22, #NODE_IF
    b.eq    .Lgs_if
    cmp     w22, #NODE_WHILE
    b.eq    .Lgs_while
    b       .Lgs_done               // ignore anything else (e.g. FUNCDEF)

.Lgs_block:
    ldr     w23, [x21, #N_A]
1:  cbz     w23, .Lgs_done
    mov     w0, w23
    bl      gen_stmt
    mov     w0, w23
    bl      getnode
    ldr     w23, [x0, #N_NEXT]
    b       1b

.Lgs_vardecl:
    ldr     w23, [x21, #N_A]
    cbz     w23, .Lgs_done          // declaration without initialiser
    mov     w0, w23
    bl      gen_expr
    add     x0, x21, #N_NAME
    bl      sym_find
    mov     w1, w0
    mov     w0, #0
    bl      emit_str_x_fp
    b       .Lgs_done

.Lgs_assign:
    ldr     w23, [x21, #N_A]
    mov     w0, w23
    bl      gen_expr
    add     x0, x21, #N_NAME
    bl      sym_find
    mov     w1, w0
    mov     w0, #0
    bl      emit_str_x_fp
    b       .Lgs_done

.Lgs_exprstmt:
    ldr     w0, [x21, #N_A]
    bl      gen_expr
    b       .Lgs_done

.Lgs_print:
    mov     w0, w20
    bl      gen_print
    b       .Lgs_done

.Lgs_return:
    ldr     w0, [x21, #N_A]
    bl      gen_expr
    LDW     w0, 0xA9407BFD          // ldp x29,x30,[sp]
    bl      emit32
    ldr     w9, [x19, #CG_FRAME]
    lsl     w9, w9, #10
    LDW     w0, 0x910003FF          // add sp,sp,#FRAME
    orr     w0, w0, w9
    bl      emit32
    LDW     w0, 0xD65F03C0          // ret
    bl      emit32
    b       .Lgs_done

.Lgs_if:
    ldr     w0, [x21, #N_A]         // cond
    bl      gen_expr
    LDW     w0, 0xF100001F          // cmp x0,#0
    bl      emit32
    ldr     w23, [x19, #CG_POS]     // site1 (b.eq)
    LDW     w0, 0x54000000
    bl      emit32
    ldr     w0, [x21, #N_B]         // then
    bl      gen_stmt
    ldr     w24, [x21, #N_C]        // else idx
    cbz     w24, .Lgs_if_noelse
    ldr     w25, [x19, #CG_POS]     // site2 (b)
    LDW     w0, 0x14000000
    bl      emit32
    // patch site1 -> here (else start)
    ldr     w9, [x19, #CG_POS]
    sub     w9, w9, w23
    asr     w9, w9, #2
    and     w9, w9, #0x7FFFF
    lsl     w9, w9, #5
    LDW     w10, 0x54000000
    orr     w1, w9, w10
    mov     w0, w23
    bl      patch_at
    ldr     w0, [x21, #N_C]
    bl      gen_stmt
    // patch site2 -> here (end)
    ldr     w9, [x19, #CG_POS]
    sub     w9, w9, w25
    asr     w9, w9, #2
    LDW     w10, 0x03FFFFFF
    and     w9, w9, w10
    LDW     w10, 0x14000000
    orr     w1, w9, w10
    mov     w0, w25
    bl      patch_at
    b       .Lgs_done
.Lgs_if_noelse:
    ldr     w9, [x19, #CG_POS]
    sub     w9, w9, w23
    asr     w9, w9, #2
    and     w9, w9, #0x7FFFF
    lsl     w9, w9, #5
    LDW     w10, 0x54000000
    orr     w1, w9, w10
    mov     w0, w23
    bl      patch_at
    b       .Lgs_done

.Lgs_while:
    ldr     w23, [x19, #CG_POS]     // top
    ldr     w0, [x21, #N_A]
    bl      gen_expr
    LDW     w0, 0xF100001F          // cmp x0,#0
    bl      emit32
    ldr     w24, [x19, #CG_POS]     // siteEnd (b.eq)
    LDW     w0, 0x54000000
    bl      emit32
    ldr     w0, [x21, #N_B]         // body
    bl      gen_stmt
    // b back to top
    ldr     w9, [x19, #CG_POS]
    sub     w9, w23, w9             // top - cur
    asr     w9, w9, #2
    LDW     w10, 0x03FFFFFF
    and     w9, w9, w10
    LDW     w10, 0x14000000
    orr     w0, w9, w10
    bl      emit32
    // patch siteEnd -> here
    ldr     w9, [x19, #CG_POS]
    sub     w9, w9, w24
    asr     w9, w9, #2
    and     w9, w9, #0x7FFFF
    lsl     w9, w9, #5
    LDW     w10, 0x54000000
    orr     w1, w9, w10
    mov     w0, w24
    bl      patch_at
    b       .Lgs_done

.Lgs_done:
    ldp     x24, x25, [sp, #48]
    ldp     x22, x23, [sp, #32]
    ldp     x20, x21, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// ============================================================
//  gen_func_common : w0 = params head idx, w1 = body list head idx
// ============================================================
gen_func_common:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x20, x21, [sp, #16]
    stp     x22, x23, [sp, #32]
    mov     w20, w0                 // params head
    mov     w21, w1                 // body head
    str     wzr, [x19, #CG_SYMCOUNT]
    // add params in order
    mov     w22, #0
    mov     w23, w20
1:  cbz     w23, 2f
    mov     w0, w23
    bl      getnode
    add     x0, x0, #N_NAME
    bl      sym_add
    add     w22, w22, #1
    mov     w0, w23
    bl      getnode
    ldr     w23, [x0, #N_NEXT]
    b       1b
2:  str     w22, [x19, #CG_NPARAM]
    mov     w0, w21
    bl      collect_locals
    // FRAME = align16(16 + symcount*8)
    ldr     w9, [x19, #CG_SYMCOUNT]
    lsl     w9, w9, #3
    add     w9, w9, #16
    add     w9, w9, #15
    bic     w9, w9, #15
    str     w9, [x19, #CG_FRAME]
    // prologue
    lsl     w10, w9, #10
    LDW     w0, 0xD10003FF          // sub sp,sp,#FRAME
    orr     w0, w0, w10
    bl      emit32
    LDW     w0, 0xA9007BFD          // stp x29,x30,[sp]
    bl      emit32
    LDW     w0, 0x910003FD          // mov x29,sp
    bl      emit32
    // store params into slots
    mov     w23, #0
3:  ldr     w9, [x19, #CG_NPARAM]
    cmp     w23, w9
    b.ge    4f
    mov     w0, w23
    lsl     w1, w23, #3
    add     w1, w1, #16
    bl      emit_str_x_fp
    add     w23, w23, #1
    b       3b
4:  // body (skip FUNCDEF nodes)
    mov     w23, w21
5:  cbz     w23, 6f
    mov     w0, w23
    bl      getnode
    ldr     w9, [x0, #N_TYPE]
    cmp     w9, #NODE_FUNCDEF
    b.eq    7f
    mov     w0, w23
    bl      gen_stmt
7:  mov     w0, w23
    bl      getnode
    ldr     w23, [x0, #N_NEXT]
    b       5b
6:  // final epilogue
    LDW     w0, 0xD2800000          // mov x0,#0
    bl      emit32
    LDW     w0, 0xA9407BFD          // ldp x29,x30,[sp]
    bl      emit32
    ldr     w9, [x19, #CG_FRAME]
    lsl     w9, w9, #10
    LDW     w0, 0x910003FF          // add sp,sp,#FRAME
    orr     w0, w0, w9
    bl      emit32
    LDW     w0, 0xD65F03C0          // ret
    bl      emit32
    ldp     x22, x23, [sp, #32]
    ldp     x20, x21, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// ============================================================
//  resolve_fixups : patch all forward/backward BL call sites
// ============================================================
resolve_fixups:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x20, x21, [sp, #16]
    stp     x22, x23, [sp, #32]
    ldr     w20, [x19, #CG_FIXCOUNT]
    mov     w21, #0
1:  cmp     w21, w20
    b.ge    .Lrf_done
    ldr     x9, [x19, #CG_FIXSITE]
    ldr     w22, [x9, w21, uxtw #2] // site
    ldr     x9, [x19, #CG_FIXNAMES]
    mov     x10, #32
    madd    x0, x21, x10, x9
    bl      fn_find
    cmn     w0, #1
    b.eq    .Lrf_err
    mov     w23, w0                 // target offset
    sub     w9, w23, w22
    asr     w9, w9, #2
    LDW     w10, 0x03FFFFFF
    and     w9, w9, w10
    LDW     w10, 0x94000000
    orr     w1, w9, w10
    mov     w0, w22
    bl      patch_at
    add     w21, w21, #1
    b       1b
.Lrf_err:
    mov     w9, #1
    str     w9, [x19, #CG_ERR]
.Lrf_done:
    ldp     x22, x23, [sp, #32]
    ldp     x20, x21, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// ============================================================
//  hc_codegen entry
// ============================================================
.global hc_codegen
.type hc_codegen, %function
hc_codegen:
    stp     x29, x30, [sp, #-96]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    str     x27, [sp, #80]
    sub     sp, sp, #16384
    mov     x25, x0                 // arena (temp)
    mov     w26, w1                 // root
    mov     x19, sp                 // ctx base
    // fill ctx
    str     x0, [x19, #CG_ARENA]
    str     x2, [x19, #CG_BUF]
    str     x4, [x19, #CG_SRC]
    str     x5, [x19, #CG_PSTR]
    str     x6, [x19, #CG_PINT]
    str     wzr, [x19, #CG_POS]
    str     w3, [x19, #CG_CAP]
    str     wzr, [x19, #CG_ERR]
    str     wzr, [x19, #CG_SYMCOUNT]
    str     wzr, [x19, #CG_FNCOUNT]
    str     wzr, [x19, #CG_FIXCOUNT]
    // data region = top quarter of buf
    lsr     w9, w3, #2
    sub     w10, w3, w9
    str     w10, [x19, #CG_DATASTART]
    str     w10, [x19, #CG_DATAPOS]
    // array pointers
    add     x9, x19, #256
    str     x9, [x19, #CG_SYMNAMES]
    add     x9, x9, #2048
    str     x9, [x19, #CG_SYMOFFS]
    add     x9, x9, #256
    str     x9, [x19, #CG_FNNAMES]
    add     x9, x9, #2048
    str     x9, [x19, #CG_FNOFFS]
    add     x9, x9, #256
    str     x9, [x19, #CG_FIXSITE]
    add     x9, x9, #1024
    str     x9, [x19, #CG_FIXNAMES]

    // ---- pass 1: generate every funcdef ----
    mov     w0, w26
    bl      getnode
    ldr     w24, [x0, #N_A]         // first program item
    mov     w23, w24
.Lhc_funcs:
    cbz     w23, .Lhc_entry
    mov     w0, w23
    bl      getnode
    mov     x20, x0
    ldr     w9, [x20, #N_TYPE]
    cmp     w9, #NODE_FUNCDEF
    b.ne    .Lhc_funcnext
    // fn_add(name, CG_POS)
    add     x0, x20, #N_NAME
    ldr     w1, [x19, #CG_POS]
    bl      fn_add
    // gen_func_common(params=node.a, body=block.a)
    ldr     w9, [x20, #N_B]         // block idx
    mov     w0, w9
    bl      getnode                 // block node
    ldr     w1, [x0, #N_A]          // body head
    ldr     w0, [x20, #N_A]         // params head
    bl      gen_func_common
.Lhc_funcnext:
    mov     w0, w23
    bl      getnode
    ldr     w23, [x0, #N_NEXT]
    b       .Lhc_funcs

.Lhc_entry:
    // ---- entry function for top-level statements ----
    ldr     w27, [x19, #CG_POS]     // entry offset
    mov     w0, #0                  // no params
    mov     w1, w24                 // body = program items list
    bl      gen_func_common
    bl      resolve_fixups

    ldr     w9, [x19, #CG_ERR]
    cbz     w9, .Lhc_ok
    mov     w27, #-1
.Lhc_ok:
    mov     w0, w27
    add     sp, sp, #16384
    ldr     x27, [sp, #80]
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #96
    ret
