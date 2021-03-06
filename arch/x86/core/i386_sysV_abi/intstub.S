/*
 * Copyright (c) 2010-2014 Wind River Systems, Inc.
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
 * @brief Interrupt management support for IA-32 architecture
 *
 * This module implements assembly routines to manage interrupts on
 * the Intel IA-32 architecture.  More specifically, the interrupt (asynchronous
 * exception) stubs are implemented in this module.  The stubs are invoked when
 * entering and exiting a C interrupt handler.
 */

#define _ASMLANGUAGE

#include <nano_private.h>
#include <arch/x86/asm.h>
#include <offsets.h>	/* nanokernel structure offset definitions */
#include <arch/cpu.h>	/* _NANO_ERR_SPURIOUS_INT */
#include <drivers/loapic.h> /* LOAPIC_EOI */


	/* exports (internal APIs) */

	GTEXT(_IntEnt)
	GTEXT(_IntExitWithEoi)
	GTEXT(_IntExit)
	GTEXT(_SpuriousIntNoErrCodeHandler)
	GTEXT(_SpuriousIntHandler)
	GTEXT(_DynIntStubsBegin)
	GTEXT(_irq_sw_handler)

	/* externs */

	GTEXT(_Swap)

#ifdef CONFIG_SYS_POWER_MANAGEMENT
#if defined(CONFIG_NANOKERNEL) && defined(CONFIG_TICKLESS_IDLE)
	GTEXT(_power_save_idle_exit)
#else
	GTEXT(_sys_power_save_idle_exit)
#endif
#endif


#ifdef CONFIG_INT_LATENCY_BENCHMARK
	GTEXT(_int_latency_start)
	GTEXT(_int_latency_stop)
#endif
/**
 *
 * @brief Inform the kernel of an interrupt
 *
 * This function is called from the interrupt stub created by IRQ_CONNECT()
 * to inform the kernel of an interrupt.  This routine increments
 * _nanokernel.nested (to support interrupt nesting), switches to the
 * base of the interrupt stack, if not already on the interrupt stack, and then
 * saves the volatile integer registers onto the stack.  Finally, control is
 * returned back to the interrupt stub code (which will then invoke the
 * "application" interrupt service routine).
 *
 * Only the volatile integer registers are saved since ISRs are assumed not to
 * utilize floating point (or SSE) instructions.  If an ISR requires the usage
 * of floating point (or SSE) instructions, it must first invoke nanoCpuFpSave()
 * (or nanoCpuSseSave()) at the beginning of the ISR.  A subsequent
 * nanoCpuFpRestore() (or nanoCpuSseRestore()) is needed just prior to returning
 * from the ISR.  Note that the nanoCpuFpSave(), nanoCpuSseSave(),
 * nanoCpuFpRestore(), and nanoCpuSseRestore() APIs have not been
 * implemented yet.
 *
 * WARNINGS
 *
 * Host-based tools and the target-based GDB agent depend on the stack frame
 * created by this routine to determine the locations of volatile registers.
 * These tools must be updated to reflect any changes to the stack frame.
 *
 * @return N/A
 *
 * C function prototype:
 *
 * void _IntEnt (void);
 */
SECTION_FUNC(TEXT, _IntEnt)

	/*
	 * The _IntVecSet() routine creates an interrupt-gate descriptor for
	 * all connections.  The processor will automatically clear the IF
	 * bit in the EFLAGS register upon execution of the handler, thus
	 * _IntEnt() (and _ExcEnt) need not issue an 'cli' as the first
	 * instruction.
	 *
	 * Clear the direction flag.  It is automatically restored when the
	 * interrupt exits via the IRET instruction.
	 */

	cld



	/*
	 * Note that the processor has pushed both the EFLAGS register
	 * and the logical return address (cs:eip) onto the stack prior
	 * to invoking the handler specified in the IDT
	 */


	/*
	 * swap eax and return address on the current stack;
	 * this saves eax on the stack without losing knowledge
	 * of how to get back to the interrupt stub
	 */
	xchgl	%eax, (%esp)

	/*
	 * The remaining volatile registers are pushed onto the current
	 * stack.
	 */

	pushl	%ecx
	pushl	%edx

