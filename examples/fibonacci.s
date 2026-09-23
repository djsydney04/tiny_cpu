.syntax unified
.arch armv4t
.arm
.global _start
.text
_start:
    mov r0, #0
    mov r1, #1
    mov r2, #0x100
    mov r3, #12
.Lloop:
    str r0, [r2], #4
    add r4, r0, r1
    mov r0, r1
    mov r1, r4
    subs r3, r3, #1
    bne .Lloop
    svc #0                  @ RAM: 0,1,1,2,3,5,8,13,21,34,55,89
