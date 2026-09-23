.syntax unified
.arch armv4t
.arm
.global _start
.text
_start:
    mov sp, #0x10000
    mov r0, #48
    mov r1, #18
    bl .Lgcd
    mov r2, #0x100
    str r0, [r2]             @ greatest common divisor = 6
    svc #0
.Lgcd:
    str lr, [sp, #-4]!
.Lloop:
    cmp r0, r1
    subgt r0, r0, r1
    sublt r1, r1, r0
    bne .Lloop
    ldr lr, [sp], #4
    bx lr
