
[bits 16]
[org 0x7c00]

%ifndef KERNEL_SECTORS
%define KERNEL_SECTORS 24
%endif

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti
    mov [boot_drive], dl

    mov si, msg_boot
    call print

    mov ah, 0x08
    int 0x13
    jc .default_geo
    and cl, 0x3F
    jz .default_geo
    mov [spt], cl
    inc dh
    mov [heads], dh
    jmp .geo_done
.default_geo:
    mov byte [spt], 18
    mov byte [heads], 2
.geo_done:
    xor ax, ax
    mov es, ax                                                                    AH=08 may trash ES


    mov word [cur_lba], 1
    mov word [dest_seg], 0x07E0
    mov cx, KERNEL_SECTORS
.load:
    push cx
    call read_sector
    jc disk_error
    inc word [cur_lba]
    add word [dest_seg], 0x20   
    pop cx
    loop .load

    mov dl, [boot_drive]
    jmp 0x07E0:0x0000

read_sector:                    
    mov ax, [cur_lba]
    xor dx, dx
    xor bx, bx
    mov bl, [spt]
    div bx                      
    inc dl
    mov cl, dl                  
    xor dx, dx
    xor bx, bx
    mov bl, [heads]
    div bx                      
    mov dh, dl
    mov ch, al
    shl ah, 6
    or cl, ah
    mov dl, [boot_drive]
    mov ax, [dest_seg]
    mov es, ax
    xor bx, bx
    mov di, 3
.try:
    push cx
    push dx
    mov ax, 0x0201
    int 0x13
    pop dx
    pop cx
    jnc .ok
    push cx
    push dx
    xor ax, ax
    int 0x13                    
    pop dx
    pop cx
    dec di
    jnz .try
    stc
    ret
.ok:
    xor ax, ax
    mov es, ax
    clc
    ret

print:
    lodsb
    test al, al
    jz .done
    mov ah, 0x0E
    int 0x10
    jmp print
.done:
    ret

disk_error:
    mov si, msg_err
    call print
    jmp $

msg_boot db 'TorbSL Desktop: loading kernel...', 13, 10, 0
msg_err  db 'Disk error :( 0x1', 0
boot_drive db 0
spt      db 18
heads    db 2
cur_lba  dw 1
dest_seg dw 0x07E0

times 510-($-$$) db 0
dw 0xAA55
