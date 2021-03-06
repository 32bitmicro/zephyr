/*
 * Copyright (c) 2015 Wind River Systems, Inc.
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
 * @brief System/hardware module for the Quark D2000 BSP
 *
 * This module provides routines to initialize and support board-level
 * hardware for the Quark D2000 BSP.
 */

#include <nanokernel.h>
#include "soc.h"
#include <drivers/mvic.h>
#include <init.h>

#ifdef CONFIG_MVIC
SYS_INIT(_mvic_init, PRIMARY, CONFIG_KERNEL_INIT_PRIORITY_DEFAULT);
#endif /* CONFIG_IOAPIC */
