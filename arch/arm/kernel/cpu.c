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

#include <linux/module.h>
#include <linux/mm.h>
#include <asm/ptrace.h>
#include <asm/tlbflush.h>
#include <linux/stringify.h>


/*
 * Helper macros for machine-specific code to create ARM coprocessor
 * state save/load operations.
 *
 * Used in <mach/hibernate.h> to save/restore processor specific state.
 *
 * Note: Some versions of gcc's inline assembler create incorrect code
 * (ldr / str instructions to transfer src/tgt into the register given
 * to mrc/mcr are missing); it's a good idea to disassemble cpu.o to
 * validate that the mrc/mcr is always paired with a str/ldr instruction.
 * If that's not the case, a "+r"() constraint might help, at the cost
 * of an unnecessary load/store.
 */

#define SAVE_CPREG(p, op1, cr1, cr2, op2, tgt) \
 "mrc " __stringify(p, op1, %0, cr1, cr2, op2) : "=r"(tgt) : : "memory", "cc"

#define LOAD_CPREG(p, op1, cr1, cr2, op2, src) \
 "mcr " __stringify(p, op1, %0, cr1, cr2, op2) : : "r"(src) : "memory", "cc"


/*
 * declares "struct saved_context" for mach-specific registers. 
 */
#include <mach/hibernate.h>

/* References to section boundaries */
extern const void __nosave_begin, __nosave_end;


/*
 * pfn_is_nosave - check if given pfn is in the 'nosave' section
 */
notrace int pfn_is_nosave(unsigned long pfn)
{
 unsigned long nosave_begin_pfn = __pa_symbol(&__nosave_begin) >> PAGE_SHIFT;
 unsigned long nosave_end_pfn = PAGE_ALIGN(__pa_symbol(&__nosave_end)) >> PAGE_SHIFT;

 return (pfn >= nosave_begin_pfn) && (pfn < nosave_end_pfn);
}

/*
 * The ARM suspend code calls these to save/restore machine-specific
 * registers.  These might be highly architecture- and even SoC-specific.
 *
 * All architectures supporting swsusp need to implement their own
 * versions of __save/__restore_processor_state().
 *
 * FIXME: Once there is a generic interface to save/restore processor
 * state, it should simply be hooked here.
 */

notrace void swsusp_cpu_save(struct saved_context *ctx)
{
 __save_processor_state(ctx);
}

notrace void swsusp_cpu_restore(struct saved_context *ctx)
{
 __restore_processor_state(ctx);
 local_flush_tlb_all(); /* only on this CPU ?  */
}
