@import Foundation;
@import IOKit;
@import CoreGraphics;

#include <unistd.h>

typedef CFTypeRef IOAVServiceRef;

extern IOAVServiceRef IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service);
extern IOReturn IOAVServiceReadI2C(IOAVServiceRef service, uint32_t chipAddress,
                                  uint32_t offset, void *buffer, uint32_t size);
extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef service, uint32_t chipAddress,
                                   uint32_t dataAddress, void *buffer, uint32_t size);
extern CFDictionaryRef CoreDisplay_DisplayCreateInfoDictionary(CGDirectDisplayID displayID);

static const UInt32 kDefaultChipAddress = 0x37;
static const UInt32 kMCDP29xxChipAddress = 0xB7;
static const UInt8 kDefaultDataAddress = 0x51;

typedef struct {
    CGDirectDisplayID displayID;
    io_service_t adapter;
    NSString *name;
    NSString *uuid;
} DisplayInfo;

typedef struct {
    IOAVServiceRef service;
    UInt32 chipAddress;
} DDCTransport;

static CFTypeRef recursiveProperty(io_service_t service, CFStringRef key) {
    return IORegistryEntrySearchCFProperty(
        service, kIOServicePlane, key, kCFAllocatorDefault, kIORegistryIterateRecursively
    );
}

static BOOL isMCDP29xxProxy(io_service_t proxy) {
    io_registry_entry_t parent = MACH_PORT_NULL;
    if (IORegistryEntryGetParentEntry(proxy, kIOServicePlane, &parent) != KERN_SUCCESS) {
        return NO;
    }

    CFTypeRef value = IORegistryEntryCreateCFProperty(
        parent, CFSTR("EPICProviderClass"), kCFAllocatorDefault, 0
    );
    BOOL matches = value && CFGetTypeID(value) == CFStringGetTypeID() &&
        CFStringCompare(value, CFSTR("AppleDCPMCDP29XX"), 0) == kCFCompareEqualTo;
    if (value) CFRelease(value);
    IOObjectRelease(parent);
    return matches;
}

static DDCTransport transportForDisplay(DisplayInfo *display) {
    DDCTransport result = { NULL, kDefaultChipAddress };
    if (!display || display->adapter == MACH_PORT_NULL) return result;

    uint64_t adapterID = 0;
    if (IORegistryEntryGetRegistryEntryID(display->adapter, &adapterID) != KERN_SUCCESS) {
        return result;
    }

    io_registry_entry_t root = IORegistryGetRootEntry(kIOMainPortDefault);
    io_iterator_t iterator = MACH_PORT_NULL;
    if (IORegistryEntryCreateIterator(
            root, kIOServicePlane, kIORegistryIterateRecursively, &iterator
        ) != KERN_SUCCESS) {
        return result;
    }

    BOOL matchedFramebuffer = NO;
    io_service_t service = MACH_PORT_NULL;
    while ((service = IOIteratorNext(iterator)) != MACH_PORT_NULL) {
        if (IOObjectConformsTo(service, "IOMobileFramebuffer")) {
            uint64_t framebufferID = 0;
            matchedFramebuffer =
                IORegistryEntryGetRegistryEntryID(service, &framebufferID) == KERN_SUCCESS &&
                framebufferID == adapterID;
            IOObjectRelease(service);
            continue;
        }

        io_name_t name = {0};
        IORegistryEntryGetName(service, name);
        if (!matchedFramebuffer || strcmp(name, "DCPAVServiceProxy") != 0) {
            IOObjectRelease(service);
            continue;
        }

        IOAVServiceRef avService = IOAVServiceCreateWithService(kCFAllocatorDefault, service);
        if (!avService) {
            IOObjectRelease(service);
            continue;
        }

        CFTypeRef location = recursiveProperty(service, CFSTR("Location"));
        BOOL external = location && CFGetTypeID(location) == CFStringGetTypeID() &&
            CFStringCompare(location, CFSTR("External"), 0) == kCFCompareEqualTo;
        if (location) CFRelease(location);

        if (!external) {
            CFRelease(avService);
            IOObjectRelease(service);
            continue;
        }

        result.service = avService;
        result.chipAddress = isMCDP29xxProxy(service)
            ? kMCDP29xxChipAddress
            : kDefaultChipAddress;
        IOObjectRelease(service);
        break;
    }

    IOObjectRelease(iterator);
    return result;
}

