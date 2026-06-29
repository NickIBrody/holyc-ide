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

// void hc_print_char(long c)
.global hc_print_char
.type hc_print_char, %function
hc_print_char:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    strb    w0, [sp, #24]
    add     x0, sp, #24
    mov     x1, #1
    bl      hc_print_str
    ldp     x29, x30, [sp], #32
    ret

// void hc_print_uint(long v)
.global hc_print_uint
.type hc_print_uint, %function
hc_print_uint:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    mov     x9, x0
    cbz     x9, .Lpu_zero
    add     x10, sp, #40
    mov     x11, #10
.Lpu_digit:
    udiv    x12, x9, x11
    msub    x13, x12, x11, x9
    add     w13, w13, #'0'
    sub     x10, x10, #1
    strb    w13, [x10]
    mov     x9, x12
    cbnz    x9, .Lpu_digit
    b       .Lpu_emit
.Lpu_zero:
    add     x10, sp, #40
    sub     x10, x10, #1
    mov     w13, #'0'
    strb    w13, [x10]
.Lpu_emit:
    add     x15, sp, #40
    sub     x1, x15, x10
    mov     x0, x10
    bl      hc_print_str
    ldp     x29, x30, [sp], #48
    ret

// void hc_print_cstr(const char *s)
.global hc_print_cstr
.type hc_print_cstr, %function
hc_print_cstr:
    cbz     x0, .Lpcstr_null
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     x9, x0
    mov     x10, #0
.Lpcstr_loop:
    ldrb    w11, [x9, x10]
    cbz     w11, .Lpcstr_emit
    add     x10, x10, #1
    b       .Lpcstr_loop
.Lpcstr_emit:
    cbz     x10, .Lpcstr_done
    mov     x1, x10
    bl      hc_print_str
.Lpcstr_done:
    ldp     x29, x30, [sp], #16
.Lpcstr_null:
    ret

// void hc_print_ptr(long p)  — prints as 0x%016llx
.global hc_print_ptr
.type hc_print_ptr, %function
hc_print_ptr:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    mov     x9, x0
    add     x12, sp, #34           // end of 16-char hex field
    mov     x13, #16
.Lpp_hex:
    and     x14, x9, #0xF
    cmp     x14, #10
    add     x15, x14, #'0'
    add     x16, x14, #('a'-10)
    csel    x14, x15, x16, lt
    sub     x12, x12, #1
    strb    w14, [x12]
    lsr     x9, x9, #4
    sub     x13, x13, #1
    cbnz    x13, .Lpp_hex
    sub     x12, x12, #2
    mov     w13, #'0'
    strb    w13, [x12]
    mov     w13, #'x'
    strb    w13, [x12, #1]
    mov     x0, x12
    mov     x1, #18
    bl      hc_print_str
    ldp     x29, x30, [sp], #48
    ret

// void *hc_malloc(long size)
.global hc_malloc
.type hc_malloc, %function
hc_malloc:
    cbz     x0, .Lmalloc_null
    stp     x29, x30, [sp, #-32]!
    stp     x19, x20, [sp, #16]
    mov     x29, sp
    add     x19, x0, #16           // total = requested + 16 for header
    mov     x0, #0
    mov     x1, x19
    mov     x2, #3                 // PROT_READ|WRITE
    mov     x3, #0x22              // MAP_PRIVATE|MAP_ANONYMOUS
    mov     x4, #-1                // fd
    mov     x5, #0
    mov     x8, #222               // __NR_mmap
    svc     #0
    tbnz    x0, #63, .Lmalloc_err
    str     x19, [x0]
    add     x0, x0, #16
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.Lmalloc_err:
    mov     x0, #0
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.Lmalloc_null:
    mov     x0, #0
    ret

// void hc_free(void *ptr)
.global hc_free
.type hc_free, %function
hc_free:
    cbz     x0, .Lfree_null
    sub     x0, x0, #16
    ldr     x1, [x0]               // size stored at header
    mov     x8, #215               // __NR_munmap
    svc     #0
.Lfree_null:
    ret

// long hc_strlen(const char *s)
.global hc_strlen
.type hc_strlen, %function
hc_strlen:
    cbz     x0, .Lslen_zero
    mov     x9, #0
.Lslen_loop:
    ldrb    w10, [x0, x9]
    cbz     w10, .Lslen_done
    add     x9, x9, #1
    b       .Lslen_loop
.Lslen_done:
    mov     x0, x9
    ret
.Lslen_zero:
    mov     x0, #0
    ret

// char *hc_strcpy(char *dst, const char *src)
.global hc_strcpy
.type hc_strcpy, %function
hc_strcpy:
    mov     x9, x0
    mov     x10, #0
.Lscpy_loop:
    ldrb    w11, [x1, x10]
    strb    w11, [x0, x10]
    cbz     w11, .Lscpy_done
    add     x10, x10, #1
    b       .Lscpy_loop
.Lscpy_done:
    mov     x0, x9
    ret

// char *hc_strcat(char *dst, const char *src)
.global hc_strcat
.type hc_strcat, %function
hc_strcat:
    mov     x9, x0
    mov     x10, #0
.Lscat_find:
    ldrb    w11, [x0, x10]
    cbz     w11, .Lscat_copy
    add     x10, x10, #1
    b       .Lscat_find
.Lscat_copy:
    mov     x11, #0
.Lscat_loop:
    ldrb    w12, [x1, x11]
    strb    w12, [x0, x10]
    cbz     w12, .Lscat_done
    add     x10, x10, #1
    add     x11, x11, #1
    b       .Lscat_loop
.Lscat_done:
    mov     x0, x9
    ret

// long hc_get_tsc(void)  — ARM64 generic timer virtual count
.global hc_get_tsc
.type hc_get_tsc, %function
hc_get_tsc:
    mrs     x0, cntvct_el0
    ret
