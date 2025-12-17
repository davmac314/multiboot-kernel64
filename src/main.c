// Put a message at the top line of the VGA text-mode screen.
// This won't work if the display is not a VGA-compatible text-mode display...

#include <stdint.h>

const char msg1[] = "WE ARE 64 BIT NOW";
const char msg2[] = "WOOHOO!";

struct multiboot_info {
    uint32_t flags;
    uint32_t mem_lower;
    uint32_t mem_upper;
    uint32_t boot_device;
    uint32_t cmdline;
    uint32_t mods_count;
    uint32_t mods_addr;
    
    // syms (for ELF; present if flags:5 is set)
    uint32_t syms_num;
    uint32_t syms_size;
    uint32_t syms_addr;
    uint32_t syms_shndex;
    
    // memory map (if flags:6 is set)
    uint32_t mmap_length;  // 44
    uint32_t mmap_addr;
    
    // disk drives (flags:7)
    uint32_t drives_length;
    uint32_t drives_addr;
    
    uint32_t config_table; // (if flags:8 set)
    uint32_t boot_loader_name;  // (if flags:9 set)
    uint32_t apm_table; // (if flags:10 set)
    
    // VBE info, present if flags:11 is set
    uint32_t vbe_control_info;
    uint32_t vbe_mode_info;
    uint16_t vbe_mode;
    uint16_t vbe_interface_seg;
    uint16_t vbe_interface_off;
    uint16_t vbe_interface_len;
    
    // framebuffer (flags:12)
    uint64_t framebuffer_addr;
    uint32_t framebuffer_pitch;
    uint32_t framebuffer_width;
    uint32_t framebuffer_height;
    uint8_t framebuffer_bpp;
    uint8_t framebuffer_type; // 0 = indexed, 1 = direct color, 2 = text mode
    union {
        char _color_info[6];
        // type 0:
        struct {
            uint32_t pallette_addr;
            uint16_t pallette_num_colors;
        } indexed;
        // type 1:
        struct {
            uint8_t red_field_position;
            uint8_t red_mask_size;
            uint8_t green_field_position;
            uint8_t green_mask_size;
            uint8_t blue_field_position;
            uint8_t blue_mask_size;
        } direct;
    } framebuffer_color_info;
};

void kernel_main(int mb_magic, struct multiboot_info *mb_info_ptr)
{
    if (mb_magic != 0x2BADB002) {
        return;
    }

    // Make sure we have an EGA/VGA(like) text mode, and determine the frame address
    _Bool have_tm = 0;
    volatile char *tm;
    uint16_t tm_pitch;
    
    // First, check "framebuffer" information
    if (mb_info_ptr->flags & (1u << 12)) {
        if (mb_info_ptr->framebuffer_type == 2 /* type 2 = text mode */) {
            tm = (char *)mb_info_ptr->framebuffer_addr;
            tm_pitch = mb_info_ptr->framebuffer_pitch;
            have_tm = 1;
        }
    }
    // 2nd, Qemu generally always boots in 80x25 mode, standard VGA mode
    // (Qemu doesn't provide the framebuffer information, making this kludge necessary)
    if (!have_tm && (mb_info_ptr->flags & (1u << 9))) {
        char *bl_name = (char *)(uintptr_t)mb_info_ptr->boot_loader_name;
        if (bl_name[0] == 'q' && bl_name[1] == 'e' && bl_name[2] == 'm' && bl_name[3] == 'u'
                && bl_name[4] == 0) {
            tm = (char *)0xB8000;
            tm_pitch = 160;
            have_tm = 1;
        }
    }
    
    if (!have_tm) {
        return;
    }
    
    volatile char *ss = tm;
    for (int i = 0; i < sizeof(msg1) - 1; i++) {
        *ss++ = msg1[i];
        *ss++ = 0x40;
    }
    
    ss = tm + tm_pitch; // i.e. next line
    for (int i = 0; i < sizeof(msg2) - 1; i++) {
        *ss++ = msg2[i];
        *ss++ = 0x40;
    }

    return;
}