static int onlineDisplays(DisplayInfo *result, int capacity) {
    CGDirectDisplayID ids[16] = {0};
    CGDisplayCount count = 0;
    if (CGGetOnlineDisplayList(16, ids, &count) != kCGErrorSuccess) return 0;

    int outputCount = 0;
    for (CGDisplayCount i = 0; i < count && outputCount < capacity; i++) {
        if (CGDisplayIsBuiltin(ids[i])) continue;

        CFDictionaryRef info = CoreDisplay_DisplayCreateInfoDictionary(ids[i]);
        if (!info) continue;

        NSString *uuid = (__bridge NSString *)CFDictionaryGetValue(info, CFSTR("kCGDisplayUUID"));
        NSString *location = (__bridge NSString *)CFDictionaryGetValue(info, CFSTR("IODisplayLocation"));
        if (!uuid || !location) {
            CFRelease(info);
            continue;
        }

        io_service_t adapter = IORegistryEntryCopyFromPath(
            kIOMainPortDefault, (__bridge CFStringRef)location
        );
        if (adapter == MACH_PORT_NULL) {
            CFRelease(info);
            continue;
        }

        NSString *productName = nil;
        CFTypeRef attributes = recursiveProperty(adapter, CFSTR("DisplayAttributes"));
        if (attributes && CFGetTypeID(attributes) == CFDictionaryGetTypeID()) {
            NSDictionary *dictionary = (__bridge NSDictionary *)attributes;
            NSDictionary *product = dictionary[@"ProductAttributes"];
            productName = product[@"ProductName"];
        }

        DisplayInfo candidate = {
            .displayID = ids[i],
            .adapter = adapter,
            .name = [productName ?: @"External Display" copy],
            .uuid = [uuid copy]
        };
        if (attributes) CFRelease(attributes);

        DDCTransport transport = transportForDisplay(&candidate);
        if (transport.service) {
            CFRelease(transport.service);
            result[outputCount++] = candidate;
        } else {
            IOObjectRelease(adapter);
        }
        CFRelease(info);
    }
    return outputCount;
}

static UInt8 checksum(UInt8 dataAddress, const UInt8 *bytes, size_t count) {
    UInt8 value = 0x6E ^ dataAddress;
    for (size_t i = 0; i < count; i++) value ^= bytes[i];
    return value;
}

static BOOL readVCP(DDCTransport transport, UInt8 code, UInt16 *current, UInt16 *maximum) {
    UInt8 request[4] = { 0x82, 0x01, code, 0 };
    // A Get VCP request checksum starts with the display destination (0x6E),
    // while a Set VCP request also includes the host source address (0x51).
    request[3] = 0x6E ^ request[0] ^ request[1] ^ request[2];

    for (int attempt = 0; attempt < 3; attempt++) {
        IOReturn writeResult = kIOReturnSuccess;
        // A number of LG firmwares only queue a Get VCP reply reliably after
        // the request is repeated. This mirrors m1ddc's proven transaction.
        for (int writeAttempt = 0; writeAttempt < 2; writeAttempt++) {
            usleep(10000);
            writeResult = IOAVServiceWriteI2C(
                transport.service, transport.chipAddress, kDefaultDataAddress,
                request, (uint32_t)sizeof(request)
            );
            if (writeResult != kIOReturnSuccess) break;
        }
        if (writeResult != kIOReturnSuccess) continue;

        usleep(transport.chipAddress == kMCDP29xxChipAddress ? 50000 : 10000);
        UInt8 reply[12] = {0};
        IOReturn readResult = IOAVServiceReadI2C(
            transport.service, transport.chipAddress, kDefaultDataAddress,
            reply, (uint32_t)sizeof(reply)
        );
        if (readResult != kIOReturnSuccess) continue;

        if (getenv("MONITOR_DDC_DEBUG")) {
            fprintf(stderr, "reply:");
            for (size_t i = 0; i < sizeof(reply); i++) fprintf(stderr, " %02X", reply[i]);
            fputc('\n', stderr);
        }

        // Get VCP Feature Reply: result byte 0 means supported; byte 4 echoes VCP code.
        if (reply[2] != 0x02 || reply[3] != 0x00 || reply[4] != code) continue;
        *maximum = ((UInt16)reply[6] << 8) | reply[7];
        *current = ((UInt16)reply[8] << 8) | reply[9];
        return YES;
    }
    return NO;
}

static BOOL writeVCP(DDCTransport transport, UInt8 code, UInt16 value, UInt8 dataAddress) {
    UInt8 packet[6] = {
        0x84, 0x03, code, (UInt8)(value >> 8), (UInt8)(value & 0xFF), 0
    };
    packet[5] = checksum(dataAddress, packet, 5);

    // LG acknowledges a single write without necessarily applying it. Send the
    // same packet twice; DDC Set VCP operations are idempotent.
    for (int attempt = 0; attempt < 2; attempt++) {
        usleep(10000);
        IOReturn result = IOAVServiceWriteI2C(
            transport.service, transport.chipAddress, dataAddress,
            packet, (uint32_t)sizeof(packet)
        );
        if (result != kIOReturnSuccess) return NO;
    }
    return YES;
}

