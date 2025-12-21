/*
 * Example linker script for creating a multiboot-enabled 64-bit kernel.
 *
 * This example accompanies an assembly-language bootstrap code sample (entry.s).
 *
 * Multiboot is pretty primitive. We have to choose a specific load address - see
 * kernel_load_memory_address below. This script will set things up so that the entire kernel
 * image is loaded at that address, which should be in the first 2MB of memory so that it exists
 * in the identity mapping (and the higher-half mapping) that is created by code in entry.s.
 *
 * The 64-bit portion of the kernel is given (by this script) a virtual address in the higher-half
 * which corresponds exactly with the physical address where the portion is loaded, once the page
 * table mappings are in place, so that no relocation is necessary.
 *
 * The layout in (physical) memory is roughly:
 *
 *   +-----------------------------------------------------------+
 *   | .boot section - multiboot header and 32-bit entry point   |
 *   +-----------------------------------------------------------|
 *   | .text/.rodata/.data - 64-bit kernel sections and          |
 *   | 64-bit kernel entry point ("kernel_main").                |
 *   |                                                           |
 *   | The virtual address is offset by the higher-half offset.  |
 *   |                                                           |
 *   +-----------------------------------------------------------+  <--- FILE ENDS HERE
 *   | .bss - 64-bit kernel "BSS" (uninitialised section). This  |
 *   | should be zeroed by the bootloader (Grub, Qemu, etc).     |
 *   | The virtual address is offset by the higher-half offset.  |  The BSS sections do not take
 *   +-----------------------------------------------------------+  up space in the output file.
 *   | .boot_bss section - 32-bit entry code "BSS". This should  |
 *   | be zeroed by the bootloader. It is used for the initial   |
 *   | stack and page tables.                                    |
 *   +-----------------------------------------------------------+
 *
 * Using this layout requires "moving the dot" backwards before the .boot_bss section, which will
 * generate a warning at link time (that may be spat out multiple times):
 *
 *   ld: warning: dot moved backwards before `.boot_bss'
 *
 * This is harmless and can be ignored. The alternative would be to move the ".boot_bss" section
 * just after the ".boot" section, however this ends up making the file larger because:
 *  1. the boot_bss section is page-aligned (because it contains page table storage which is page-
 *     aligned) and so forces a page alignment between the .boot and .text sections, which is
 *     otherwise not needed.
 *  2. although the space due to that alignment doesn't technically need to be stored in the file,
 *     it seems that GNU ld likes to embed it, probably with the aim of allowing the file to be
 *     loaded "in whole" (or as much as possible) to a single address.
 */

/*
 * Offset bewteen identity mapping and "higher-half" linear mapping. Code in entry.s sets up this
 * mapping and will need to be adjusted if this value is changed.
 *
 * In general this should be at _least_ 0xFFFFFFFF80000000, i.e. -2GB, which allows using the
 * efficient "kernel" memory model when compiling the 64-bit kernel ("-mcmodel=kernel") - i.e. it
 * allows kernel addresses to be represented using a 32-bit sign-extended value rather than
 * requiring a 64-bit value.
 */
hh_map_offset = 0xFFFFFFFF80000000;

/*
 * Physical address where the kernel will be loaded.
 *
 * 1MB (0x00100000) is the traditional choice: it's (almost) beyond the real-mode addressable
 * region and in a BIOS-booted system should be available. That means the maximum possible kernel
 * size is 1MB (since only the first 2MB of memory is mapped by the code in entry.s).
 */
kernel_load_memory_address = 0x00100000; /* 1 MB */


ENTRY(_start)

SECTIONS
{
    . = kernel_load_memory_address;

    .boot :
    {
        KEEP(*(.multiboot))
        *(.boot)
    }

/****** 64-bit kernel sections here ********/

    /* 
     * The "higher-half"-mapped kernel will be put in a separate ELF segment
     * by the linker, automatically.
     */

    . = . + hh_map_offset;

    . = ALIGN(ALIGNOF(NEXT_SECTION));
    .text . : AT(ADDR(.text) - hh_map_offset)
    {
        *(.text)
        *(.text.*)
    }

    . = ALIGN(ALIGNOF(NEXT_SECTION));
    .rodata : AT(ADDR(.rodata) - hh_map_offset)
    {
        *(.rodata)
        *(.rodata.*)
    }

    . = ALIGN(0x1000);
    . = ALIGN(ALIGNOF(NEXT_SECTION));
    .data : AT(ADDR(.data) - hh_map_offset)
    {
        *(.data)
        *(.data.*)
    }

    .bss :
    {
        *(COMMON)
        *(.bss)
        *(.bss.*)
    }

/****** 64-bit kernel sections end ********/

    /*
     * Now we adjust the '.' location counter to return to identity-mapped addressing, because we
     * want to drop the bootstrap's own BSS section here:
     */
    . = . - hh_map_offset;

    .boot_bss :
    {
        *(.boot_bss)
        ASSERT(ABSOLUTE(.) < 2M, "Entire kernel image does not fit within first 2MB");
    }

    /DISCARD/ : /* discard some stuff that's not needed or is problematic. */
    {
        *(.comment)
        *(.note.gnu.property)
        *(.note.GNU-stack)
        *(.dynamic)
        *(.eh_frame)
    }
}