#ifdef CONFIG_DEBUG_INFO
	/*
	 * Push the cooperative registers on the existing stack as they are
	 * required by debug tools.
	 */

	pushl	%edi
	pushl	%esi
	pushl	%ebx
	pushl	%ebp

	leal	44(%esp), %ecx   /* Calculate ESP before interrupt occurred */
	pushl	%ecx             /* Save calculated ESP */
#endif

#ifdef CONFIG_INT_LATENCY_BENCHMARK
	/*
	 * Volatile registers are now saved it is safe to start measuring
	 * how long interrupt are disabled.
	 * The interrupt gate created by IRQ_CONNECT disables the
	 * interrupt.
	 *
	 * Preserve EAX as it contains the stub return address.
	 */

	pushl	%eax
	call	_int_latency_start
	popl	%eax
#endif

#ifdef CONFIG_KERNEL_EVENT_LOGGER_INTERRUPT
	/*
	 * Preserve EAX as it contains the stub return address.
	 */
	pushl	%eax
	call	_sys_k_event_logger_interrupt
	popl	%eax
#endif

#ifdef CONFIG_KERNEL_EVENT_LOGGER_SLEEP
	/*
	 * Preserve EAX as it contains the stub return address.
	 */
	pushl	%eax
	call	_sys_k_event_logger_exit_sleep
	popl	%eax
#endif

	/* load %ecx with &_nanokernel */

	movl	$_nanokernel, %ecx

	/* switch to the interrupt stack for the non-nested case */

	incl	__tNANO_nested_OFFSET(%ecx)	/* inc interrupt nest count */
	cmpl	$1, __tNANO_nested_OFFSET(%ecx)	/* use int stack if !nested */
#ifdef CONFIG_DEBUG_INFO
	jne	nested_save_isf
#else
	jne	alreadyOnIntStack
#endif

	/* switch to base of the interrupt stack */

	movl	%esp, %edx		/* save current thread's stack pointer */
	movl	__tNANO_common_isp_OFFSET(%ecx), %esp	/* load new sp value */


	/* save thread's stack pointer onto base of interrupt stack */

	pushl	%edx			/* Save stack pointer */

#ifdef CONFIG_DEBUG_INFO
	/*
	 * The saved stack pointer happens to match the address of the
	 * interrupt stack frame.  To simplify the exit case, push a dummy ISF
	 * for the "old" ISF and save it to the _nanokernel.isf.
	 */
	pushl	%edx
	movl	%edx, __tNANO_isf_OFFSET(%ecx)
#endif

#ifdef CONFIG_SYS_POWER_MANAGEMENT
	cmpl	$0, __tNANO_idle_OFFSET(%ecx)
	jne	_HandleIdle
	/* fast path is !idle, in the pipeline */
#endif

#ifdef CONFIG_DEBUG_INFO
	jmp alreadyOnIntStack

BRANCH_LABEL(nested_save_isf)
	movl	__tNANO_isf_OFFSET(%ecx), %edx	/* Get old ISF */
	movl	%esp, __tNANO_isf_OFFSET(%ecx)	/* Save new ISF */
	pushl	%edx                            /* Save old ISF */
#endif

	/* fall through to nested case */

BRANCH_LABEL(alreadyOnIntStack)
#ifdef CONFIG_INT_LATENCY_BENCHMARK
	/* preserve eax which contain stub return address */
	pushl	%eax
	call	_int_latency_stop
	popl	%eax
#endif
#ifdef CONFIG_NESTED_INTERRUPTS
	sti			/* re-enable interrupts */
#endif
	jmp	*%eax		/* "return" back to stub */

#ifdef CONFIG_SYS_POWER_MANAGEMENT
BRANCH_LABEL(_HandleIdle)
#if defined(CONFIG_NANOKERNEL) && defined(CONFIG_TICKLESS_IDLE)
	pushl	%eax
	call _power_save_idle_exit
