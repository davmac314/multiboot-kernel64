# It's considered by some to be good practice to use a cross-compiler for OS development.
# However, you may well get by by using your system's standard utilities, in which case,
# set the below accordingly (to gcc, ld, as, and objcopy, respectively).
CC = x86_64-elf-gcc
LD = x86_64-elf-ld
AS = x86_64-elf-as
OBJCOPY = x86_64-elf-objcopy

export CC LD AS OBJCOPY

all:
	$(MAKE) -C src all

run: all
	qemu-system-x86_64 -no-reboot -d int -kernel src/kernel.elf

clean:
	$(MAKE) -C src clean
