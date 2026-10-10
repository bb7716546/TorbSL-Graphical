
bits 16
org 0x0000

KSEG        equ 0x07E0
BB_SEG      equ 0x2000
PAINT_SEG   equ 0x3000
VGA_SEG     equ 0xA000
STACK_TOP   equ 0x7C00

SCR_W       equ 320
SCR_H       equ 200
TASK_Y      equ 186
NWIN        equ 3
TERM_COLS   equ 28
TERM_ROWS   equ 12
INPUT_MAX   equ 19
PAINT_W     equ 208
PAINT_H     equ 100
MENU_ITEMS  equ 4
MENU_H      equ MENU_ITEMS*14+4
MENU_Y      equ TASK_Y-MENU_H
CUR_W       equ 12
CUR_H       equ 13


%macro RECT 5
    mov al, %1
    mov bx, %2
    mov cx, %3
    mov dx, %4
    mov si, %5
    call fill_rect
%endmacro


%macro RECTO 5
    mov al, %1
    mov bx, [or_x]
    add bx, %2
    mov cx, [or_y]
    add cx, %3
    mov dx, %4
    mov si, %5
    call fill_rect
%endmacro


start:
    cli
    cld
    xor ax, ax
    mov ss, ax
    mov sp, STACK_TOP
    mov ax, KSEG
    mov ds, ax
    mov es, ax
    sti


    push es
    xor ax, ax
    mov es, ax
    cli
    mov word [es:0x00], divide_error
    mov word [es:0x02], KSEG
    sti
    pop es

    push ds                     
    mov ax, 0x0040
    mov ds, ax
    mov eax, [0x006C]
    pop ds
    mov [boot_ticks], eax

    call init_font
    mov ax, 0x0013              
    int 0x10
    call set_palette
    call splash
    call init_mouse
    call paint_clear
    call term_init
    mov byte [dirty], 1
    jmp gui_loop

gui_loop:
    cli
    mov sp, STACK_TOP           
    sti
    cld
    call check_tick
    cmp byte [dirty], 0
    je .nodraw
    mov byte [dirty], 0
    call render
.nodraw:
    call handle_mouse
    mov ah, 1
    int 0x16
    jz .nokey
    xor ax, ax
    int 0x16
    call handle_key
.nokey:
    cli
    cmp byte [m_dirty], 0
    jne .loop
    cmp byte [dirty], 0
    jne .loop
    sti
    hlt
.loop:
    sti
    jmp gui_loop

check_tick:                    
    push ax
    push ds
    mov ax, 0x0040
    mov ds, ax
    mov ax, [0x006C]
    pop ds
    push ax
    sub ax, [last_tick]
    cmp ax, 9
    pop ax
    jb .no
    mov [last_tick], ax
    mov byte [dirty], 1
    xor byte [blink], 1
.no:
    pop ax
    ret


fill_rect:                      
    pusha
    imul di, cx, SCR_W
    add di, bx
    mov bx, si
    mov ah, al
.row:
    push di
    mov cx, dx
    rep stosb
    pop di
    add di, SCR_W
    dec bx
    jnz .row
    popa
    ret

draw_char:                      
    pusha
    xor ah, ah
    and al, 0x7F
    shl ax, 3
    add ax, font_buf
    mov si, ax
    imul di, cx, SCR_W
    add di, bx
    mov dh, 8
.r:
    lodsb
    mov ah, al
    mov cx, 8
    push di
.p:
    shl ah, 1
    jnc .skip
    mov [es:di], dl
.skip:
    inc di
    loop .p
    pop di
    add di, SCR_W
    dec dh
    jnz .r
    popa
    ret

draw_text:                      
    push ax
    push bx
    push si
    mov dl, al
.l:
    lodsb
    test al, al
    jz .d
    call draw_char
    add bx, 8
    jmp .l
.d:
    pop si
    pop bx
    pop ax
    ret

draw_text_big:                  
    pusha
    mov [bt_col], al
    mov [bt_x], bx
    mov [bt_y], cx
.next:
    lodsb
    test al, al
    jz .end
    xor ah, ah
    and al, 0x7F
    shl ax, 3
    add ax, font_buf
    mov [bt_gl], ax
    xor di, di
.row:
    mov bx, [bt_gl]
    add bx, di
    mov bl, [bx]
    mov [bt_bits], bl
    mov word [bt_ci], 0
.col:
    shl byte [bt_bits], 1
    jnc .nopx
    mov ax, [bt_ci]
    mul word [bigscale]
    add ax, [bt_x]
    mov bx, ax
    mov ax, di
    mul word [bigscale]
    add ax, [bt_y]
    mov cx, ax
    mov dx, [bigscale]
    mov al, [bt_col]
    push si
    mov si, [bigscale]
    call fill_rect
    pop si
.nopx:
    inc word [bt_ci]
    cmp word [bt_ci], 8
    jb .col
    inc di
    cmp di, 8
    jb .row
    mov ax, 8
    mul word [bigscale]
    add [bt_x], ax
    jmp .next
.end:
    popa
    ret

init_font:                      
    mov ax, 0x1130
    mov bh, 3
    int 0x10                    
    push ds
    mov si, bp
    mov ax, es
    mov ds, ax
    mov ax, KSEG
    mov es, ax
    mov di, font_buf
    mov cx, 512
    cld
    rep movsw
    pop ds
    ret

set_palette:                    
    mov al, 64
    mov dx, 0x3C8
    out dx, al
    xor cx, cx
.p:
    mov ax, cx
    mov bl, 3
    div bl
    add al, 4
    mov dx, 0x3C9
    out dx, al                  
    mov ax, cx
    shr ax, 2
    add ax, cx
    add al, 6
    out dx, al                  
    mov al, cl
    add al, 26
    out dx, al                  
    inc cx
    cmp cx, 25
    jb .p
    ret

wait_ticks:                     
    push ax
    push bx
    push cx
    push dx
    push si
    mov si, cx
    mov ah, 0
    int 0x1A
    mov bx, dx
.w:
    sti
    hlt
    mov ah, 0
    int 0x1A
    mov ax, dx
    sub ax, bx
    cmp ax, si
    jb .w
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

