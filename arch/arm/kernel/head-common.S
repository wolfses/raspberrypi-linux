/*
 *  linux/arch/arm/kernel/head-common.S
 *
 *  Copyright (C) 1994-2002 Russell King
 *  Copyright (c) 2003 ARM Limited
 *  All Rights Reserved
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 */

#define ATAG_CORE 0x54410001
#define ATAG_CORE_SIZE ((2*4 + 3*4) >> 2)
#define ATAG_CORE_SIZE_EMPTY ((2*4) >> 2)

#ifdef CONFIG_CPU_BIG_ENDIAN
#define OF_DT_MAGIC 0xd00dfeed
#else
#define OF_DT_MAGIC 0xedfe0dd0 /* 0xd00dfeed in big-endian */
#endif

/*
 * Exception handling.  Something went wrong and we can't proceed.  We
 * ought to tell the user, but since we don't have any guarantee that
 * we're even running on the right architecture, we do virtually nothing.
 *
 * If CONFIG_DEBUG_LL is set we try to print out something about the error
 * and hope for the best (useful if bootloader fails to pass a proper
 * machine ID for example).
 */
	__HEAD

/* Determine validity of the r2 atags pointer.
 * atags pointer의 유효성을 판단
 * The heuristic requires that the pointer be aligned, in the first 16k of physical RAM
 * 휴리스틱은 물리적인 램의 첫 16k에서 포인터가 정렬되어 있기를 요구한다.
 * and that the ATAG_CORE marker is first and present.
 * 그리고 ATAG_CORE marker가 포인터의 처음에 존재하길 요구한다.
 * Future revisions of this function may be more lenient with the physical address and
 * 이 함수의 추후의 개정은 물리적인 메모리에 좀 더 유연해지고
 * may also be able to move the ATAGS block if necessary.
 * 필요하면 ATAGS 블럭을 이동할 수 있을 것이다.
 * r8  = machinfo
 *
 * Returns:
 *  r2 either valid atags pointer, or zero
 *  r5, r6 corrupted
 */

/*커널 부팅시 넘어온 atags 정보를 검사한다.
 * ATAG_CORE = 0x54410001 ATAG_CORE_SIZE = ((2*4 + 3*4) >> 2)
 * atags 헤더의 두 멤버를 의미한다.
 * 결국 두 멤버를 위의 값과 비교해 동일할 경우 정상이라 판단하고 리턴한다.
 * 아닐 경우 r2에 0을 넣어준다.*/
