# Example of a multiboot stub to transition to 64-bit long mode with a "higher-half" kernel, which
# can be written in C (for example).
#
# This is written to be assembled with GNU "as", and uses the AT&T assembly language dialect.
# It goes together with an accompanying linker script.
#
# This should not be considered production quality. It:
# - does not verify a 64-bit capable processor before attempting to switch, and has no error
#   handling
# - expects the entire kernel (i.e. the linked executable comprising this code and the main
#   kernel) to be loaded within the first 2MB of physical memory (the linker script will report
#   any violation of this constraint)
#
# The basic functionality provided here is:
# - set up a small initial stack
# - set up page tables which identity map the first 2MB and set up a mirror mapping in the
#   "higher half"
# - transition to a GDT which includes a 64-bit code segment
# - transition to long mode and the 64-bit code segment
# - jump to the kernel (residing in the mapped region of the higher half)


# Multiboot header

.set MB_FLAG_ALIGN, 1    #  align loaded modules on page boundaries
.set MB_FLAG_MEMINFO, 2  #  provide memory information / map

.set MB_MAGIC, 0x1BADB002      # "Magic" value so the bootloader recognises the kernel
.set MB_FLAGS, MB_FLAG_ALIGN | MB_FLAG_MEMINFO  # Value for the multiboot flags field
.set MB_CHECKSUM, -(MB_MAGIC + MB_FLAGS) # Multiboot checksum

.section .multiboot, "a"
.align 4
.long MB_MAGIC
.long MB_FLAGS
.long MB_CHECKSUM


# Entry point (32-bit multiboot entry point)
# We have this in its own section, ".boot", and specify an identity mapping for this section in
# the link script (unlike the main kernel sections which are higher-half mapped).
.section .boot, "ax"
.code32
.global _start
.type _start, @function
_start:
    # Set up initial stack
    movl $stack_top, %esp

    # Save multiboot magic value and info pointer from (EAX, EBX) into (EDI, ESI)
    movl %eax, %edi
    movl %ebx, %esi

    # We have to do a little dance to get to 64-bit mode with a "higher-half" kernel. First, we
    # need to set up the page tables and load CR3 (_setup_page_tables). We also need to set up a
    # GDT with a 64-bit code segment, enable long mode (set PAE in CR4, set LME in the EFER MSR,
    # set PG in CR0). We can then do a far jump (ljmp) to the 64-bit code segment, but only with
    # a 32-bit offset; the final step is to jump to the real higher-half entry point.

    # Set up (64-bit, 4-level) page tables
    call _setup_page_tables

    # Load our GDT (32-bit CS = $8)
    lgdt bootstrap_gdt_ptr

    # Since we have a GDT anyway, let's transition to it properly before we do anything else. This
    # shouldn't actually be necessary, but it seems cleaner.
    ljmp $8, $_on_our_gdt   # 8 = 32-bit CS

_on_our_gdt:
    movl $16, %eax  # 16 = data segment
    movl %eax, %ds
    movl %eax, %es
    movl %eax, %ss

    # Now transition to long mode (compatibility mode, i.e. still executing 32-bit code for now):
    movl %cr4, %eax
    orl $(1 << 5), %eax  # PAE
    movl %eax, %cr4

    movl $0xC0000080, %ecx  # EFER
    rdmsr
    orl $(1 << 8), %eax     # LME
    wrmsr

    movl %cr0, %eax
    orl $(1 << 31), %eax    # PG
    movl %eax, %cr0

    # Now transition to 64-bit mode:
    ljmp $24, $_long_bootstrap

.code64

_long_bootstrap:

    # We've done it; we're now 64-bit! There's no need to reload DS/ES/SS at this point, they are
    # still valid (the base/limit will be ignored).

    # Call main 64-bit kernel entry point.
    # RDI, RSI already contain multiboot parameters (magic, info block pointer).
    movq $kernel_main, %rax
    callq *%rax

    # Above should not return; if it does, just sleep.
    cli