splash:                         
    mov ax, VGA_SEG
    mov es, ax
    RECT 0, 0, 0, 320, 200
    mov word [bigscale], 4
    mov si, str_torbsl
    mov bx, 64
    mov cx, 56
    mov al, 11
    call draw_text_big
    mov si, str_loading
    mov bx, 60
    mov cx, 112
    mov al, 7
    call draw_text
    RECT 7, 59, 129, 202, 10
    RECT 0, 60, 130, 200, 8
    xor di, di
.bar:
    mov ax, di
    mov bx, 10
    mul bx
    add ax, 60
    mov bx, ax
    mov al, 10
    mov cx, 130
    mov dx, 10
    mov si, 8
    call fill_rect
    mov cx, 1
    call wait_ticks
    inc di
    cmp di, 20
    jb .bar
    mov cx, 5
    call wait_ticks
    mov ax, KSEG
    mov es, ax
    ret


init_mouse:
    mov byte [mouse_ok], 0
    mov word [m_x], 160
    mov word [m_y], 100
    mov ax, 0xC201              
    int 0x15
    jc .fail
    mov ax, 0xC205              
    mov bh, 3
    int 0x15
    jc .fail
    mov ax, 0xC203              
    mov bh, 3
    int 0x15
    mov ax, KSEG
    mov es, ax
    mov bx, mouse_handler
    mov ax, 0xC207              
    int 0x15
    jc .fail
    mov ax, 0xC200              
    mov bh, 1
    int 0x15
    jc .fail
    mov byte [mouse_ok], 1
.fail:
    ret


mouse_handler:
    push bp
    mov  bp, sp

    push ax
    push bx
    push ds

    mov  ax, KSEG
    mov  ds, ax


    mov  bl, [m_btn]


    mov  ax, [ss:bp+12]
    and  al, 7
    mov  [m_btn], al

  
    mov  ax, [ss:bp+10]
    cbw
    add  [m_x], ax

    cmp  word [m_x], 0
    jge  .x_upper
    mov  word [m_x], 0

.x_upper:
    cmp  word [m_x], SCR_W-1
    jle  .y_move
    mov  word [m_x], SCR_W-1

.y_move:
    mov  ax, [ss:bp+8]
    cbw
    sub  [m_y], ax

    cmp  word [m_y], 0
    jge  .y_upper
    mov  word [m_y], 0

.y_upper:
    cmp  word [m_y], SCR_H-1
    jle  .click_check
    mov  word [m_y], SCR_H-1

.click_check:
    mov  al, [m_btn]
    test al, 1
    jz   .done
    test bl, 1
    jnz  .done

    mov  byte [m_click], 1
    mov  ax, [m_x]
    mov  [m_clx], ax
    mov  ax, [m_y]
    mov  [m_cly], ax

.done:
    mov  byte [m_dirty], 1

    pop  ds
    pop  bx
    pop  ax
    pop  bp
    retf


handle_mouse:
    cmp byte [m_dirty], 0
    jne .go
    ret
.go:
    cli
    mov ax, [m_x]
    mov [cur_x], ax
    mov ax, [m_y]
    mov [cur_y], ax
    mov al, [m_btn]
    mov [cur_btn], al
    mov byte [m_dirty], 0
    sti
    mov byte [dirty], 1

    cmp byte [dragging], 0
    je .nodrag
    test byte [cur_btn], 1
    jz .enddrag
    xor ax, ax
    mov al, [drag_id]
    shl ax, 1
    mov di, ax
    mov ax, [cur_x]
    sub ax, [drag_dx]
    jge .xpos
    xor ax, ax
.xpos:
    mov cx, SCR_W-2
    sub cx, [win_w+di]
    cmp ax, cx
    jle .xok
    mov ax, cx
.xok:
    mov [win_x+di], ax
    mov ax, [cur_y]
    sub ax, [drag_dy]
    jge .ypos
    xor ax, ax
.ypos:
    mov cx, TASK_Y-2
    sub cx, [win_h+di]
    cmp ax, cx
    jle .yok
    mov ax, cx
.yok:
    mov [win_y+di], ax
    jmp .nodrag
.enddrag:
    mov byte [dragging], 0
.nodrag:

    cmp byte [painting], 0
    je .nopaint
    test byte [cur_btn], 1
    jz .endpaint
    call paint_stroke
    jmp .nopaint
.endpaint:
    mov byte [painting], 0
.nopaint:

    cmp byte [m_click], 0
    je .noclick
    cli
    mov byte [m_click], 0
    sti
    call on_click
.noclick:
    ret

on_click:                       
    pusha
    mov ax, [m_clx]
    mov bx, [m_cly]

    cmp bx, TASK_Y              
    jb .notask
    cmp ax, 46
    jae .tbbtns
    xor byte [menu_open], 1
    jmp .done
.tbbtns:
    mov byte [menu_open], 0
    xor si, si
.tl:
    cmp byte [win_vis+si], 0
    je .tn
    mov di, si
    shl di, 1
    mov cx, [tb_x+di]
    cmp ax, cx
    jb .tn
    add cx, 66
    cmp ax, cx
    jae .tn
    mov ax, si
    call raise_win
    jmp .done
.tn:
    inc si
    cmp si, NWIN
    jb .tl
    jmp .done

.notask:
    cmp byte [menu_open], 0     
    je .nomenu
    mov byte [menu_open], 0
    cmp ax, 2
    jb .done
    cmp ax, 83
    jae .done
    cmp bx, MENU_Y+2
    jb .done
    cmp bx, MENU_Y+2+MENU_ITEMS*14
    jae .done
    sub bx, MENU_Y+2
    mov ax, bx
    mov bl, 14
    div bl
    call launch_item
    jmp .done

.nomenu:
    mov [clk_x], ax             
    mov [clk_y], bx
    mov si, NWIN-1
.wl:
    xor ax, ax
    mov al, [zorder+si]
    mov di, ax
    cmp byte [win_vis+di], 0
    je .wn
    call load_win
    mov ax, [clk_x]
    cmp ax, [wx]
    jb .wn
    mov bx, [wx]
    add bx, [ww]
    cmp ax, bx
    jae .wn
    mov ax, [clk_y]
    cmp ax, [wy]
    jb .wn
    mov bx, [wy]
    add bx, [wh]
    cmp ax, bx
    jae .wn
    mov al, [cur_id]
    call raise_win
    jmp .hit
.wn:
    dec si
    jns .wl
    jmp .icons

