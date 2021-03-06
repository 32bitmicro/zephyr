/*
 * Copyright (c) 2014-2015 Wind River Systems, Inc.
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
 * @brief Variables needed needed for system clock
 *
 *
 * Declare variables used by both system timer device driver and kernel
 * components that use timer functionality.
 */

#ifndef _SYS_CLOCK__H_
#define _SYS_CLOCK__H_

#ifdef __cplusplus
extern "C" {
#endif

#ifndef _ASMLANGUAGE
#include <stdint.h>

#if defined(CONFIG_SYS_CLOCK_EXISTS) && \
	(CONFIG_SYS_CLOCK_HW_CYCLES_PER_SEC == 0)
#error "SYS_CLOCK_HW_CYCLES_PER_SEC must be non-zero!"
#endif

#define sys_clock_ticks_per_sec CONFIG_SYS_CLOCK_TICKS_PER_SEC

#if defined(CONFIG_TIMER_READS_ITS_FREQUENCY_AT_RUNTIME)
extern int sys_clock_hw_cycles_per_sec;
#else
#define sys_clock_hw_cycles_per_sec CONFIG_SYS_CLOCK_HW_CYCLES_PER_SEC
#endif

/*
 * sys_clock_us_per_tick global variable represents a number
 * of microseconds in one OS timer tick
 */
extern int sys_clock_us_per_tick;

/*
 * sys_clock_hw_cycles_per_tick global variable represents a number
 * of platform clock ticks in one OS timer tick.
 * sys_clock_hw_cycles_per_tick often represents a value of divider
 * of the board clock frequency
 */
extern int sys_clock_hw_cycles_per_tick;

/* number of nsec per usec */
#define NSEC_PER_USEC 1000

/* number of microseconds per millisecond */
#define USEC_PER_MSEC 1000

/* number of milliseconds per second */
#define MSEC_PER_SEC 1000

/* number of microseconds per second */
#define USEC_PER_SEC ((USEC_PER_MSEC) * (MSEC_PER_SEC))

/* number of nanoseconds per second */
#define NSEC_PER_SEC ((NSEC_PER_USEC) * (USEC_PER_MSEC) * (MSEC_PER_SEC))


/* SYS_CLOCK_HW_CYCLES_TO_NS64 converts CPU clock cycles to nanoseconds */
#define SYS_CLOCK_HW_CYCLES_TO_NS64(X) \
	(((uint64_t)(X) * sys_clock_us_per_tick * NSEC_PER_USEC) / \
	 sys_clock_hw_cycles_per_tick)

/*
 * SYS_CLOCK_HW_CYCLES_TO_NS_AVG converts CPU clock cycles to nanoseconds
 * and calculates the average cycle time
 */
#define SYS_CLOCK_HW_CYCLES_TO_NS_AVG(X, NCYCLES) \
	(uint32_t)(SYS_CLOCK_HW_CYCLES_TO_NS64(X) / NCYCLES)

#define SYS_CLOCK_HW_CYCLES_TO_NS(X) (uint32_t)(SYS_CLOCK_HW_CYCLES_TO_NS64(X))

extern int64_t _sys_clock_tick_count;

/*
 * Number of ticks for x seconds. NOTE: With MSEC() or USEC(),
 * since it does an integer division, x must be greater or equal to
 * 1000/sys_clock_ticks_per_sec to get a non-zero value.
 * You may want to raise CONFIG_SYS_CLOCK_TICKS_PER_SEC depending on
 * your requirements.
 */
#define SECONDS(x)	((x) * sys_clock_ticks_per_sec)
#define MSEC(x)		(SECONDS(x) / MSEC_PER_SEC)
#define USEC(x)		(MSEC(x) / USEC_PER_MSEC)

#endif /* !_ASMLANGUAGE */

#ifdef __cplusplus
}
#endif

#endif /* _SYS_CLOCK__H_ */
