.syntax unified
.arch armv4t
.arm
.global _start
.text
_start:
    mov r0, #0
    mov r1, #10
.Lloop:
    add r0, r0, r1
    subs r1, r1, #1
    bne .Lloop
    mov r2, #0x100
    str r0, [r2]             @ RAM[0x100] = 1 + ... + 10 = 55
    svc #0                  @ tiny_cpu monitor stop