.hit:
    mov ax, [clk_x]             
    mov bx, [wx]
    add bx, [ww]
    sub bx, 14
    cmp ax, bx
    jb .notclose
    add bx, 9
    cmp ax, bx
    jae .notclose
    mov ax, [clk_y]
    mov bx, [wy]
    add bx, 3
    cmp ax, bx
    jb .notclose
    add bx, 9
    cmp ax, bx
    jae .notclose
    xor bx, bx
    mov bl, [cur_id]
    mov byte [win_vis+bx], 0
    jmp .done
.notclose:
    mov ax, [clk_y]             
    mov bx, [wy]
    add bx, 14
    cmp ax, bx
    jae .content
    mov al, [cur_id]
    mov [drag_id], al
    mov byte [dragging], 1
    mov ax, [clk_x]
    sub ax, [wx]
    mov [drag_dx], ax
    mov ax, [clk_y]
    sub ax, [wy]
    mov [drag_dy], ax
    jmp .done
.content:
    cmp byte [cur_id], 1
    jne .done
    call paint_click
    jmp .done

.icons:                         
    mov ax, [clk_x]
    cmp ax, 2
    jb .done
    cmp ax, 66
    jae .done
    mov ax, [clk_y]
    sub ax, 9
    jb .done
    xor dx, dx
    mov bx, 44
    div bx
    cmp ax, NWIN
    jae .done
    cmp dx, 36
    jae .done
    call launch_item
.done:
    popa
    ret

launch_item:                    
    cmp al, 3
    je do_reboot
    push ax
    xor ah, ah
    mov si, ax
    mov byte [win_vis+si], 1
    pop ax
    call raise_win
    ret

raise_win:                      
    push ax
    push bx
    push cx
    push si
    push di
    mov bl, al
    mov si, zorder
    mov di, ztmp
    mov cx, NWIN
.l:
    lodsb
    cmp al, bl
    je .skip
    mov [di], al
    inc di
.skip:
    loop .l
    mov [di], bl
    mov si, ztmp
    mov di, zorder
    mov cx, NWIN
    rep movsb
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

load_win:                       
    push bx
    xor bx, bx
    mov bl, al
    mov [cur_id], bl
    shl bx, 1
    mov ax, [win_x+bx]
    mov [wx], ax
    mov ax, [win_y+bx]
    mov [wy], ax
    mov ax, [win_w+bx]
    mov [ww], ax
    mov ax, [win_h+bx]
    mov [wh], ax
    pop bx
    ret

calc_focus:                     
    mov byte [focus_id], 0xFF
    mov si, NWIN-1
.l:
    xor ax, ax
    mov al, [zorder+si]
    mov di, ax
    cmp byte [win_vis+di], 0
    je .n
    mov [focus_id], al
    ret
.n:
    dec si
    jns .l
    ret

handle_key:                     
    push ax
    call calc_focus
    pop ax
    cmp byte [focus_id], 0      
    jne .ret
    cmp al, 0x0D
    je .enter
    cmp al, 0x08
    je .back
    cmp al, 0x20
    jb .ret
    cmp al, 0x7E
    ja .ret
    mov bx, [input_len]
    cmp bx, INPUT_MAX
    jae .ret
    mov [input_buffer+bx], al
    inc word [input_len]
    call term_putc
    mov byte [dirty], 1
.ret:
    ret
.back:
    cmp word [input_len], 0
    je .ret
    dec word [input_len]
    mov al, 0x08
    call term_putc
    mov al, ' '
    call term_putc
    mov al, 0x08
    call term_putc
    mov byte [dirty], 1
    ret
.enter:
    mov bx, [input_len]
    mov byte [input_buffer+bx], 0
    mov word [input_len], 0
    call newline
    mov byte [dirty], 1
    jmp execute_command

paint_clear:
    push es
    push ax
    push cx
    push di
    mov ax, PAINT_SEG
    mov es, ax
    xor di, di
    mov cx, PAINT_W*PAINT_H/2
    mov ax, 0x0F0F
    cld
    rep stosw
    pop di
    pop cx
    pop ax
    pop es
    ret

paint_click:                    
    pusha
    mov ax, [clk_x]
    sub ax, [wx]
    sub ax, 2
    mov bx, [clk_y]
    sub bx, [wy]
    sub bx, 14
    cmp ax, 0
    jl .ret
    cmp bx, 13
    jge .canvas
    cmp ax, 176                 
    jge .clr
    mov cl, 11
    div cl
    mov [paint_color], al
    jmp .ret
.clr:
    cmp ax, 180
    jl .ret
    cmp ax, PAINT_W
    jge .ret
    call paint_clear
    jmp .ret
.canvas:
    cmp ax, PAINT_W
    jge .ret
    sub bx, 13
    cmp bx, PAINT_H
    jge .ret
    mov byte [painting], 1
    mov cx, [clk_x]
    mov [last_x], cx
    mov cx, [clk_y]
    mov [last_y], cx
    call paint_plot
.ret:
    popa
    ret

paint_stroke:                   
    pusha
    mov ax, [win_x+2]
    add ax, 2
    mov [ln_ox], ax
    mov ax, [win_y+2]
    add ax, 14+13
    mov [ln_oy], ax
    mov ax, [last_x]
    sub ax, [ln_ox]
    mov [ln_x0], ax
    mov ax, [last_y]
    sub ax, [ln_oy]
    mov [ln_y0], ax
    mov ax, [cur_x]
    sub ax, [ln_ox]
    mov [ln_x1], ax
    mov ax, [cur_y]
    sub ax, [ln_oy]
    mov [ln_y1], ax
    call paint_line
    mov ax, [cur_x]
    mov [last_x], ax
    mov ax, [cur_y]
    mov [last_y], ax
    popa
    ret

paint_line:                     
    pusha
    mov ax, [ln_x1]
    sub ax, [ln_x0]
    mov [ln_dx], ax
    mov ax, [ln_y1]
    sub ax, [ln_y0]
    mov [ln_dy], ax
    mov ax, [ln_dx]
    cwd
    xor ax, dx
    sub ax, dx                  
    mov bx, [ln_dy]
    mov dx, bx
    sar dx, 15
    xor bx, dx
    sub bx, dx                 
    cmp ax, bx
    jae .gotn
    mov ax, bx
.gotn:
    mov [ln_n], ax
    xor si, si
