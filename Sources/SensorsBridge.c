#include "SensorsBridge.h"
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach.h>
#include <dlfcn.h>
#include <string.h>
#include <stdlib.h>

// AppleSMC's 80-byte wire layout; C owns the ABI alignment rather than Swift tuples.
typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } MSVersion;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, memory; } MSPowerLimits;
typedef struct { uint32_t size, type; uint8_t attributes; } MSKeyInfo;
typedef struct {
    uint32_t key;
    MSVersion version;
    MSPowerLimits limits;
    MSKeyInfo info;
    uint8_t result, status, command;
    uint32_t index;
    uint8_t bytes[32];
} MSPacket;
_Static_assert(sizeof(MSPacket) == 80, "AppleSMC packet ABI must be 80 bytes");
_Static_assert(offsetof(MSPacket, bytes) == 48, "AppleSMC payload offset mismatch");

static int32_t ms_call(uint32_t connection, MSPacket *request, MSPacket *response) {
    size_t size = sizeof(*response);
    kern_return_t status = IOConnectCallStructMethod(connection, 2, request, sizeof(*request), response, &size);
    if (status != KERN_SUCCESS) return status;
    if (size != sizeof(*response)) return kIOReturnUnderrun;
    return response->result == 0 ? KERN_SUCCESS : (int32_t)(0x10000 + response->result);
}

int32_t ms_smc_open(uint32_t *connection) {
    *connection = 0;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return kIOReturnNotFound;
    kern_return_t status = IOServiceOpen(service, mach_task_self(), 0, connection);
    IOObjectRelease(service);
    return status;
}
void ms_smc_close(uint32_t connection) { if (connection) IOServiceClose(connection); }
int32_t ms_smc_info(uint32_t connection, uint32_t key, uint32_t *size, uint32_t *type) {
    MSPacket input = {0}, output = {0};
    input.key = key; input.command = 9;
    int32_t result = ms_call(connection, &input, &output);
    if (!result) { *size = output.info.size; *type = output.info.type; }
    return result;
}
int32_t ms_smc_read(uint32_t connection, uint32_t key, uint32_t size, uint8_t *bytes) {
    if (size == 0 || size > 32) return kIOReturnBadArgument;
    MSPacket input = {0}, output = {0};
    input.key = key; input.command = 5; input.info.size = size;
    int32_t result = ms_call(connection, &input, &output);
    if (!result) memcpy(bytes, output.bytes, size);
    return result;
}
int32_t ms_smc_key(uint32_t connection, uint32_t index, uint32_t *key) {
    MSPacket input = {0}, output = {0};
    input.command = 8; input.index = index;
    int32_t result = ms_call(connection, &input, &output);
    if (!result) *key = output.key;
    return result;
}

// HID temperature entry points are dynamically resolved: if macOS removes them,
// SMC and the CPU/RAM monitor continue to operate.
typedef CFTypeRef (*MSCreateClient)(CFAllocatorRef);
typedef void (*MSSetMatching)(CFTypeRef, CFDictionaryRef);
typedef CFArrayRef (*MSCopyServices)(CFTypeRef);
typedef CFTypeRef (*MSCopyProperty)(CFTypeRef, CFStringRef);
typedef CFTypeRef (*MSCopyEvent)(CFTypeRef, int64_t, int32_t, int64_t);
typedef double (*MSGetFloat)(CFTypeRef, uint32_t);
typedef struct {
    void *library;
    CFTypeRef client;
    CFArrayRef services;
    MSCopyProperty property;
    MSCopyEvent event;
    MSGetFloat value;
} MSHIDContext;

void *ms_hid_open(void) {
    MSHIDContext *context = calloc(1, sizeof(*context));
    if (!context) return NULL;
    context->library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
    if (!context->library) { ms_hid_close(context); return NULL; }
    MSCreateClient create = (MSCreateClient)dlsym(context->library, "IOHIDEventSystemClientCreate");
    MSSetMatching matching = (MSSetMatching)dlsym(context->library, "IOHIDEventSystemClientSetMatching");
    MSCopyServices services = (MSCopyServices)dlsym(context->library, "IOHIDEventSystemClientCopyServices");
    context->property = (MSCopyProperty)dlsym(context->library, "IOHIDServiceClientCopyProperty");
    context->event = (MSCopyEvent)dlsym(context->library, "IOHIDServiceClientCopyEvent");
    context->value = (MSGetFloat)dlsym(context->library, "IOHIDEventGetFloatValue");
    if (!create || !matching || !services || !context->property || !context->event || !context->value) {
        ms_hid_close(context); return NULL;
    }
    context->client = create(kCFAllocatorDefault);
    if (!context->client) { ms_hid_close(context); return NULL; }
    int page = 0xff00, usage = 5;
    CFNumberRef p = CFNumberCreate(NULL, kCFNumberIntType, &page);
    CFNumberRef u = CFNumberCreate(NULL, kCFNumberIntType, &usage);
    const void *keys[] = {CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage")};
    const void *values[] = {p, u};
    CFDictionaryRef filter = CFDictionaryCreate(NULL, keys, values, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    matching(context->client, filter);
    CFRelease(filter); CFRelease(p); CFRelease(u);
    context->services = services(context->client);
    return context;
}
void ms_hid_close(void *pointer) {
    MSHIDContext *context = pointer;
    if (!context) return;
    if (context->services) CFRelease(context->services);
    if (context->client) CFRelease(context->client);
    if (context->library) dlclose(context->library);
    free(context);
}
size_t ms_hid_count(void *pointer) {
    MSHIDContext *context = pointer;
    return context && context->services ? (size_t)CFArrayGetCount(context->services) : 0;
}
int ms_hid_label(void *pointer, size_t index, char *destination, size_t capacity) {
    MSHIDContext *context = pointer;
    if (!context || index >= ms_hid_count(context) || capacity == 0) return 0;
    CFTypeRef service = CFArrayGetValueAtIndex(context->services, index);
    CFTypeRef label = context->property(service, CFSTR("Product"));
    if (!label) return 0;
    int success = CFGetTypeID(label) == CFStringGetTypeID() && CFStringGetCString(label, destination, capacity, kCFStringEncodingUTF8);
    CFRelease(label);
    return success;
}
int ms_hid_temperature(void *pointer, size_t index, double *temperature) {
    MSHIDContext *context = pointer;
    if (!context || index >= ms_hid_count(context)) return 0;
    CFTypeRef service = CFArrayGetValueAtIndex(context->services, index);
    CFTypeRef event = context->event(service, 15, 0, 0);
    if (!event) return 0;
    *temperature = context->value(event, 15u << 16);
    CFRelease(event);
    return 1;
}