#else
	pushl	%eax
	push	__tNANO_idle_OFFSET(%ecx)
	movl	$0, __tNANO_idle_OFFSET(%ecx)

	/*
	 * Beware that a timer driver's _sys_power_save_idle_exit() implementation might
	 * expect that interrupts are disabled when invoked.  This ensures that
	 * the calculation and programming of the device for the next timer
	 * deadline is not interrupted.
	 */

	call	_sys_power_save_idle_exit
	add	$0x4, %esp
#endif /* CONFIG_NANOKERNEL && CONFIG_TICKLESS_IDLE */
#ifdef CONFIG_INT_LATENCY_BENCHMARK
	call	_int_latency_stop
#endif
	sti			/* re-enable interrupts */
	popl	%eax
	jmp	*%eax		/* "return" back to stub */
#endif /* CONFIG_SYS_POWER_MANAGEMENT */

/**
 * @brief Perform EOI, clean up stack, and do interrupt exit
 *
 * This is used by the interrupt stubs, which all leave the stack in
 * a particular state and need to poke the interrupt controller.
 * Prior to running the logic in _IntExit, the ISR parameter is popped off
 * the stack and EOI is set to the LOAPIC.
 */
SECTION_FUNC(TEXT, _IntExitWithEoi)
	popl %eax			/* Pushed onto stack by stub */
#if CONFIG_EOI_FORWARDING_BUG
	call	_lakemont_eoi
#endif
	xorl %eax, %eax			/* zeroes eax */
	/* TODO not great to have hard-coded LOAPIC stuff here. When
	 * we get around to introducing the interrupt controller abstraction
	 * layer, the in-use IRQ controller code will define an ASM macro
	 * with a specific name which does the correct thing for the particular
	 * controller.
	 */
	loapic_eoi_reg = (CONFIG_LOAPIC_BASE_ADDRESS + LOAPIC_EOI)
	movl %eax, loapic_eoi_reg	/* tell LOAPIC the IRQ is handled */
	/* fall through to _IntExit */

/**
 *
 * @brief Inform the kernel of an interrupt exit
 *
 * This function is called from the interrupt stub created by IRQ_CONNECT()
 * to inform the kernel that the processing of an interrupt has
 * completed.  This routine decrements _nanokernel.nested (to support interrupt
 * nesting), restores the volatile integer registers, and then switches
 * back to the interrupted execution context's stack, if this isn't a nested
 * interrupt.
 *
 * Finally, control is returned back to the interrupted fiber or ISR.
 * A context switch _may_ occur if the interrupted context was a task context,
 * in which case one or more other fibers and tasks will execute before
 * this routine resumes and control gets returned to the interrupted task.
 *
 * @return N/A
 *
 * C function prototype:
 *
 * void _IntExit (void);
 */
BRANCH_LABEL(_IntExit)

	cli			/* disable interrupts */
#ifdef CONFIG_INT_LATENCY_BENCHMARK
	call	_int_latency_start
#endif

	/* determine whether exiting from a nested interrupt */

	movl	$_nanokernel, %ecx
#ifdef CONFIG_DEBUG_INFO
	popl	__tNANO_isf_OFFSET(%ecx)    /* Restore old ISF */
#endif
	decl	__tNANO_nested_OFFSET(%ecx)	/* dec interrupt nest count */
	jne	nestedInterrupt                 /* 'iret' if nested case */


	/*
	 * Determine whether the execution of the ISR requires a context
	 * switch.  If the interrupted thread is PREEMPTIBLE (a task) and
	 * _nanokernel.fiber is non-NULL, a _Swap() needs to occur.
	 */

	movl	__tNANO_current_OFFSET (%ecx), %eax
	testl	$PREEMPTIBLE, __tTCS_flags_OFFSET(%eax)
	je	noReschedule
	cmpl	$0, __tNANO_fiber_OFFSET (%ecx)
	je	noReschedule

	/*
	 * Set the INT_ACTIVE bit in the tTCS to allow the upcoming call to
	 * _Swap() to determine whether non-floating registers need to be
	 * preserved using the lazy save/restore algorithm, or to indicate to
	 * debug tools that a preemptive context switch has occurred.
	 *
	 * Setting the NO_METRICS bit tells _Swap() that the per-execution context
	 * [totalRunTime] calculation has already been performed and that
	 * there is no need to do it again.
	 */

#if defined(CONFIG_FP_SHARING) ||  defined(CONFIG_GDB_INFO)
	orl	$INT_ACTIVE, __tTCS_flags_OFFSET(%eax)
#endif

	/*
	 * A context reschedule is required: keep the volatile registers of
	 * the interrupted thread on the context's stack.  Utilize
	 * the existing _Swap() primitive to save the remaining
	 * thread's registers (including floating point) and perform
	 * a switch to the new thread.
	 */

	popl	%esp		/* switch back to kernel stack */

#ifdef CONFIG_DEBUG_INFO
	popl	%ebp        /* Discard saved ESP */
	popl	%ebp
	popl	%ebx
	popl	%esi
	popl	%edi
#endif

	pushfl			/* push KERNEL_LOCK_KEY argument */
	call	_Swap

	/*
	 * The interrupted thread has now been scheduled,
	 * as the result of a _later_ invocation of _Swap().
	 *
	 * Now need to restore the interrupted thread's environment before
	 * returning control to it at the point where it was interrupted ...
	 */


#if ( defined(CONFIG_FP_SHARING) ||  \
      defined(CONFIG_GDB_INFO) )
	/*
	 * _Swap() has restored the floating point registers, if needed.
	 * Clear the INT_ACTIVE bit of the interrupted thread's TCS
	 * since it has served its purpose.
	 */

	movl	_nanokernel + __tNANO_current_OFFSET, %eax
	andl	$~INT_ACTIVE, __tTCS_flags_OFFSET (%eax)
#endif /* CONFIG_FP_SHARING || CONFIG_GDB_INFO */


	addl 	$4, %esp	/* pop KERNEL_LOCK_KEY argument */




	/* Restore volatile registers and return to the interrupted thread */
#ifdef CONFIG_INT_LATENCY_BENCHMARK
	call	_int_latency_stop
#endif

	popl	%edx
	popl	%ecx
	popl	%eax

	/* Pop of EFLAGS will re-enable interrupts and restore direction flag */
	iret


BRANCH_LABEL(noReschedule)

	/*
	 * A thread reschedule is not required; switch back to the
	 * interrupted thread's stack and restore volatile registers
	 */

	popl	%esp		/* pop thread stack pointer */


	/* fall through to 'nestedInterrupt' */


	/*
	 * For the nested interrupt case, the interrupt stack must still be
	 * utilized, and more importantly, a rescheduling decision must
	 * not be performed.
	 */

BRANCH_LABEL(nestedInterrupt)
#ifdef CONFIG_INT_LATENCY_BENCHMARK
	call	_int_latency_stop
#endif

#ifdef CONFIG_DEBUG_INFO
	popl	%ebp        /* Discard saved ESP */
	popl	%ebp
	popl	%ebx
	popl	%esi
	popl	%edi
#endif

	popl	%edx		/* pop volatile registers in reverse order */
	popl	%ecx
	popl	%eax
	/* Pop of EFLAGS will re-enable interrupts and restore direction flag */
	iret


/**
 *
 * _SpuriousIntHandler -
 * @brief Spurious interrupt handler stubs
 *
 * Interrupt-gate descriptors are statically created for all slots in the IDT
 * that point to _SpuriousIntHandler() or _SpuriousIntNoErrCodeHandler().  The
 * former stub is connected to exception vectors where the processor pushes an
 * error code onto the stack (or kernel stack) in addition to the EFLAGS/CS/EIP
 * records.
 *
 * A spurious interrupt is considered a fatal condition, thus this routine
 * merely sets up the 'reason' and 'pEsf' parameters to the routine
 *  _SysFatalHwErrorHandler().  In other words, there is no provision to return
 * to the interrupted execution context and thus the volatile registers are not
 * saved.
 *
 * @return Never returns
 *
 * C function prototype:
 *
 * void _SpuriousIntHandler (void);
 *
 * INTERNAL
 * The _IntVecSet() routine creates an interrupt-gate descriptor for all
 * connections.  The processor will automatically clear the IF bit
 * in the EFLAGS register upon execution of the handler,
 * thus _SpuriousIntNoErrCodeHandler()/_SpuriousIntHandler() shall be
 * invoked with interrupts disabled.
 */