__vet_atags:
	tst	r2, #0x3			@ aligned?,4byte단위로 정렬되어있는지 검사
						@ ## TST 비트 단위 검사
						@ ## CPSR flags := Rn AND Op2
	bne	1f				@ ## align이 되어 있으면(r2하위 2비트
						@ ## 가 00이라면), Zflag 1
						@ ## 즉, align 안되어 있으면,
						@ ## 1 label forward로 점프한다.

	ldr	r5, [r2, #0]			@ is first tag ATAG_CORE?
#ifdef CONFIG_OF_FLATTREE
	ldr	r6, =OF_DT_MAGIC		@ is it a DTB?
	cmp	r5, r6
	beq	2f
#endif
	cmp	r5, #ATAG_CORE_SIZE		@ is first tag ATAG_CORE?
	cmpne	r5, #ATAG_CORE_SIZE_EMPTY	@ ATAG_CORE_SIZE와 header의 size값을 비교
	bne	1f				@다르다면 forward label 1로 점프
	ldr	r5, [r2, #4]			@atag의 다음 멤버의 값을 r5에 저장,tag임
	ldr	r6, =ATAG_CORE
	cmp	r5, r6				@ATAG_CORE와 tag를 비교
	bne	1f

2:	mov	pc, lr				@ atag/dtb pointer is ok

1:	mov	r2, #0				@ ## atag 정보가 넘어온값과 다를 경우, 이 경우는 오류
	mov	pc, lr
ENDPROC(__vet_atags)

/*
 * The following fragment of code is executed with the MMU on in MMU mode,
 * and uses absolute addresses; this is not position independent.
 *
 *  r0  = cp#15 control register
 *  r1  = machine ID
 *  r2  = atags/dtb pointer
 *  r9  = processor ID
 */
////////////////////////////////////////////////////////////////
/* head.S의 turn_mmu_on에서 넘어옴
 * C 함수를 호출하기 전 C 함수 호출이 가능하도록
 * 스택이나 BSS 와 같은 메모리 구조들을 정리
 * 최종적으로 호출하는 것은 init/main.c파일의 start_kernel()  */
////////////////////////////////////////////////////////////////
	__INIT
__mmap_switched:
	adr	r3, __mmap_switched_data

	ldmia	r3!, {r4, r5, r6, r7}
						/* r4 = __data_loc
						 * r5 = _data
						 * r6 = __bss_start
						 * r7 = _end
						 * r3는 processor_id로 업데이트
						 */
	cmp	r4, r5				@ Copy data segment if needed
1:	cmpne	r5, r6				// 위에서 두개가 같지 않을 경우 __data_loc의 데이터를 _data에 복사한다
	ldrne	fp, [r4], #4
	strne	fp, [r5], #4
	bne	1b

						// bss를 0로 클리어
	mov	fp, #0				@ Clear BSS (and zero fp)
1:	cmp	r6, r7
	strcc	fp, [r6],#4
	bcc	1b

 ARM(	ldmia	r3, {r4, r5, r6, r7, sp})
 THUMB(	ldmia	r3, {r4, r5, r6, r7}	)
 THUMB(	ldr	sp, [r3, #16]		)
	str	r9, [r4]			@ Save processor ID
	str	r1, [r5]			@ Save machine type
	str	r2, [r6]			@ Save atags pointer
	bic	r4, r0, #CR_A			@ Clear 'A' bit
						/* \arch\arm\include\asm\system.h에 CR_A는 (1 << 1)로 정의되어 있다
						 * alignment fault checking On
						 * cr_alignment에 이것을 저장
						 */
	stmia	r7, {r0, r4}			@ Save control register values
						// r0, r4를 r7이 가리키는 곳에 차례대로 넣는다.
						// r0 =  cp#15 control register에 설정한 값
						// r1 = machine type
						// r2 = atags pointer
						// r3 = __create_page_table에서 0x50004C1E에서 시작해 1메가씩 증가된 값
						// r4 =

						//r7는 cr_alignment의 주소를 가리키고 있음
						//이곳에 r0의 값을 넣은 다음 4만큼 주소가 증가되고
						//cr_no_alignment를 가리킨다. 이곳에 r4가 들어가는것이다
						//arch/arm/kernel/entry-armv.S 참고
	b	start_kernel
ENDPROC(__mmap_switched)

	.align	2
	.type	__mmap_switched_data, %object
__mmap_switched_data:
	.long	__data_loc			@ r4
	.long	_sdata				@ r5
	.long	__bss_start			@ r6
	.long	_end				@ r7
	.long	processor_id			@ r4
	.long	__machine_arch_type		@ r5
	.long	__atags_pointer			@ r6
	.long	cr_alignment			@ r7
	.long	init_thread_union + THREAD_START_SP @ sp
	.size	__mmap_switched_data, . - __mmap_switched_data

/*
 * This provides a C-API version of __lookup_processor_type
 */
ENTRY(lookup_processor_type)
	stmfd	sp!, {r4 - r6, r9, lr}
	mov	r9, r0
	bl	__lookup_processor_type
	mov	r0, r5
	ldmfd	sp!, {r4 - r6, r9, pc}
ENDPROC(lookup_processor_type)

/*
 * Read processor ID register (CP#15, CR0), and look up in the linker-built
 * supported processor list.  Note that we can't use the absolute addresses
 * for the __proc_info lists since we aren't running with the MMU on
 * (and therefore, we are not in the correct address space).  We have to
 * calculate the offset.
 *
 *	r9 = cpuid
 * Returns:
 *	r3, r4, r6 corrupted
 *	r5 = proc_info pointer in physical address space
 *	r9 = cpuid (preserved)
 */
	__CPUINIT
__lookup_processor_type:
	adr	r3, __lookup_processor_type_data	@ ## __lookup_processor_type_data의 주소값을 r3 저장한다.
	ldmia	r3, {r4 - r6}				@ multiple load decreament after
							@ ## =========================================
							@ ## <상식>
							@ ## ARM에는 어드레스를 자동으로 increment하는
							@ ## 로직은 있지만 decrement하는 것은 없다.
							@ ## 따라서, decrement 동작은 먼저 ALU를 이용
							@ ## 하여, 어드레스를 계산한 후 어드레스를 증가
							@ ## 하면서 데이터를 읽거나 쓴다.
							@ ## 따라서, 모든 decrement 동작은,어드레스를
							@ ## 레지스터 리스트만큼 ALU를 이용해서 감소해
							@ ## 놓고, 어드레스를 증가하면서 데이터 저장
							@ ## =========================================
							@ ## r3에는 __lookup_processor_type_data의의 주소값이 있으므로,
							@ ## r5 = __proc_info_begin
							@ ## r6 = __proc_info_end
							@ ## r7 = .
							@ ## 이 저장된다.
/* r3은 물리주소, r7은 가상주소
 * 가상메모리와 물리메모리의 차를 이용해 proc_info_begin과 end의 물리주소를 구한다.
 * mmu가 아직 작동되지 않으므로 구해진 물리주소를 통해 begin과 end에 접근한다.
 */
	sub	r3, r3, r4			@ get offset between virt&phys
	add	r5, r5, r3			@ convert virt addresses to
	add	r6, r6, r3			@ physical address space
 /* ## < 참고자료 : struct proc_info_list >
  * Note!  struct processor is always defined if we're using MULTI_CPU, otherwise this entry is unused,
  * but still exists.
  *
  * NOTE! The following structure is defined by assembly language, NOT C code.  For more information, check:
  *  arch/arm/mm/proc-*.S and arch/arm/kernel/head.S
  *  struct proc_info_list {
  *  unsigned int        cpu_val;                        ## cpu_val == processer ID
  *  unsigned int        cpu_mask;
  *  unsigned long       __cpu_mm_mmu_flags; used by head.S
  *  unsigned long       __cpu_io_mmu_flags; used by head.S
  *  unsigned long       __cpu_flush;        used by head.S
  *  const char      *arch_name;
  *  const char      *elf_name;
  *  unsigned int        elf_hwcap;
  *  const char      *cpu_name;
  *  struct processor    *proc;
  *  struct cpu_tlb_fns  *tlb;
  *  struct cpu_user_fns *user;
  *  struct cpu_cache_fns    *cache;
  * };
  */
 /* ## 이하 서브루틴은, proc.info.init 섹션에 모여있는 모든 아키텍처의
  * ## proc_info_list 구조체의 리스트속에서, 현재 프로세서에 맞는 구조체를
  * ## 검색하는 루틴이다.
  */
1:	ldmia	r5, {r3, r4}			@ value, mask
						@ ## cpu value,cpu mask
						@ ## r5 = cpu_val의 값은 결국 ,
						@ ## processor ID 이다.
						@ ## r5는 각 프로세서의
						@ ## struct proc_info_list의 첫번째
						@ ## 멤버를 가르킨다.
	and	r4, r4, r9			@ mask wanted bits
						@ ## r4 = cpu mask
						@ ## r9 = 현재 프로세서의 processor ID
	teq	r3, r4				@ ## proc.info.init 섹션 리스트에서
	beq	2f				@ ## 현 프로세서에 대한 정보를 찾을 까지
						@ ## 계속 루프를 돈다.
						@ ## 해당 프로세서를 proc.info.init  리스트에서 찾았을 경우
						@ ## 바로 label 2로 점프
	add	r5, r5, #PROC_INFO_SZ		@ sizeof(proc_info_list)
						@ ## 각 프로세서의 proc_info 사이즈
						@ ## r5에는 발견된 현 프로세서의
						@ ## proc_info_list 구조체의 마지막 주소가
						@ ## 저장된다.
	cmp	r5, r6				@ ## r5 = 발견된 proc_info_list의 마지막주소
						@ ## r6 = proc.info.init section list의 마지막 주소
	blo	1b				@ ## branch if than lower
	mov	r5, #0				@ unknown processor
						@ ## 해당 프로세서를 proc.info.init 리스트에서
						@ ## 못 찾았을 경우는, r5 에 0값을 넣고 복귀한다.
2:	mov	pc, lr
ENDPROC(__lookup_processor_type)		@ ## ENDPROC은 /include/linux/linkage.h에
						@ ## 정의되어 있다.
						@ ## ENDPROC()을 사용함으로 써,label을
						@ ## 심볼테이블에 "함수"로써 등록한다.

/*
 * Look in <asm/procinfo.h> for information about the __proc_info structure.
 */
	.align	2
	.type	__lookup_processor_type_data, %object
__lookup_processor_type_data:
	.long	.
	.long	__proc_info_begin		@ ## .proc.info.init section list 영역의
						@ ## 시작주소(vmlinux.lds.S 참조)
	.long	__proc_info_end			@ ## .proc.info.init section list 영역의
						@ ## 끝 주소(vmlinux.lds.S 참조)
	.size	__lookup_processor_type_data, . - __lookup_processor_type_data

__error_p:
#ifdef CONFIG_DEBUG_LL
	adr	r0, str_p1
	bl	printascii
	mov	r0, r9
	bl	printhex8
	adr	r0, str_p2
	bl	printascii
	b	__error
str_p1:	.asciz	"\nError: unrecognized/unsupported processor variant (0x"
str_p2:	.asciz	").\n"
	.align
#endif
ENDPROC(__error_p)

__error:
#ifdef CONFIG_ARCH_RPC
/*
 * Turn the screen red on a error - RiscPC only.
 */
	mov	r0, #0x02000000
	mov	r3, #0x11
	orr	r3, r3, r3, lsl #8
	orr	r3, r3, r3, lsl #16
	str	r3, [r0], #4
	str	r3, [r0], #4
	str	r3, [r0], #4
	str	r3, [r0], #4
#endif
1:	mov	r0, r0
	b	1b
ENDPROC(__error)