.step:
    cmp word [ln_n], 0
    je .zero
    movsx eax, word [ln_dx]
    movsx edx, si
    imul eax, edx
    cdq
    movsx ebx, word [ln_n]
    idiv ebx
    add ax, [ln_x0]
    mov [pt_x], ax
    movsx eax, word [ln_dy]
    movsx edx, si
    imul eax, edx
    cdq
    movsx ebx, word [ln_n]
    idiv ebx
    add ax, [ln_y0]
    mov bx, ax
    mov ax, [pt_x]
    call paint_plot
    jmp .adv
.zero:
    mov ax, [ln_x0]
    mov bx, [ln_y0]
    call paint_plot
.adv:
    inc si
    cmp si, [ln_n]
    jbe .step
    popa
    ret

paint_plot:                     
    pusha
    push es
    mov [pp_x], ax
    mov [pp_y], bx
    mov ax, PAINT_SEG
    mov es, ax
    xor si, si
.ly:
    xor di, di
.lx:
    mov ax, [pp_x]
    add ax, di
    cmp ax, 0
    jl .skip
    cmp ax, PAINT_W
    jge .skip
    mov bx, [pp_y]
    add bx, si
    cmp bx, 0
    jl .skip
    cmp bx, PAINT_H
    jge .skip
    imul bx, bx, PAINT_W
    add bx, ax
    mov al, [paint_color]
    mov [es:bx], al
.skip:
    inc di
    cmp di, 2
    jb .lx
    inc si
    cmp si, 2
    jb .ly
    pop es
    popa
    ret

render:
    pusha
    push es
    call calc_focus
    mov ax, BB_SEG
    mov es, ax
    call draw_desktop
    call draw_icons
    xor bx, bx                  
.wl:
    xor ax, ax
    mov al, [zorder+bx]
    mov si, ax
    cmp byte [win_vis+si], 0
    je .next
    push bx
    call draw_window
    pop bx
.next:
    inc bx
    cmp bx, NWIN
    jb .wl
    call draw_taskbar
    cmp byte [menu_open], 0
    je .nomenu
    call draw_menu
.nomenu:
    call draw_cursor
    push ds
    mov ax, BB_SEG
    mov ds, ax
    mov ax, VGA_SEG
    mov es, ax
    xor si, si
    xor di, di
    mov cx, 32000
    cld
    rep movsw
    pop ds
    pop es
    popa
    ret

draw_desktop:
    xor di, di
.b:
    mov ax, di
    shl ax, 3
    mov cx, ax
    mov ax, di
    add al, 64
    xor bx, bx
    mov dx, SCR_W
    mov si, 8
    call fill_rect
    inc di
    cmp di, 25
    jb .b
    mov si, str_mark
    mov bx, 207
    mov cx, TASK_Y-11
    mov al, 0
    call draw_text
    mov si, str_mark
    mov bx, 206
    mov cx, TASK_Y-12
    mov al, 11
    call draw_text
    ret

draw_icons:
    pusha
    xor si, si
.l:
    mov ax, si
    mov bx, 44
    mul bx
    add ax, 10
    mov [ic_y], ax
    mov [ic_id], si
    mov al, 15                  
    mov bx, 11
    mov cx, [ic_y]
    dec cx
    mov dx, 30
    mov si, 26
    call fill_rect
    mov si, [ic_id]
    mov al, [icon_col+si]       
    mov bx, 12
    mov cx, [ic_y]
    mov dx, 28
    mov si, 24
    call fill_rect
    mov si, [ic_id]
    cmp si, 1
    je .paint
    mov di, si
    shl di, 1
    mov al, [icon_gcol+si]
    mov bx, 16
    cmp si, 0
    je .gx
    mov bx, 22
.gx:
    mov cx, [ic_y]
    add cx, 8
    mov si, [icon_glyph+di]
    call draw_text
    jmp .label
.paint:
    mov ax, [ic_y]
    add ax, 4
    mov [ic_t], ax
    add ax, 9
    mov [ic_u], ax
    RECT 4, 17, [ic_t], 8, 8
    RECT 14, 27, [ic_t], 8, 8
    RECT 9, 17, [ic_u], 8, 8
    RECT 2, 27, [ic_u], 8, 8
.label:
    mov si, [ic_id]
    mov di, si
    shl di, 1
    mov bx, [icon_lx+di]
    inc bx
    mov cx, [ic_y]
    add cx, 28
    mov si, [icon_label+di]
    mov al, 0
    call draw_text
    mov si, [icon_label+di]
    mov bx, [icon_lx+di]
    mov cx, [ic_y]
    add cx, 27
    mov al, 15
    call draw_text
    mov si, [ic_id]
    inc si
    cmp si, NWIN
    jb .l
    popa
    ret

draw_window:                    
    pusha
    call load_win
    mov bx, [wx]                
    add bx, 2
    mov cx, [wy]
    add cx, 2
    mov dx, [ww]
    mov si, [wh]
    mov al, 8
    call fill_rect
    mov bx, [wx]                
    mov cx, [wy]
    mov al, 0
    call fill_rect
    inc bx                      
    inc cx
    sub dx, 2
    sub si, 2
    mov al, 7
    call fill_rect
    mov al, 15                  
    mov si, 1
    call fill_rect
    mov si, [wh]
    sub si, 2
    mov dx, 1
    mov al, 15
    call fill_rect
    mov al, 8                   
    mov ah, [cur_id]
    cmp ah, [focus_id]
    jne .tc
    mov al, 1
.tc:
    mov bx, [wx]
    add bx, 2
    mov cx, [wy]
    add cx, 2
    mov dx, [ww]
    sub dx, 4
    mov si, 11
    call fill_rect
    xor bx, bx
    mov bl, [cur_id]
    shl bx, 1
    mov si, [win_title+bx]
    mov bx, [wx]
    add bx, 6
    mov cx, [wy]
    add cx, 3
    mov al, 15
    call draw_text
    mov bx, [wx]                
    add bx, [ww]
    sub bx, 14
    mov cx, [wy]
    add cx, 3
    mov dx, 9
    mov si, 9
    mov al, 4
    call fill_rect
    inc bx
    mov al, 'x'
    mov dl, 15
    call draw_char
    mov ax, [wx]
    add ax, 2
    mov [cont_x], ax
    mov ax, [wy]
    add ax, 14
    mov [cont_y], ax
    mov al, [cur_id]
    cmp al, 0
    je .t
    cmp al, 1
    je .p
    call draw_about
    jmp .e
.t:
    call draw_term
    jmp .e
.p:
    call draw_paint
.e:
    popa
    ret

draw_term:
    pusha
    mov bx, [cont_x]
    mov cx, [cont_y]
    mov dx, TERM_COLS*8
    mov si, TERM_ROWS*8
    xor al, al
    call fill_rect
    xor di, di
    mov byte [t_r], 0
.rowl:
    mov byte [t_c], 0
.coll:
    mov al, [term_buf+di]
    cmp al, ' '
    jbe .skip
    xor bx, bx
    mov bl, [t_c]
    shl bx, 3
    add bx, [cont_x]
    xor cx, cx
    mov cl, [t_r]
    shl cx, 3
    add cx, [cont_y]
    mov dl, 10
    call draw_char
.skip:
    inc di
    inc byte [t_c]
    cmp byte [t_c], TERM_COLS
    jb .coll
    inc byte [t_r]
    cmp byte [t_r], TERM_ROWS
    jb .rowl
    cmp byte [focus_id], 0      
    jne .done
    test byte [blink], 1
    jz .done
    xor bx, bx
    mov bl, [term_col]
    shl bx, 3
    add bx, [cont_x]
    xor cx, cx
    mov cl, [term_row]
    shl cx, 3
    add cx, [cont_y]
    mov al, '_'
    mov dl, 10
    call draw_char
.done:
    popa
    ret

draw_paint:
    pusha
    mov ax, [cont_x]
    mov [or_x], ax
    mov ax, [cont_y]
    mov [or_y], ax
    mov byte [pi], 0
.sw:                            
    xor ax, ax
    mov al, [pi]
    mov bl, 11
    mul bl
    mov [pi_x], ax
    mov al, [pi]
    cmp al, [paint_color]
    jne .nosel
    mov bx, [or_x]
    add bx, [pi_x]
    dec bx
    mov cx, [or_y]
    mov dx, 12
    mov si, 12
    mov al, 0
    call fill_rect
.nosel:
    mov bx, [or_x]
    add bx, [pi_x]
    mov cx, [or_y]
    inc cx
    mov dx, 10
    mov si, 10
    mov al, [pi]
    call fill_rect
    inc byte [pi]
    cmp byte [pi], 16
    jb .sw
    RECTO 0, 180, 1, 28, 10     
    RECTO 7, 181, 2, 26, 8
    mov si, str_clr
    mov bx, [or_x]
    add bx, 182
    mov cx, [or_y]
    add cx, 2
    mov al, 0
    call draw_text
    ; blit canvas
    mov ax, [cont_y]
    add ax, 13
    imul di, ax, SCR_W
    add di, [cont_x]
    push ds
    mov ax, PAINT_SEG
    mov ds, ax
    xor si, si
    mov bx, PAINT_H
    cld
.r:
    mov cx, PAINT_W/2
    rep movsw
    add di, SCR_W-PAINT_W
    dec bx
    jnz .r
    pop ds
    popa
    ret

draw_about:
    pusha
    mov ax, [cont_x]
    add ax, 6
    mov [or_x], ax
    mov ax, [cont_y]
    add ax, 8
    mov [or_y], ax
    RECTO 0, 0, 0, 36, 36       
    RECTO 1, 2, 2, 32, 32
    RECTO 14, 6, 4, 24, 2
    RECTO 15, 6, 9, 24, 6
    RECTO 15, 15, 15, 6, 15
    RECTO 12, 6, 30, 24, 2
    mov bx, [cont_x]
    add bx, 50
    mov cx, [cont_y]
    add cx, 8
    mov al, 1
    mov si, ab_l0
    call draw_text
    add cx, 10
    xor al, al
    mov si, ab_l1
    call draw_text
    add cx, 10
    mov si, ab_l2
    call draw_text
    add cx, 10
    mov si, ab_l3
    call draw_text
    add cx, 10
    mov si, ab_l4
    call draw_text
    add cx, 10
    mov si, ab_mouse_ok
    cmp byte [mouse_ok], 0
    jne .mo
    mov si, ab_mouse_no
.mo:
    call draw_text
    add cx, 10
    mov si, ab_up
    call draw_text
    push bx
    push cx
    call get_uptime
    mov di, numbuf
    call put_dec
    mov byte [di], ' '
    mov byte [di+1], 's'
    mov byte [di+2], 0
    pop cx
    pop bx
    add bx, 64
    mov si, numbuf
    xor al, al
    call draw_text
    popa
    ret

draw_taskbar:
    pusha
    RECT 7, 0, TASK_Y, SCR_W, 14
    RECT 15, 0, TASK_Y, SCR_W, 1
    cmp byte [menu_open], 0
    jne .pressed
    RECT 8, 2, TASK_Y+2, 42, 11
    RECT 15, 2, TASK_Y+2, 41, 10
    RECT 7, 3, TASK_Y+3, 39, 9
    jmp .sbt
.pressed:
    RECT 15, 2, TASK_Y+2, 42, 11
    RECT 8, 2, TASK_Y+2, 41, 10
    RECT 7, 4, TASK_Y+4, 38, 8
.sbt:
    mov si, str_start
    mov bx, 7
    mov cx, TASK_Y+4
    mov al, 1
    call draw_text
    xor di, di
.wb:
    cmp byte [win_vis+di], 0
    je .nwb
    mov bx, di
    shl bx, 1
    mov ax, [tb_x+bx]
    mov [or_x], ax
    mov word [or_y], TASK_Y+2
    mov ax, di
    cmp al, [focus_id]
    je .foc
    RECTO 8, 0, 0, 66, 11
    RECTO 15, 0, 0, 65, 10
    RECTO 7, 1, 1, 63, 9
    mov byte [tcol], 0
    jmp .wbt
.foc:
    RECTO 0, 0, 0, 66, 11
    RECTO 8, 1, 1, 64, 9
    mov byte [tcol], 15
.wbt:
    mov bx, di
    shl bx, 1
    mov si, [win_title+bx]
    mov bx, [or_x]
    add bx, 3
    mov cx, TASK_Y+4
    mov al, [tcol]
    call draw_text