1:  hlt
    jmp 1b

.size _start, . - _start

# Setup page tables. Create an identity mapping spanning the first 2MB, and a mapping of the same
# range at 0xFFFFFFFF80000000 (i.e. at the beginning of the top 2GB of what some call the
# "higher-half" of the address space).
#
# Higher half address, broken down to binary and then indexes:
# 0xFFFF         F F F F              8 0 0 0               0    000
#   (1111...)   1111 1111 1111 1111  1000 0000 0000 0000    0000 (nnnn...)
#               |          |           |          |              |
#               +-bit 47   |           |         bit 20        bit 11
#                          |           |
#                          +-bit 38    |             bit 47-39 = 111111111b = 511
#                                      |             bit 38-30 = 111111110b = 510
#                                      +-bit 29      bit 29-21 = 000000000b = 0
#                                                  
#                                                                             ^
#                                                                             |
#                                                     these are the indexes --+
#
# So, the mapping to higher half is created via:
#    pml4[511] -> pdpt[510] -> pd[0] -> pt[0 - 511]
#                  ^
#                  |
#                  +-- we will use 'pt_pdpt_hh' for this PDPT
#
# (Starting at bit 47, peel 9 bits off for each index: 511, 510, 0, XXX).
#
# The identity mapping of course is through:
#    pml4[0] -> pdpt[0] -> pd[0] -> pt[0 - 511]
#
# Since the page directory (PD) in both mappings is the same we can use the same physical PD page
# for both (and so will also use the same page table PT as a result).
#
.code32
.type _setup_page_tables, @function
_setup_page_tables:
    # first set up page table:
    movl $3, %eax    # bit 0 = (P)resent, bit 1 = (W)ritable
    movl $0, %ecx
1:  movl %eax, pt_pt(,%ecx,8)
    movl $0, pt_pt+4(,%ecx,8)
    addl $0x1000, %eax
    incl %ecx
    cmpl $512, %ecx
    jne 1b

    # set up pml4[0]
    movl $(pt_pdpt + 3), pt_pml4
    movl $0, pt_pml4 + 4
    # set up pml4[511]
    movl $(pt_pdpt_hh + 3), pt_pml4 + (511*8)
    movl $0, pt_pml4 + 4 + (511*8)
    # set up pdpt[0]
    movl $(pt_pd + 3), pt_pdpt
    movl $0, pt_pdpt + 4
    # set up pdpt_hh[510]
    movl $(pt_pd + 3), pt_pdpt_hh + (510*8)
    movl $0, pt_pdpt_hh + 4 + (510*8)

    # set up pd[0]
    movl $(pt_pt + 3), pt_pd
    movl $0, pt_pd + 4

    # load CR3
    movl $pt_pml4, %eax
    movl %eax, %cr3

    ret

.size _setup_page_tables, . - _setup_page_tables

# GDT "pointer" structure, used with LGDT instruction.
.align 2
bootstrap_gdt_ptr:
    .word 8*4-1;
    .long bootstrap_gdt

# A GDT that we use in the transition to 64-bit mode.
.align 8
bootstrap_gdt:
    # null segment:
    .long 0, 0
    # 32-bit code segment:
    .long 0x0000FFFF, 0x00CF9A00
    # 32/64-bit data, stack:
    .long 0x0000FFFF, 0x00CF9200
    # 64-bit code segment:
    .long 0x0000FFFF, 0x002F9A00


# BSS (uninitialised data) section. This *should* be zeroed out by the bootloader. This section
# will not consume space in the linked executable file.

.section .boot_bss, "aw", @nobits

# Initial page tables
.align 4096
pt_pml4:
    .skip 4096
pt_pdpt:
    .skip 4096
pt_pdpt_hh:
    .skip 4096
pt_pd:
    .skip 4096
pt_pt:
    .skip 4096

# Stack space
.align 16
stack_bottom:
    .skip 16384 # 16 KiB
stack_top:
