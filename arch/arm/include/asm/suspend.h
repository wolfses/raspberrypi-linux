#ifndef __ASM_ARM_SUSPEND_H
#define __ASM_ARM_SUSPEND_H

extern void cpu_resume(void);
extern int cpu_suspend(unsigned long, int (*)(unsigned long));

static inline int arch_prepare_suspend(void) { return 0; }
/*
 * On ARM, we'd ultimately prefer to have these "static" so that they
 * completely disappear from the code.  All necessary state save / restore
 * is done from within swsusp_arch_suspend / swsusp_arch_resume.
 * These functions have no other purpose than to get the preempt count right.
 *
 * swsusp generics force existance of the symbols though, so at least mandate
 * inlining for good.
 */
__inline__ void notrace save_processor_state(void) { preempt_disable(); }
__inline__ void notrace restore_processor_state(void) { preempt_enable(); }

#endif