SECTION_FUNC(TEXT, _SpuriousIntNoErrCodeHandler)

	pushl	$0			/* push dummy err code onto stk */

	/* fall through to _SpuriousIntHandler */


SECTION_FUNC(TEXT, _SpuriousIntHandler)

	cld				/* Clear direction flag */

	/* Create the ESF */

	pushl %eax
	pushl %ecx
	pushl %edx
	pushl %edi
	pushl %esi
	pushl %ebx
	pushl %ebp

	leal	44(%esp), %ecx   /* Calculate ESP before exception occurred */
	pushl	%ecx             /* Save calculated ESP */

	/*
	 * The task's regular stack is being used, but push the value of ESP
	 * anyway so that _ExcExit can "recover the stack pointer"
	 * without determining whether the exception occurred while CPL=3
	 */

	pushl	%esp			/* push cur stack pointer: pEsf arg */

BRANCH_LABEL(finishSpuriousInt)

	/* re-enable interrupts */

	sti

	/* push the 'unsigned int reason' parameter */

	pushl	$_NANO_ERR_SPURIOUS_INT

BRANCH_LABEL(callFatalHandler)

	/* call the fatal error handler */

	call	_NanoFatalErrorHandler

	/* handler shouldn't return, but call it again if it does */

	jmp	callFatalHandler

#if ALL_DYN_IRQ_STUBS > 0
BRANCH_LABEL(_DynIntStubCommon)
	call _common_dynamic_irq_handler
	/* Clean up and call IRET */
	jmp _IntExitWithEoi

/* Create all the dynamic IRQ stubs
 *
 * NOTE: Please update DYN_STUB_SIZE in include/arch/x86/arch.h if you change
 * how large the generated stubs are, otherwise _get_dynamic_stub() will
 * be unable to correctly determine the offset
 */

/*
 * Create nice labels for all the stubs so we can see where we
 * are in a debugger
 */
.altmacro
.macro __INT_STUB_NUM id
BRANCH_LABEL(_DynIntStub\id)
.endm
.macro INT_STUB_NUM id
__INT_STUB_NUM %id
.endm

SECTION_FUNC(TEXT, _DynIntStubsBegin)
stub_num = 0
.rept ((ALL_DYN_IRQ_STUBS + DYN_STUB_PER_BLOCK - 1) / DYN_STUB_PER_BLOCK)
	block_counter = 0
	.rept DYN_STUB_PER_BLOCK
		.if stub_num < ALL_DYN_IRQ_STUBS
			INT_STUB_NUM stub_num
			/*
			 * TODO: make this call in _DynIntStubCommon, saving
			 * 5 bytes per stub. Some voodoo will be necessary
			 * in _IntEnt/_IntExit to transplant the pushed
			 * stub_num to the irq stack
			 */
			call _IntEnt

			/*
			 * 2-byte push imm8. Consumed by
			 * common_dynamic_handler(), see intconnect.c
			 */
			push $stub_num

			/*
			 * Check to make sure this isn't the last stub in
			 * a block, in which case we just fall through
			 */
			.if (block_counter <> (DYN_STUB_PER_BLOCK - 1) && \
			     (stub_num <> ALL_DYN_IRQ_STUBS - 1))
				/* This should always be a 2-byte jmp rel8 */
				jmp 1f
			.endif
			stub_num = stub_num + 1
			block_counter = block_counter + 1
		.endif
	.endr
	/*
	 * This must a 5-bvte jump rel32, which is why _DynStubCommon
	 * is before the actual stubs
	 */
1:	jmp _DynIntStubCommon
.endr
#endif /* ALL_DYN_IRQ_STUBS */

#if CONFIG_IRQ_OFFLOAD
SECTION_FUNC(TEXT, _irq_sw_handler)
	call _IntEnt
	call _irq_do_offload
	jmp _IntExit

#endif