static unsigned long parseNumber(const char *text, BOOL *valid) {
    if (!text || !*text) {
        *valid = NO;
        return 0;
    }
    char *end = NULL;
    unsigned long value = strtoul(text, &end, 0);
    *valid = end && *end == '\0';
    return value;
}

static void printJSON(id object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
}

static int usage(void) {
    fprintf(stderr,
        "Usage:\n"
        "  monitor-ddc list\n"
        "  monitor-ddc scan <display-index>\n"
        "  monitor-ddc read <display-index> <vcp-code>\n"
        "  monitor-ddc write <display-index> <vcp-code> <value> [data-address]\n"
        "Numbers accept decimal or 0x-prefixed hexadecimal notation.\n"
    );
    return 64;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) return usage();

        DisplayInfo displays[16] = {0};
        int count = onlineDisplays(displays, 16);

        if (strcmp(argv[1], "list") == 0) {
            NSMutableArray *json = [NSMutableArray array];
            for (int i = 0; i < count; i++) {
                [json addObject:@{
                    @"index": @(i + 1),
                    @"displayID": @(displays[i].displayID),
                    @"name": displays[i].name,
                    @"uuid": displays[i].uuid
                }];
            }
            printJSON(json);
            return 0;
        }

        if (argc < 3) return usage();
        BOOL indexValid = NO;
        unsigned long index = parseNumber(argv[2], &indexValid);
        if (!indexValid || index < 1 || index > (unsigned long)count) {
            fprintf(stderr, "Invalid display index.\n");
            return 65;
        }

        DDCTransport transport = transportForDisplay(&displays[index - 1]);
        if (!transport.service) {
            fprintf(stderr, "No DDC channel is available for that display.\n");
            return 69;
        }

        if (strcmp(argv[1], "scan") == 0) {
            NSMutableArray *values = [NSMutableArray array];
            for (int code = 0; code <= UINT8_MAX; code++) {
                UInt16 current = 0, maximum = 0;
                if (readVCP(transport, (UInt8)code, &current, &maximum)) {
                    [values addObject:@{
                        @"code": @(code), @"current": @(current), @"maximum": @(maximum)
                    }];
                }
            }
            printJSON(values);
            CFRelease(transport.service);
            for (int i = 0; i < count; i++) IOObjectRelease(displays[i].adapter);
            return 0;
        }

        if (argc < 4) {
            CFRelease(transport.service);
            return usage();
        }
        BOOL codeValid = NO;
        unsigned long code = parseNumber(argv[3], &codeValid);
        if (!codeValid || code > UINT8_MAX) {
            fprintf(stderr, "Invalid VCP code.\n");
            CFRelease(transport.service);
            return 65;
        }

        int exitCode = 0;
        if (strcmp(argv[1], "read") == 0) {
            UInt16 current = 0, maximum = 0;
            if (!readVCP(transport, (UInt8)code, &current, &maximum)) {
                fprintf(stderr, "The display did not return a valid value for VCP 0x%02lX.\n", code);
                exitCode = 70;
            } else {
                printJSON(@{
                    @"code": @(code), @"current": @(current), @"maximum": @(maximum)
                });
            }
        } else if (strcmp(argv[1], "write") == 0) {
            if (argc < 5) {
                CFRelease(transport.service);
                return usage();
            }
            BOOL valueValid = NO;
            unsigned long value = parseNumber(argv[4], &valueValid);
            UInt8 dataAddress = kDefaultDataAddress;
            if (argc >= 6) {
                BOOL addressValid = NO;
                unsigned long address = parseNumber(argv[5], &addressValid);
                if (!addressValid || address > UINT8_MAX) valueValid = NO;
                else dataAddress = (UInt8)address;
            }
            if (!valueValid || value > UINT16_MAX) {
                fprintf(stderr, "Invalid VCP value or data address.\n");
                exitCode = 65;
            } else if (!writeVCP(transport, (UInt8)code, (UInt16)value, dataAddress)) {
                fprintf(stderr, "DDC write failed.\n");
                exitCode = 70;
            } else {
                printJSON(@{ @"ok": @YES, @"value": @(value) });
            }
        } else {
            exitCode = usage();
        }

        CFRelease(transport.service);
        for (int i = 0; i < count; i++) IOObjectRelease(displays[i].adapter);
        return exitCode;
    }
}
