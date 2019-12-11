	bits 16
	org 100h
	
	SB_BASE equ 220h
	SB_IRQ equ 7
	SB_DMA equ 1
	INT_NUMBER equ 0fh
	SOUND_SIZE equ 10986
	
segment code

	start:
			call reset_dsp
			; call print_dsp_version
			call turn_speaker_on
			call install_isr
			call enable_irq_7
			call calculate_sound_buffer_page_offset
			call fill_sound_buffer
			call program_dma
			call set_16KHz_out_sampling_rate
			
			call start_playback
			
			; wait for keypress
			mov ah, 0
			int 16h
			
	exit:
			call disable_irq_7
			call uninstall_isr
			call turn_speaker_off
			mov ax, 4c00h
			int 21h
	
	; in: al = value
	print_al:
			pusha
			mov bx, ax
			mov cl, 4
		.next_digit:
			mov ax, bx
			shr ax, cl
			and al, 0fh
			cmp al, 09h
			ja .above
		.less_equal:
			add al, '0'
			jmp short .continue
		.above:	
			add al, ('A' - 10)
		.continue:	
			mov ah, 0eh
			int 10h
			sub cl, 4
			jnc .next_digit
			popa
			ret
			
	reset_dsp:
			mov dx, SB_BASE
			add dl, 6
			
			mov al, 1
			out dx, al
			sub al, al
		.delay:
			dec al
			jnz .delay
			out dx, al
			
			sub cx, cx
		.empty:
			mov dx, SB_BASE
			add dl, 0eh
			
			in al, dx
			or al, al
			jns .next_attempt
			
			sub dl, 4
			in al, dx
			cmp al, 0aah
			je .reset_ok
			
		.next_attempt:	
			loop .empty
			
		.reset_ok:
			; call print_al
			ret

	; bl = data
	write_dsp:
			mov dx, SB_BASE
			add dl, 0ch
		.busy:
			in al, dx
			or al, al
			js .busy
			
			mov al, bl
			out dx, al
			ret
			
	; out: al 		
	read_dsp:
			mov dx, SB_BASE
			add dl, 0eh
		.busy:
			in al, dx
			or al, al
			jns .busy
			
			sub dl, 4
			in al, dx
			ret
			
	print_dsp_version:
			mov bl, 0e1h
			call write_dsp
			call read_dsp
			call print_al
			mov ah, 0eh
			mov al, '.'
			int 10h
			call read_dsp
			call print_al
			ret
			
	turn_speaker_on:
			mov bl, 0d1h
			call write_dsp
			ret
			
	turn_speaker_off:
			mov bl, 0d3h
			call write_dsp
			ret
			
	disable_irq_7:
			in al, 21h
			or al, 10000000b
			out 21h, al
			ret
			
	enable_irq_7:
			in al, 21h
			and al, 01111111b
			out 21h, al
			ret
			
	irq_7_handler:
			pusha
			
			; print 'X'
			mov ah, 0eh
			mov al, 'X'
			int 10h
			
			; SB 8-bit ack
			mov dx, SB_BASE + 0eh
			in al, dx
			
			; EOI
			mov al, 20h
			out 20h, al
			
			popa
			iret
			
	install_isr:		
			cli
			mov ax, 0
			mov es, ax
			mov ax, [es:4 * INT_NUMBER]
			mov [old_int_offset], ax
			mov ax, [es:4 * INT_NUMBER + 2]
			mov [old_int_seg], ax
			mov word [es:4 * INT_NUMBER], irq_7_handler
			mov word [es:4 * INT_NUMBER + 2], cs
			sti
			ret
			
	uninstall_isr:
			cli
			mov ax, 0
			mov es, ax
			mov ax, [old_int_offset]
			mov [es:4 * INT_NUMBER], ax
			mov ax, [old_int_seg]
			mov [es:4 * INT_NUMBER + 2], ax
			sti
			ret
	
	calculate_sound_buffer_page_offset:
			mov ax, cs
			mov dx, ax
			shr dx, 12
			shl ax, 4
			add ax, sound_buffer
			jnc .continue
			inc dx
		.continue:
			mov cx, 0ffffh
			sub cx, ax
			inc cx 
			cmp cx, SOUND_SIZE
			jae .size_ok
		.use_next_page:
			mov ax, 0
			inc dx
		.size_ok:
			mov word [dma_page], dx
			mov word [dma_offset], ax
			ret

	fill_sound_buffer:
			mov ax, [dma_page]
			shl ax, 12
			mov es, ax
			mov di, [dma_offset]

			mov si, sound_data
			mov cx, SOUND_SIZE
			rep movsb
			ret
			
	program_dma:
			mov dx, 0ah ; write single mask register
			mov al, 05h ; disable DMA channel 1
			out dx, al
			
			mov dx, 0ch ; clear byte pointer flip flop
			mov al, 0 ; any value
			out dx, al 
			
			mov dx, 0bh ; write mode register
			mov al, 49h ; single-cycle playback
			out dx, al
			
			mov dx, 03h ; channel 1 count
			mov al, (SOUND_SIZE - 1) & 0ffh
			out dx, al ; low byte
			mov al, (SOUND_SIZE - 1) >> 8
			out dx, al ; high byte
			
			mov dx, 02h ; channel 1 address
			mov al, [dma_offset]
			out dx, al ; low byte
			mov al, [dma_offset + 1]
			out dx, al ; high byte
			
			mov dx, 83h ; page register for 8-bit DMA channel 1
			mov al, [dma_page]
			out dx, al
			
			mov dx, 0ah ; write single mask register
			mov al, 01h ; enable DMA channel 1
			out dx, al
			
			ret

	set_16KHz_out_sampling_rate:
			mov bl, 40h ; time constant
			call write_dsp
			mov bl, 0c1h ; 16KHz
			call write_dsp
			ret
			
	start_playback:
			mov bl, 14h ; 8-bit 'Single-cycle' PCM output
			call write_dsp
			mov bl, (SOUND_SIZE - 1) & 0ffh ; low byte
			call write_dsp
			mov bl, (SOUND_SIZE - 1) >> 8 ; high byte
			call write_dsp
			ret
			
segment data
	
	dma_page dw 0
	dma_offset dw 0

	old_int_offset dw 0
	old_int_seg dw 0
	
	sound_data:
		incbin "yattane.raw"
		
	sound_buffer:		
		times SOUND_SIZE * 2 db 0	
			
			
			
			
			
			
			
			
			
			
			
			
			
			
			
			
			
			













