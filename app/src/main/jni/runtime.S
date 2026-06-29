// runtime.S — JIT memory, execution, and HolyC output helpers (ARM64).
//
// The generated machine code calls hc_print_str / hc_print_int (their
// absolute addresses are baked in by codegen).  Both append to a global
// output buffer which the JNI bridge reads back after execution.

.set OUT_CAP, 262144

.bss
.align 4
// Kept local (not .global) so adrp/:lo12: resolve directly within the .so;
// a preemptible global symbol would force GOT relocations that ld.lld
// rejects for ADR_PREL_PG_HI21.  The bridge reaches these via hc_out_data().
hc_out_buf:
    .skip OUT_CAP
.align 3
hc_out_len:
    .skip 8

.text

// void hc_out_reset(void)
.global hc_out_reset
.type hc_out_reset, %function
hc_out_reset:
    adrp    x9, hc_out_len
    add     x9, x9, :lo12:hc_out_len
    str     xzr, [x9]
    ret

// long hc_out_size(void)
.global hc_out_size
.type hc_out_size, %function
hc_out_size:
    adrp    x9, hc_out_len
    add     x9, x9, :lo12:hc_out_len
    ldr     x0, [x9]
    ret

// const char *hc_out_data(void)
.global hc_out_data
.type hc_out_data, %function
hc_out_data:
    adrp    x0, hc_out_buf
    add     x0, x0, :lo12:hc_out_buf
    ret

// void hc_print_str(const char *p, long len)
.global hc_print_str
.type hc_print_str, %function
hc_print_str:
    adrp    x9, hc_out_len
    add     x9, x9, :lo12:hc_out_len
    ldr     x10, [x9]                   // current length
    adrp    x11, hc_out_buf
    add     x11, x11, :lo12:hc_out_buf
    mov     x12, #(OUT_CAP - 1)
    mov     x13, #0
1:  cmp     x13, x1
    b.ge    2f
    add     x14, x10, x13
    cmp     x14, x12
    b.ge    2f
    ldrb    w15, [x0, x13]
    strb    w15, [x11, x14]
    add     x13, x13, #1
    b       1b
2:  add     x10, x10, x13
    str     x10, [x9]
    ret

// void hc_print_int(long v)
.global hc_print_int
.type hc_print_int, %function
hc_print_int:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    mov     x9, x0                      // value
    mov     x14, #0                     // negative flag
    tbz     x9, #63, .Lpi_abs
    mov     x14, #1
    neg     x9, x9
.Lpi_abs:
    add     x10, sp, #40                // write digits backward from here
    mov     x11, #10
.Lpi_digit:
    udiv    x12, x9, x11
    msub    x13, x12, x11, x9           // remainder
    add     w13, w13, #'0'
    sub     x10, x10, #1
    strb    w13, [x10]
    mov     x9, x12
    cbnz    x9, .Lpi_digit
    cbz     x14, .Lpi_emit
    sub     x10, x10, #1
    mov     w13, #'-'
    strb    w13, [x10]
.Lpi_emit:
    add     x15, sp, #40
    sub     x1, x15, x10                // length
    mov     x0, x10                     // pointer
    bl      hc_print_str
    ldp     x29, x30, [sp], #48
    ret

// void *hc_jit_alloc(long size)   — mmap RWX, MAP_PRIVATE|MAP_ANON
.global hc_jit_alloc
.type hc_jit_alloc, %function
hc_jit_alloc:
    mov     x1, x0                      // length
    mov     x0, #0                      // addr = NULL
    mov     x2, #7                      // PROT_READ|WRITE|EXEC
    mov     x3, #0x22                   // MAP_PRIVATE|MAP_ANONYMOUS
    movn    x4, #0                      // fd = -1
    mov     x5, #0                      // offset
    mov     x8, #222                    // __NR_mmap
    svc     #0
    ret

// long hc_run(void *entry)  — call the JIT entry, return its result
.global hc_run
.type hc_run, %function
hc_run:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    blr     x0
    ldp     x29, x30, [sp], #16
    ret
