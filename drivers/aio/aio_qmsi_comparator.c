/*
 * Copyright (c) 2016 Intel Corporation.
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

#include <errno.h>

#include <stdio.h>
#include <nanokernel.h>
#include <board.h>
#include <device.h>
#include <init.h>
#include <aio_comparator.h>

#include "qm_comparator.h"

#define INT_COMPARATORS_MASK 0x7FFFF
#define AIO_QMSI_CMP_COUNT		(19)

struct aio_qmsi_cmp_cb {
	aio_cmp_cb cb;
	void *param;
};

struct aio_qmsi_cmp_dev_data_t {
	/** Number of total comparators */
	uint8_t num_cmp;
	/** Callback for each comparator */
	struct aio_qmsi_cmp_cb cb[AIO_QMSI_CMP_COUNT];
};

static int aio_cmp_config(struct device *dev);

static int aio_qmsi_cmp_disable(struct device *dev, uint8_t index)
{
	qm_ac_config_t config;

	if (qm_ac_get_config(&config) != QM_RC_OK) {
		return -EINVAL;
	}

	if (index >= AIO_QMSI_CMP_COUNT) {
		return -EINVAL;
	}

	/* Disable interrupt to host */
	QM_SCSS_INT->int_comparators_host_mask |= (1 << index);

	/* Disable comparator according to index */
	config.int_en &= ~(1 << index);
	config.power &= ~(1 << index);

	if (qm_ac_set_config(&config) != QM_RC_OK) {
		return -EINVAL;
	}

	return 0;
}

static int aio_qmsi_cmp_configure(struct device *dev, uint8_t index,
			 enum aio_cmp_polarity polarity,
			 enum aio_cmp_ref refsel,
			 aio_cmp_cb cb, void *param)
{
	struct aio_qmsi_cmp_dev_data_t *dev_data =
		(struct aio_qmsi_cmp_dev_data_t *)dev->driver_data;

	qm_ac_config_t config;

	if (qm_ac_get_config(&config) != QM_RC_OK) {
		return -EINVAL;
	}

	if (index >= AIO_QMSI_CMP_COUNT) {
		return -EINVAL;
	}

	aio_qmsi_cmp_disable(dev, index);

	dev_data->cb[index].cb = cb;
	dev_data->cb[index].param = param;

	if (refsel == AIO_CMP_REF_A) {
		config.reference &= ~(1 << index);
	} else {
		config.reference |= (1 << index);
	}

	if (polarity == AIO_CMP_POL_RISE) {
		config.polarity &= ~(1 << index);
	} else {
		config.polarity |= (1 << index);
	}
	/* The driver will not use QMSI callback mechanism */
	config.callback = NULL;
	/* Enable comparator */
	config.int_en |= (1 << index);
	config.power |= (1 << index);

	if (qm_ac_set_config(&config) != QM_RC_OK) {
		return -EINVAL;
	}

	/* Enable Interrupts to host for an specific comparator */
	QM_SCSS_INT->int_comparators_host_mask &= ~(1 << index);

	return 0;
}

static struct aio_cmp_driver_api aio_cmp_funcs = {
	.disable = aio_qmsi_cmp_disable,
	.configure = aio_qmsi_cmp_configure,
};

int aio_qmsi_cmp_init(struct device *dev)
{
	uint8_t i;
	struct aio_qmsi_cmp_dev_data_t *dev_data =
		(struct aio_qmsi_cmp_dev_data_t *)dev->driver_data;

	aio_cmp_config(dev);

	/* Disable all comparator interrupts */
	QM_SCSS_INT->int_comparators_host_mask |= INT_COMPARATORS_MASK;

	/* Clear status and dissble all comparators */
	QM_SCSS_CMP->cmp_stat_clr |= INT_COMPARATORS_MASK;
	QM_SCSS_CMP->cmp_pwr &= ~INT_COMPARATORS_MASK;
	QM_SCSS_CMP->cmp_en &= ~INT_COMPARATORS_MASK;

	/* Clear callback pointers */
	for (i = 0; i < dev_data->num_cmp; i++) {
		dev_data->cb[i].cb = NULL;
		dev_data->cb[i].param = NULL;
	}

	irq_enable(QM_IRQ_AC);

	return 0;
}

void aio_qmsi_cmp_isr(struct device *dev)
{
	uint8_t i;
	struct aio_qmsi_cmp_dev_data_t *dev_data =
		(struct aio_qmsi_cmp_dev_data_t *)dev->driver_data;

	uint32_t int_status = QM_SCSS_CMP->cmp_stat_clr;

	for (i = 0; i < dev_data->num_cmp; i++) {
		if (int_status & (1 << i)) {
			aio_qmsi_cmp_disable(dev, i);
			if (dev_data->cb[i].cb != NULL) {
				dev_data->cb[i].cb(dev_data->cb[i].param);
			}
		}
	}

	/* Clear all pending interrupts */
	QM_SCSS_CMP->cmp_stat_clr = int_status;
}

struct aio_qmsi_cmp_dev_data_t aio_qmsi_cmp_dev_data = {
		.num_cmp = AIO_QMSI_CMP_COUNT,
};

DEVICE_AND_API_INIT(aio_qmsi_cmp, CONFIG_AIO_QMSI_COMPARATOR_DEV_NAME,
		    &aio_qmsi_cmp_init, &aio_qmsi_cmp_dev_data, NULL,
		    SECONDARY, CONFIG_KERNEL_INIT_PRIORITY_DEVICE,
		    (void *)&aio_cmp_funcs);

static int aio_cmp_config(struct device *dev)
{
	ARG_UNUSED(dev);

	IRQ_CONNECT(QM_IRQ_AC, CONFIG_AIO_COMPARATOR_IRQ_PRI,
		    aio_qmsi_cmp_isr, DEVICE_GET(aio_qmsi_cmp), 0);

	return 0;
}