.nwb:
    inc di
    cmp di, NWIN
    jb .wb
    mov ah, 2                   
    int 0x1A
    jc .done
    mov al, ch
    shr al, 4
    add al, '0'
    mov [clock_str], al
    mov al, ch
    and al, 0x0F
    add al, '0'
    mov [clock_str+1], al
    mov al, cl
    shr al, 4
    add al, '0'
    mov [clock_str+3], al
    mov al, cl
    and al, 0x0F
    add al, '0'
    mov [clock_str+4], al
    RECT 8, 270, TASK_Y+2, 48, 11
    RECT 7, 271, TASK_Y+3, 46, 9
    mov si, clock_str
    mov bx, 275
    mov cx, TASK_Y+4
    xor al, al
    call draw_text
.done:
    popa
    ret

draw_menu:
    pusha
    RECT 0, 1, MENU_Y, 84, MENU_H
    RECT 7, 2, MENU_Y+1, 82, MENU_H-2
    mov byte [mi], 0
.l:
    xor ax, ax
    mov al, [mi]
    mov bl, 14
    mul bl
    add ax, MENU_Y+2
    mov [mi_y], ax
    mov byte [mi_hot], 0
    mov bx, [m_x]
    cmp bx, 2
    jb .nh
    cmp bx, 83
    jae .nh
    mov bx, [m_y]
    cmp bx, [mi_y]
    jb .nh
    mov cx, [mi_y]
    add cx, 14
    cmp bx, cx
    jae .nh
    mov byte [mi_hot], 1
.nh:
    cmp byte [mi_hot], 0
    je .nobg
    mov al, 1
    mov bx, 3
    mov cx, [mi_y]
    mov dx, 80
    mov si, 14
    call fill_rect
.nobg:
    xor bx, bx
    mov bl, [mi]
    shl bx, 1
    mov si, [menu_ptr+bx]
    xor al, al
    cmp byte [mi], 3
    jne .nr
    mov al, 4                   
.nr:
    cmp byte [mi_hot], 0
    je .tc
    mov al, 15
.tc:
    mov bx, 8
    mov cx, [mi_y]
    add cx, 3
    call draw_text
    inc byte [mi]
    cmp byte [mi], MENU_ITEMS
    jb .l
    popa
    ret

draw_cursor:
    pusha
    mov si, cursor_bmp
    xor di, di
.row:
    xor cx, cx
.col:
    mov al, [si]
    inc si
    cmp al, ' '
    je .next
    mov dx, [m_x]
    add dx, cx
    cmp dx, SCR_W
    jae .next
    mov bx, [m_y]
    add bx, di
    cmp bx, SCR_H
    jae .next
    imul bx, bx, SCR_W
    add bx, dx
    mov ah, 15
    cmp al, 'X'
    jne .w
    xor ah, ah
.w:
    mov [es:bx], ah
.next:
    inc cx
    cmp cx, CUR_W
    jb .col
    inc di
    cmp di, CUR_H
    jb .row
    popa
    ret


term_init:
    call term_clear
    mov si, welcome
    call print
    call newline
    call show_prompt
    ret

term_clear:
    push ax
    push cx
    push di
    mov di, term_buf
    mov cx, TERM_COLS*TERM_ROWS
    xor al, al
    cld
    rep stosb
    mov byte [term_row], 0
    mov byte [term_col], 0
    pop di
    pop cx
    pop ax
    ret

term_putc:                      
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    cmp al, 0x0D
    je .cr
    cmp al, 0x0A
    je .lf
    cmp al, 0x08
    je .bs
    mov bl, al
    mov al, [term_row]
    mov ah, TERM_COLS
    mul ah
    xor cx, cx
    mov cl, [term_col]
    add ax, cx
    add ax, term_buf
    mov di, ax
    mov [di], bl
    inc byte [term_col]
    cmp byte [term_col], TERM_COLS
    jb .done
    mov byte [term_col], 0
    call term_nl
    jmp .done
.cr:
    mov byte [term_col], 0
    jmp .done
.lf:
    call term_nl
    jmp .done
.bs:
    cmp byte [term_col], 0
    je .done
    dec byte [term_col]
.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

term_nl:
    inc byte [term_row]
    cmp byte [term_row], TERM_ROWS
    jb .ret
    mov si, term_buf+TERM_COLS
    mov di, term_buf
    mov cx, TERM_COLS*(TERM_ROWS-1)
    cld
    rep movsb
    mov di, term_buf+TERM_COLS*(TERM_ROWS-1)
    mov cx, TERM_COLS
    xor al, al
    rep stosb
    mov byte [term_row], TERM_ROWS-1
.ret:
    ret

print:                          
    push ax
.l:
    lodsb
    test al, al
    jz .d
    call term_putc
    jmp .l
.d:
    pop ax
    ret

newline:
    push ax
    mov al, 0x0D
    call term_putc
    mov al, 0x0A
    call term_putc
    pop ax
    ret

show_prompt:
    push si
    mov si, prompt_msg
    call print
    pop si
    mov word [input_len], 0
    ret

print_num:                      
    movzx eax, ax
print_num32:                    
    mov ebx, 10
    xor cx, cx
.convert:
    xor edx, edx
    div ebx
    push dx
    inc cx
    test eax, eax
    jnz .convert
.print:
    pop dx
    add dl, '0'
    mov al, dl
    call term_putc
    loop .print
    ret

put_dec:                        
    push bx
    push cx
    push dx
    xor cx, cx
    mov ebx, 10
.c:
    xor edx, edx
    div ebx
    push dx
    inc cx
    test eax, eax
    jnz .c
.p:
    pop dx
    add dl, '0'
    mov [di], dl
    inc di
    loop .p
    pop dx
    pop cx
    pop bx
    ret

print_bcd:                      
    push ax
    shr al, 4
    add al, '0'
    call term_putc
    pop ax
    and al, 0x0F
    add al, '0'
    call term_putc
    ret

get_uptime:                     
    push ds
    mov ax, 0x0040
    mov ds, ax
    mov eax, [0x006C]
    pop ds
    sub eax, [boot_ticks]
    jae .nowrap
    add eax, 0x1800B0           
.nowrap:
    mov ebx, 10
    mul ebx
    mov ebx, 182
    xor edx, edx
    div ebx
    ret

str_eq:
    push si
    push di
.n:
    lodsb
    scasb
    jne .no
    test al, al
    jnz .n
    pop di
    pop si
    mov al, 1
    ret
