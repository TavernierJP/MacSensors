#ifndef MACSENSORS_BRIDGE_H
#define MACSENSORS_BRIDGE_H
#include <stdint.h>
#include <stddef.h>

// Read-only transport. No fan control, SMC write or privileged helper.
int32_t ms_smc_open(uint32_t *connection);
void ms_smc_close(uint32_t connection);
int32_t ms_smc_info(uint32_t connection, uint32_t key, uint32_t *size, uint32_t *type);
int32_t ms_smc_read(uint32_t connection, uint32_t key, uint32_t size, uint8_t *bytes);
int32_t ms_smc_key(uint32_t connection, uint32_t index, uint32_t *key);
void *ms_hid_open(void);
void ms_hid_close(void *context);
size_t ms_hid_count(void *context);
int ms_hid_label(void *context, size_t index, char *destination, size_t capacity);
int ms_hid_temperature(void *context, size_t index, double *temperature);
#endif
