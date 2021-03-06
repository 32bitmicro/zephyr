/** @file
 *  @brief Bluetooth subsystem persistent storage APIs.
 */

/*
 * Copyright (c) 2016 Intel Corporation
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
#ifndef __BT_STORAGE_H
#define __BT_STORAGE_H

#include <sys/types.h>

#include <bluetooth/bluetooth.h>
#include <bluetooth/hci.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Well known storage keys */
enum {
	BT_STORAGE_ID_ADDR,        /** Identity Address */
	BT_STORAGE_LOCAL_IRK,      /** Local Identity Resolving Key */
};

struct bt_storage {
	/** Read the value of a key from storage.
	 *
	 *  @param addr   Remote address or NULL for local storage
	 *  @param key    BT_STORAGE_* key to read
	 *  @param data   Memory location to place the data
	 *  @param length Maximum number of bytes to read
	 *
	 *  @return Number of bytes read or negative error value on
	 *          failure.
	 */
	ssize_t (*read)(const bt_addr_le_t *addr, uint16_t key,
			void *data, size_t length);

	/** Write the value of a key to storage.
	 *
	 *  @param addr   Remote address or NULL for local storage
	 *  @param key    BT_STORAGE_* key to write
	 *  @param data   Memory location of the data
	 *  @param length Number of bytes to write
	 *
	 *  @return Number of bytes written or negative error value on
	 *          failure.
	 */
	ssize_t (*write)(const bt_addr_le_t *addr, uint16_t key,
			 const void *data, size_t length);

	/** Clear all keys for a specific address
	 *
	 *  @param addr   Remote address, BT_ADDR_LE_ANY for all
	 *                remote devices, or NULL for local storage.
	 *
	 *  @return 0 on success or negative error value on failure.
	 */
	int (*clear)(const bt_addr_le_t *addr);

};

void bt_storage_register(struct bt_storage *storage);

/** Clear all storage keys for a specific address
  *
  * @param addr  Remote address, NULL for local storage or
  *              BT_ADDR_LE_ANY to clear all remote devices.
  *
  * @return 0 on success or negative error value on failure.
  */
int bt_storage_clear(bt_addr_le_t *addr);

#ifdef __cplusplus
}
#endif

#endif /* __BT_STORAGE_H */