.no:
    pop di
    pop si
    mov al, 0
    ret

execute_command:
    cmp byte [input_buffer], 0
    je main_loop

    mov si, input_buffer
    mov di, info_cmd
    call str_eq
    cmp al, 1
    je do_info

    mov si, input_buffer
    mov di, ping_cmd
    call str_eq
    cmp al, 1
    je do_ping

    mov si, input_buffer
    mov di, beep_cmd
    call str_eq
    cmp al, 1
    je do_beep

    mov si, input_buffer
    mov di, clear_cmd
    call str_eq
    cmp al, 1
    je do_clear

    mov si, input_buffer
    mov di, math_help_cmd
    call str_eq
    cmp al, 1
    je do_math_help

    mov si, input_buffer
    mov di, reboot_cmd
    call str_eq
    cmp al, 1
    je do_reboot

    mov si, input_buffer
    mov di, uptime_cmd
    call str_eq
    cmp al, 1
    je do_uptime

    mov si, input_buffer
    mov di, mem_cmd
    call str_eq
    cmp al, 1
    je do_mem

    mov si, input_buffer
    mov di, time_cmd
    call str_eq
    cmp al, 1
    je do_time

    mov si, input_buffer
    mov di, paint_cmd
    call str_eq
    cmp al, 1
    je do_paint

    mov si, input_buffer
    mov di, about_cmd
    call str_eq
    cmp al, 1
    je do_about

    mov si, input_buffer
    call try_math
    cmp al, 1
    je main_loop

    mov si, input_buffer
    cmp byte [si], 'e'
    jne .not_echo
    cmp byte [si+1], 'c'
    jne .not_echo
    cmp byte [si+2], 'h'
    jne .not_echo
    cmp byte [si+3], 'o'
    jne .not_echo
    cmp byte [si+4], 0
    je do_echo
    cmp byte [si+4], ' '
    je do_echo

.not_echo:
    mov si, input_buffer
    mov di, help_cmd
    call str_eq
    cmp al, 1
    je do_help

    mov si, input_buffer
    mov di, panic_cmd
    call str_eq
    cmp al, 1
    je do_panic

    mov si, input_buffer
    mov di, crash_cmd
    call str_eq
    cmp al, 1
    je do_crash

    mov si, unknown_msg
    call print
    call newline
    jmp main_loop

main_loop:                      
    call show_prompt
    mov byte [dirty], 1
    jmp gui_loop

do_clear:
    call term_clear
    mov si, welcome
    call print
    call newline
    jmp main_loop

do_reboot:
    cli
    mov al, 0xFE                
    out 0x64, al
    jmp 0xFFFF:0x0000

do_info:
    mov si, info_msg
    call print
    call newline
    jmp main_loop

do_mem:
    mov si, mem_msg
    call print
    mov ax, kernel_size
    call print_num
    mov si, bytes_msg
    call print
    call newline
    jmp main_loop

do_help:
    mov si, help_msg
    call print
    call newline
    jmp main_loop

do_ping:
    mov si, ping_msg
    call print
    call newline
    jmp main_loop

do_beep:
    mov al, 0xB6
    out 0x43, al
    mov ax, 1193
    out 0x42, al
    mov al, ah
    out 0x42, al
    in al, 0x61
    or al, 0x03
    out 0x61, al
    mov cx, 4                   
    call wait_ticks
    in al, 0x61
    and al, 0xFC
    out 0x61, al
    jmp main_loop

do_echo:
    mov si, input_buffer
    add si, 4
.skip_spaces:
    cmp byte [si], ' '
    jne .print
    inc si
    jmp .skip_spaces
.print:
    call print
    call newline
    jmp main_loop

do_time:
    mov ah, 2
    int 0x1A
    jc main_loop
    push dx
    push cx
    mov si, time_msg
    call print
    pop cx
    pop dx
    mov al, ch
    call print_bcd
    mov al, ':'
    call term_putc
    mov al, cl
    call print_bcd
    mov al, ':'
    call term_putc
    mov al, dh
    call print_bcd
    call newline
    jmp main_loop

do_paint:
    mov byte [win_vis+1], 1
    mov al, 1
    call raise_win
    jmp main_loop

do_about:
    mov byte [win_vis+2], 1
    mov al, 2
    call raise_win
    jmp main_loop

do_panic:
    jmp kernel_panic

do_crash:
    xor ax, ax
    xor dx, dx
    div dx                      
divide_error:
    jmp kernel_panic

do_math_help:
    mov si, math_help_msg
    call print
    call newline
    jmp main_loop

do_uptime:
    call get_uptime
    push eax
    mov si, uptime_msg
    call print
    pop eax
    call print_num32
    mov si, seconds_msg
    call print
    call newline
    jmp main_loop

try_math:
    push si
    push bx
    push cx
    push dx

    call parse_number
    jc .not_math

    mov bx, ax
    lodsb

    cmp al, '+'
    je .add
    cmp al, '-'
    je .sub
    cmp al, '*'
    je .mul
    cmp al, '/'
    je .div
    jmp .not_math

.add:
    call parse_number
    jc .not_math
    add bx, ax
    mov ax, bx
    jmp .result
.sub:
    call parse_number
    jc .not_math
    sub bx, ax
    mov ax, bx
    jmp .result
.mul:
    call parse_number
    jc .not_math
    imul bx, ax
    mov ax, bx
    jmp .result
.div:
    call parse_number
    jc .not_math
    cmp ax, 0
    je .divide_zero
    mov cx, ax
    mov ax, bx
    xor dx, dx
    div cx
    jmp .result
.divide_zero:
    mov si, divide_msg
    call print
    call newline
    jmp .success
.result:
    call print_num
    call newline
.success:
    pop dx
    pop cx
    pop bx
    pop si
    mov al, 1
    ret
.not_math:
    pop dx
    pop cx
    pop bx
    pop si
    xor al, al
    ret

parse_number:
    push bx
    xor ax, ax
    xor cx, cx
.parse:
    mov dl, [si]
    cmp dl, '0'
    jb .done
    cmp dl, '9'
    ja .done
    sub dl, '0'
    xor dh, dh
    push dx
    mov bx, 10
    mul bx
    pop dx
    add ax, dx
    inc si
    inc cx
    jmp .parse
