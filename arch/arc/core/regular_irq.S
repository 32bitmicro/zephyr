/*
 * Copyright (c) 2014 Wind River Systems, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * @file
 * @brief Handling of transitions to-and-from regular IRQs (RIRQ)
 *
 * This module implements the code for handling entry to and exit from regular
 * IRQs.
 *
 * See isr_wrapper.S for details.
 */

#define _ASMLANGUAGE

#include <nano_private.h>
#include <offsets.h>
#include <toolchain.h>
#include <arch/cpu.h>
#include "swap_macros.h"

GTEXT(_rirq_enter)
GTEXT(_rirq_exit)

/**
 *
 * @brief Work to be done before handing control to an IRQ ISR
 *
 * The processor pushes automatically all registers that need to be saved.
 * However, since the processor always runs at kernel privilege there is no
 * automatic switch to the IRQ stack: this must be done in software.
 *
 * Assumption by _isr_demux: r3 is untouched by _rirq_enter.
 *
 * @return N/A
 */

SECTION_FUNC(TEXT, _rirq_enter)

	mov r1, _nanokernel
#ifdef CONFIG_ARC_STACK_CHECKING
	/* disable stack checking */
	lr r2, [_ARC_V2_STATUS32]
	bclr r2, r2, _ARC_V2_STATUS32_SC_BIT
	kflag r2
#endif
	ld_s r2, [r1, __tNANO_current_OFFSET]
#if CONFIG_NUM_REGULAR_IRQ_PRIO_LEVELS == 1
	st sp, [r2, __tTCS_preempReg_OFFSET + __tPreempt_sp_OFFSET]
	ld sp, [r1, __tNANO_rirq_sp_OFFSET]
#else
#error regular irq nesting is not implemented
#endif
	j _isr_demux


/**
 *
 * @brief Work to be done exiting an IRQ
 *
 * @return N/A
 */

SECTION_FUNC(TEXT, _rirq_exit)

	mov r1, _nanokernel
	ld_s r2, [r1, __tNANO_current_OFFSET]

#if CONFIG_NUM_REGULAR_IRQ_PRIO_LEVELS > 1
	/* check if we're a nested interrupt: if so, let the interrupted interrupt
	 * handle the reschedule */

	lr r3, [_ARC_V2_AUX_IRQ_ACT]
	ffs r0, r3

	asl r0, 1, r0

	/* the OS on ARCv2 always runs in kernel mode, so assume bit31 [U] in
	 * AUX_IRQ_ACT is always 0: if the contents of AUX_IRQ_ACT is greater
	 * than FFS(AUX_IRQ_ACT), it means that another bit is set so an
	 * interrupt was interrupted.
	 */

	cmp r0, r3
	brgt.nd _rirq_return_from_rirq
	ld sp, [r2, __tTCS_preempReg_OFFSET + __tPreempt_sp_OFFSET]
#endif

	/*
	 * Both (a)reschedule and (b)non-reschedule cases need to load the current
	 * thread's stack, but don't have to use it until the decision is taken:
	 * load the delay slots with the 'load stack pointer' instruction.
	 *
	 * a) needs to load it to save outgoing context.
	 * b) needs to load it to restore the interrupted context.
	 */

	ld_s r0, [r2, __tTCS_flags_OFFSET]
	and.f r0, r0, PREEMPTIBLE
	bz.d _rirq_no_reschedule
	ld sp, [r2, __tTCS_preempReg_OFFSET + __tPreempt_sp_OFFSET]

	ld_s r0, [r1, __tNANO_fiber_OFFSET] /* incoming fiber in r0 */
	cmp r0, 0
	bz.d _rirq_no_reschedule
	ld sp, [r2, __tTCS_preempReg_OFFSET + __tPreempt_sp_OFFSET]

.balign 4
_rirq_reschedule:

	/* _save_callee_saved_regs expects outgoing thread in r2 */
	_save_callee_saved_regs

	st _CAUSE_RIRQ, [r2, __tTCS_relinquish_cause_OFFSET]

	/* incoming fiber is in r0: it becomes the new 'current' */
	mov r2, r0
	st_s r2, [r1, __tNANO_current_OFFSET]
	ld_s r3, [r2, __tTCS_link_OFFSET]
	st_s r3, [r1, __tNANO_fiber_OFFSET]

#ifdef CONFIG_ARC_STACK_CHECKING
	/* Use stack top and down registers from restored context */
	add r3, r2, __tTCS_NOFLOAT_SIZEOF
	sr r3, [_ARC_V2_KSTACK_TOP]
	ld_s r3, [r2, __tTCS_stack_top_OFFSET]
	sr r3, [_ARC_V2_KSTACK_BASE]
#endif
	/*
	 * _load_callee_saved_regs expects incoming thread in r2.
	 * _load_callee_saved_regs restores the stack pointer.
	 */
	_load_callee_saved_regs

	ld_s r3, [r2, __tTCS_relinquish_cause_OFFSET]

	breq.nd r3, _CAUSE_RIRQ, _rirq_return_from_rirq
	nop
	breq.nd r3, _CAUSE_FIRQ, _rirq_return_from_firq
	nop

	/* fall through */

.balign 4
_rirq_return_from_coop:

	/* status32 and pc (blink) are already on the stack in the right order */

	/* update status32.ie (explanation in firq_exit:_firq_return_from_coop) */
	ld_s r0, [sp, 4]
	ld_s r3, [r2, __tTCS_intlock_key_OFFSET]
	st  0, [r2, __tTCS_intlock_key_OFFSET]
	cmp r3, 0
	or.ne r0, r0, _ARC_V2_STATUS32_IE
	st_s r0, [sp, 4]

	/* carve fake stack */

	sub sp, sp, (__tISF_SIZEOF - 12) /* a) status32/pc are already on the stack
	                                  * b) a real value will be pushed in r0 */

	/* push return value on stack */
	ld_s r0, [r2, __tTCS_return_value_OFFSET]
	push_s r0

	/*
	 * r13 is part of both the callee and caller-saved register sets because
	 * the processor is only able to save registers in pair in the regular
	 * IRQ prologue. r13 thus has to be set to its correct value in the IRQ
	 * stack frame.
	 */
	st r13, [sp, __tISF_r13_OFFSET]

	/* stack now has the IRQ stack frame layout, pointing to r0 */

	/* fall through to rtie instruction */

.balign 4
_rirq_return_from_firq:
_rirq_return_from_rirq:

	/* rtie will pop the rest from the stack */

	/* fall through to rtie instruction */

.balign 4
_rirq_no_reschedule:

	rtie
