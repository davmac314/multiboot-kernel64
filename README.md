# Multiboot stub for a 64-bit kernel

This repository contains a well-documented example of how to construct a 64-bit (x86_64),
"higher-half"-mapped kernel (or other payload) that can be booted using multiboot, including with
Qemu's limited multiboot support (which allows for very easily running a kernel in emulation under
Qemu).

In particular, support for Qemu means a 32-bit ELF file must be produced. This is achieved by
creating a fully-resolved 64-bit ELF and then using `objcopy` to reframe it as a 32-bit ELF.

It consists mainly of two files:
- [entry.s](src/entry.s), an assembly stub containing a 32-bit entry point that sets up page
  tables, performs a transition to long (64-bit) mode, and jumps to the higher-half mapped
  kernel entry point (`kernel_main`, which may be written in C or another language).
- [linkscript.ld](src/linkscript.ld), a linker script which neatly combines the 32-bit stub
  with the 64-bit kernel proper.

In addition, an example "kernel" [is included](src/main.c). It simply displays a message on the
(text mode) screen. Finally, makefiles are provided for building the complete example.

The example will likely need to be tweaked for a "real" kernel (eg a kernel that exceeds 1MB
in size). Note that the code assumes that it is running on a 64-bit processor (it does no feature
checks to ensure that this is the case; doing that is left as an exercise).

Use the Makefile at the top level to build and run. The following are available:
- `make all` : build
- `make run` : run in Qemu
- `make clean` : clean up (remove) all files produced by the build

The Makefile assumes that GCC and binutils built to target "x86_64-elf" (i.e. cross-compiler) are
available, but depending on how they are configured you may be able to build using the system
compiler and binutils (by editing the Makefile appropriately).


## None of these words mean anything to me

For details on kernel-development concepts and introduction to terms such as "higher-half", see
the [OSDev wiki](https://wiki.osdev.org).


## But why?

Mainly, this was an interesting exercise for me. For a hobbyist OS developer, it is useful to be
able to run kernels directly via Qemu, but even if that is not a goal, this serves as a good
example of how to boot a 64-bit kernel using an outdated but widely-supported boot protocol.

Note that there are much better boot protocols than multiboot - unless you really need multiboot
support, you may be better off looking elsewhere.


## A personal note

I really don't like the term "higher-half"; "negative-half" would make much more sense as that is
essentially how the addresses are interpreted (i.e. as negative signed values rather than very high
unsigned positive values). But, it's widely in use, so here we are.


## License

You are free to use this software, in source or compiled form, however you wish, though entirely
at your own risk.
