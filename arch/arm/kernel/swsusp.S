/*
 * Hibernation support specific for ARM
 *
 * Based on work by:
 *
 * Ubuntu project, hibernation support for mach-dove,
 * https://lkml.org/lkml/2010/6/18/4
 *
 * Copyright (C) 2010 Nokia Corporation
 * Contact: Hiroshi DOYU < Hiroshi.DOYU at nokia.com >
 * https://lists.linux-foundation.org/pipermail/linux-pm/2010-June/027422.html
 *
 * Copyright (C) 2010 Texas Instruments, Inc.
 * via linux-omap mailing list, Teerth Reddy et al.
 * https://patchwork.kernel.org/patch/96442/
 *
 * Copyright (C) 2006 Rafael J. Wysocki < rjw at sisk.pl >
 *
 * License terms: GNU General Public License (GPL) version 2
 */

#include <linux/linkage.h>
#include <asm/assembler.h>
#include <asm/cache.h>
#include <asm/memory.h>
#include <asm/page.h>
#include <asm/ptrace.h>


#define KERNEL_RAM_PADDR	(PHYS_OFFSET + TEXT_OFFSET)
#define SWAPPER_PG_DIR		(KERNEL_RAM_PADDR - 0x4000)


/*
 * Force ARM mode because:
 * - we use PC-relative addressing with >8bit offsets
 * - we use msr with immediates
 */
.arm

.align PAGE_SHIFT
.Lswsusp_page_start:

/*
 * Save the current CPU state before suspend / poweroff.
 */
ENTRY(swsusp_arch_suspend)
	adr r0, ctx
	mrs r1, cpsr
	stm r0!, {r1} /* current CPSR */
	msr cpsr_c, #SYSTEM_MODE
	stm r0!, {r0-r14} /* user regs */
	msr cpsr_c, #SVC_MODE
	mrs r2, spsr
	stm r0!, {r2, sp, lr} /* SVC SPSR, SVC regs */
	msr cpsr, r1 /* restore original mode */

	stmfd sp!, {lr}
	bl swsusp_cpu_save
	ldmfd sp!, {lr}
	b swsusp_save
ENDPROC(swsusp_arch_suspend)


/*
 * Restore the memory image from the pagelists, and load the CPU registers
 * from saved state.
 * This runs in a very restrictive context - namely, no stack can be used
 * before the CPU register state saved by swsusp_arch_suspend() has been
 * restored.
 */
ENTRY(swsusp_arch_resume)
	ldr r0, =SWAPPER_PG_DIR
	mcr p15, 0, r0, c2, c0, 0 /* load page table pointer */
	mcr p15, 0, r0, c8, c7, 0 /* invalidate I,D TLBs */
	mcr p15, 0, r0, c7, c5, 4 /* ISB */

 /*
 * The following code is an assembly version of:
 *
 * struct pbe *pbe;
 * for (pbe = restore_pblist; pbe != NULL; pbe = pbe->next)
 * copy_page(pbe->orig_address, pbe->address);
 *
 * Because this is the very place where data pages, including our stack,
 * are overwritten, function calls are obviously impossible.  Hence asm.
 *
 * The core of the loop is taken almost verbatim from copy_page.S.
 */
	ldr r1, =(restore_pblist - 8) /* "fake" pbe->next */
	b 3f
.align L1_CACHE_SHIFT
0:
PLD( pld [r0, #0] )
PLD( pld [r0, #L1_CACHE_BYTES] )
	mov r3, #(PAGE_SIZE / (2 * L1_CACHE_BYTES) PLD( -1 ))
	ldmia r0!, {r4-r7}
1:
PLD( pld [r0, #(2 * L1_CACHE_BYTES)] )
PLD( pld [r0, #(3 * L1_CACHE_BYTES)] )
2:
.rept (2 * L1_CACHE_BYTES / 16 - 1)
	stmia r2!, {r4-r7}
	ldmia r0!, {r4-r7}
.endr
	subs r3, r3, #1
	stmia r2!, {r4-r7}
	ldmgtia r0!, {r4-r7}
	bgt 1b
PLD( ldmeqia r0!, {r4-r7} )
PLD( beq 2b )
3:
	ldr r1, [r1, #8] /* load next in list (pbe->next) */
	cmp r1, #0
	ldrne r0, [r1] /* src page start address (pbe->address) */
	ldrne r2, [r1, #4] /* dst page start address (pbe->orig_address) */
	bne 0b
	
/*
 * Done - now restore the CPU state and return.
 */
	msr cpsr_c, #SYSTEM_MODE
	adr r0, ctx
	ldm r0!, {r1, sp, lr} /* first word is CPSR, following are r0/r1 (irrelevant) */
	msr cpsr_cxsf, r1
	ldm r0!, {r2-r14}
	msr cpsr_c, #SVC_MODE
	ldm r0!, {r2, sp, lr}
	msr spsr_cxsf, r2
	msr cpsr_c, r1 /* use CPSR from above */
	
	mov r1, #0
	stmfd sp!, {r1,lr}
	bl swsusp_cpu_restore /* restore CP state, flush TLB */
	ldmfd sp!, {r0,pc}
ENDPROC(swsusp_arch_resume)

.ltorg

/*
 * Save the CPU context (register set for all modes and mach-specific cp regs)
 * here.  Setting aside what remains of this CPU page, should be aplenty.
 */
.align L1_CACHE_SHIFT
ENTRY(ctx)
.space (PAGE_SIZE - (. - .Lswsusp_page_start))
END(ctx)
