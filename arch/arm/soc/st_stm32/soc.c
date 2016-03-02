/*
 * Copyright (c) 2016 Intel Corporation.
 * Copyright (c) 2013-2015 Wind River Systems, Inc.
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
 * @brief System/hardware module for ST STM32 family processor
 *
 * This module provides routines to initialize and support board-level hardware
 * for the ST STM32 family processor.
 */

#include <nanokernel.h>
#include <device.h>
#include <init.h>
#include <soc.h>

#ifdef CONFIG_RUNTIME_NMI
extern void _NmiInit(void);
#define NMI_INIT() _NmiInit()
#else
#define NMI_INIT()
#endif

/**
 * @brief Setup various clocks on the SoC
 *
 * By default this configures the system to use the HSE.
 *
 * Assumption:
 * SLCK = 32.768kHz
 */
#if defined(CONFIG_SOC_ST_STM32_CLOCK_HSE)
static void clock_init(void)
{
	uint32_t tmp;
	uint32_t rc = 0;

	RCC->cr |= RCC_CR_HSEON;

	/*
	 * Time to spin until the HSE is ready.
	 */
	while (RCC->cr & RCC_CR_HSERDY) {
		rc = RCC->cr & RCC_CR_HSERDY;
	}

	/*
	 * This will setup the following values:
	 * * HCLK = SYSCLK / 1
	 * * PCLK2 = HCLK  / 2
	 * * PCLK1 = HCLK  / 4
	 */
	RCC->cfgr |= ( RCC_CFGR_HPRE_0 | RCC_CFGR_PPRE_2_2 | RCC_CFGR_PPRE_1_4);

	/*
	 * Now that the CLK is setup, configure the main PLL
	 */
	RCC->pllcfgr = STM32F2XX_PLL_M |
			(STM32F2XX_PLL_N << 6) |
			(((STM32F2XX_PLL_P >> 1) - 1) << 16) |
			(STM32F2XX_PLL_Q << 24);

	/*
	 * If everything has gone right, at this point we can enable the PLL
	 */
	RCC->cr |= RCC_CR_PLLON;

	/*
	 * Now spin until the PLL is ready
	 */
	while ((RCC->cr & RCC_CR_PLLRDY) == 0) {
		/* do nothing */
	}

	/*
	 * The PLL is now ready! First clear out any possible values, then
	 * select it as the system clock source
	 */
	RCC->cfgr &= ~(RCC_CFGR_SW_MASK);
	RCC->cfgr |= RCC_CFGR_SW_PLL;

	/* Once again, spin until this change is ready */
	while ((RCC->cfgr & RCC_CFGR_SWS) != RCC_CFGR_SWS_PLL) {
		/* do nothing */
	}

}
#elif defined(CONFIG_SOC_ST_STM32_CLOCK_HSI)
static void clock_init(void)
{
	uint32_t rc = 0;

	RCC->cr |= RCC_CR_HSION;

	/*
	 * Time to spin until the HSI is ready.
	 */
	while (RCC->cr & RCC_CR_HSIRDY) {
		rc = RCC->cr & RCC_CR_HSIRDY;
	}

	/*
	 * This will setup the following values:
	 * * HCLK = SYSCLK / 1
	 * * PCLK2 = HCLK  / 2
	 * * PCLK1 = HCLK  / 4
	 */
	RCC->cfgr |= ( RCC_CFGR_HPRE_0 | RCC_CFGR_PPRE_2_2 | RCC_CFGR_PPRE_1_4);

	/*
	 * Now that the CLK is setup, configure the main PLL
	 */
	RCC->pllcfgr = STM32F2XX_PLL_M |
			(STM32F2XX_PLL_N << 6) |
			(((STM32F2XX_PLL_P >> 1) - 1) << 16) |
			(STM32F2XX_PLL_Q << 24);

	/*
	 * If everything has gone right, at this point we can enable the PLL
	 */
	RCC->cr |= RCC_CR_PLLON;

	/*
	 * Now spin until the PLL is ready
	 */
	while ((RCC->cr & RCC_CR_PLLRDY) == 0) {
		/* do nothing */
	}

	/*
	 * The PLL is now ready! First clear out any possible values, then
	 * select it as the system clock source
	 */
	RCC->cfgr &= ~(RCC_CFGR_SW_MASK);
	RCC->cfgr |= RCC_CFGR_SW_PLL;

	/* Once again, spin until this change is ready */
	while ((RCC->cfgr & RCC_CFGR_SWS_MASK) != RCC_CFGR_SWS_PLL) {
		/* do nothing */
	}
}
#endif

/**
 * @brief Perform basic hardware initialization at boot for STM32.
 *
 * This needs to be run from the very beginning.
 * So the init priority has to be 0 (zero).
 *
 * @return 0
 */
static int st_stm32_init(struct device *arg)
{
	uint32_t key;

	ARG_UNUSED(arg);

	key = irq_lock();

	/* Setup the vector table offset register (VTOR),
	 * which is located at the beginning of flash area.
	 */
	_scs_relocate_vector_table((void *)CONFIG_FLASH_BASE_ADDRESS);

	/* Clear all faults */
	_ScbMemFaultAllFaultsReset();
	_ScbBusFaultAllFaultsReset();
	_ScbUsageFaultAllFaultsReset();

	_ScbHardFaultAllFaultsReset();

	/* Setup master clock */
	clock_init();

	/*
	 * Install default handler that simply resets the CPU
	 * if configured in the kernel, NOP otherwise
	 */
	NMI_INIT();

	irq_unlock(key);

	return 0;
}

SYS_INIT(st_stm32_init, PRIMARY, 0);
