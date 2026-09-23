ENTRY(_start)
MEMORY { ram (rwx) : ORIGIN = 0, LENGTH = 64K }
SECTIONS {
    .text : { *(.text .text.*) } > ram
    .rodata : { *(.rodata .rodata.*) } > ram
    .data : { *(.data .data.*) } > ram
    .bss (NOLOAD) : { *(.bss .bss.*) *(COMMON) } > ram
    /DISCARD/ : { *(.ARM.exidx*) *(.ARM.extab*) *(.comment) }
}
ASSERT(_start == 0, "_start must be at reset address zero")