.done:
    cmp cx, 0
    je .error
    pop bx
    clc
    ret
.error:
    pop bx
    stc
    ret



kernel_panic:
    cli
    mov ax, KSEG
    mov ds, ax
    mov ax, VGA_SEG
    mov es, ax
    cld
    RECT 4, 0, 0, 320, 200
    RECT 15, 38, 48, 244, 104
    RECT 0, 40, 50, 240, 100
    RECT 15, 40, 50, 240, 12
    mov si, kernel_panic_title
    mov bx, 104
    mov cx, 52
    mov al, 4
    call draw_text
    mov si, kernel_panic_msg
    mov bx, 52
    mov cx, 76
    mov al, 15
    call draw_text
    mov si, kernel_panic_code
    mov bx, 52
    mov cx, 90
    mov al, 14
    call draw_text
    mov si, kernel_panic_stop
    mov bx, 52
    mov cx, 118
    mov al, 12
    call draw_text
.halt:
    cli
    hlt
    jmp .halt

welcome         db "TorbSL v1.3", 0
prompt_msg      db "TorbSL> ", 0
info_cmd        db "info", 0
clear_cmd       db "clear", 0
reboot_cmd      db "reboot", 0
mem_msg         db "Memory: ", 0
bytes_msg       db " B", 0
mem_cmd         db "mem", 0
math_help_cmd   db "math_help", 0
ping_cmd        db "ping", 0
help_cmd        db "help", 0
uptime_cmd      db "uptime", 0
seconds_msg     db " seconds", 0
beep_cmd        db "beep", 0
time_cmd        db "time", 0
paint_cmd       db "paint", 0
about_cmd       db "about", 0
divide_msg      db "Error: division by zero. 0x3", 0
ping_msg        db "Pong!", 0
panic_cmd       db "panic", 0
crash_cmd       db "crash", 0
time_msg        db "Time: ", 0

kernel_panic_title db "KERNEL PANIC", 0
kernel_panic_msg   db "A fatal error has occurred.", 0
kernel_panic_code  db "Error code: 0x2", 0
kernel_panic_stop  db "System halted.", 0

math_help_msg   db "Math: + - * /  e.g. 5+3 (16-bit)", 0
uptime_msg      db "System uptime: ", 0
help_msg        db "Commands: info clear reboot mem help beep echo math_help uptime time paint about", 0
info_msg        db "TorbSL v1.3 (2026-10-09) Desktop 2.0", 0
unknown_msg     db "Unknown command.", 0

str_torbsl      db "TorbSL", 0
str_loading     db "Loading TorbSL Desktop...", 0
str_mark        db "TorbSL Desktop", 0
str_start       db "Torb", 0
str_clr         db "CLR", 0
ab_l0           db "TorbSL Desktop", 0
ab_l1           db "Version 2.0", 0
ab_l2           db "Kernel TorbSL 1.3", 0
ab_l3           db "16-bit real mode", 0
ab_l4           db "VGA 320x200x256", 0
ab_mouse_ok     db "Mouse: PS/2", 0
ab_mouse_no     db "Mouse: not found", 0
ab_up           db "Uptime:", 0
clock_str       db "00:00", 0

title0 db "Terminal", 0
title1 db "Paint", 0
title2 db "About", 0
mn0 db "Terminal", 0
mn1 db "Paint", 0
mn2 db "About", 0
mn3 db "Reboot", 0
gl0 db ">_", 0
gl1 db "", 0
gl2 db "i", 0

win_title   dw title0, title1, title2
menu_ptr    dw mn0, mn1, mn2, mn3
icon_label  dw title0, title1, title2
icon_glyph  dw gl0, gl1, gl2
icon_lx     dw 2, 6, 6
icon_col    db 0, 15, 1
icon_gcol   db 10, 0, 15
tb_x        dw 48, 118, 188

win_x       dw 72, 60, 90
win_y       dw 8, 24, 40
win_w       dw 228, 212, 200
win_h       dw 112, 129, 96
win_vis     db 1, 0, 0
zorder      db 2, 1, 0
ztmp        db 0, 0, 0

12x13 mouse pointer: X = black outline, . = white fill
cursor_bmp:
    db "X           "
    db "XX          "
    db "X.X         "
    db "X..X        "
    db "X...X       "
    db "X....X      "
    db "X.....X     "
    db "X......X    "
    db "X...XXXXX   "
    db "X.X..X      "
    db "XX X..X     "
    db "X   X..X    "
    db "     XX     "

; ---- variables ----
dirty       db 0
blink       db 0
last_tick   dw 0
boot_ticks  dd 0
mouse_ok    db 0
m_x         dw 160
m_y         dw 100
m_btn       db 0
m_dirty     db 0
m_click     db 0
m_clx       dw 0
m_cly       dw 0
cur_x       dw 0
cur_y       dw 0
cur_btn     db 0
dragging    db 0
drag_id     db 0
drag_dx     dw 0
drag_dy     dw 0
painting    db 0
paint_color db 0
last_x      dw 0
last_y      dw 0
menu_open   db 0
focus_id    db 0
cur_id      db 0
wx          dw 0
wy          dw 0
ww          dw 0
wh          dw 0
cont_x      dw 0
cont_y      dw 0
clk_x       dw 0
clk_y       dw 0
or_x        dw 0
or_y        dw 0
ic_y        dw 0
ic_id       dw 0
ic_t        dw 0
ic_u        dw 0
t_r         db 0
t_c         db 0
tcol        db 0
mi          db 0
mi_y        dw 0
mi_hot      db 0
pi          db 0
pi_x        dw 0
term_row    db 0
term_col    db 0
input_len   dw 0
bigscale    dw 1
bt_col      db 0
bt_x        dw 0
bt_y        dw 0
bt_gl       dw 0
bt_bits     db 0
bt_ci       dw 0
ln_ox       dw 0
ln_oy       dw 0
ln_x0       dw 0
ln_y0       dw 0
ln_x1       dw 0
ln_y1       dw 0
ln_dx       dw 0
ln_dy       dw 0
ln_n        dw 0
pt_x        dw 0
pp_x        dw 0
pp_y        dw 0
numbuf      times 16 db 0
input_buffer times INPUT_MAX + 2 db 0
term_buf    times TERM_COLS*TERM_ROWS db 0
font_buf    times 1024 db 0

kernel_end:
kernel_size equ kernel_end