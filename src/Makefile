# CC, AS, LD, OBJCOPY should be inherited from calling

CC ?= gcc
AS ?= as
LD ?= ld
OBJCOPY ?= objcopy

all: kernel.elf

clean:
	rm -f kernel.elf kernel.elf64 main.o entry.o

entry.o: entry.s
	$(AS) -g -o entry.o entry.s

main.o: main.c
	$(CC) -g -ffreestanding -mcmodel=kernel -mgeneral-regs-only -Os -c main.c

kernel.elf64: entry.o main.o linkscript.ld
	$(LD) -z noexecstack -T linkscript.ld entry.o main.o -o kernel.elf64 -Map kernel.elf64.map

# Qemu refuses to run multiboot kernels encapsulated as 64-bit ELF files.
# Although in theory we can link straight to a 32-bit ELF:
#
#    ld -T linkscript.ld --oformat elf32-i386 ...
#
# ... this will process relocations as 32-bit, and the resulting file is broken.
# So, link to 64-bit ELF, and then use "objcopy" to translate to 32-bit ELF:
kernel.elf: kernel.elf64
	$(OBJCOPY) kernel.elf64 -O elf32-i386 kernel.elf
