#include "NativeDockTile.h"

#include <ApplicationServices/ApplicationServices.h>
#include <mach/mach.h>
#include <mach/ndr.h>
#include <servers/bootstrap.h>
#include <stdlib.h>
#include <string.h>

#pragma pack(push, 4)
typedef struct {
    mach_msg_header_t header;           // 0x00 .. 0x17
    mach_msg_body_t body;               // 0x18 .. 0x1B
    mach_msg_ool_descriptor_t pixels;   // 0x1C .. 0x2B
    NDR_record_t ndr;                   // 0x2C .. 0x33
    uint32_t psn_hi;                    // 0x34 .. 0x37
    uint32_t psn_lo;                    // 0x38 .. 0x3B
    uint32_t flags;                     // 0x3C .. 0x3F
    uint32_t side;                      // 0x40 .. 0x43
    uint32_t bytes_per_row;             // 0x44 .. 0x47
    uint32_t bitmap_info;               // 0x48 .. 0x4B
    uint32_t data_length;               // 0x4C .. 0x4F
} DockNativeTileFrameMsg;

typedef struct {
    mach_msg_header_t header;           // 0x00 .. 0x17
    NDR_record_t ndr;                   // 0x18 .. 0x1F
    uint32_t psn_hi;                    // 0x20 .. 0x23
    uint32_t psn_lo;                    // 0x24 .. 0x27
} DockNativeTileReleaseMsg;
#pragma pack(pop)

_Static_assert(sizeof(DockNativeTileFrameMsg) == 0x50, "Frame msg must be 80 bytes");
_Static_assert(sizeof(DockNativeTileReleaseMsg) == 0x28, "Release msg must be 40 bytes");

#include <pthread.h>

static pthread_mutex_t dock_port_lock = PTHREAD_MUTEX_INITIALIZER;
static mach_port_t cached_dock_port = MACH_PORT_NULL;

static mach_port_t acquire_dock_server_port(void) {
    pthread_mutex_lock(&dock_port_lock);
    if (cached_dock_port != MACH_PORT_NULL) {
        mach_port_t p = cached_dock_port;
        pthread_mutex_unlock(&dock_port_lock);
        return p;
    }
    mach_port_t bp = MACH_PORT_NULL;
    if (task_get_special_port(mach_task_self(), TASK_BOOTSTRAP_PORT, &bp) != KERN_SUCCESS) {
        pthread_mutex_unlock(&dock_port_lock);
        return MACH_PORT_NULL;
    }
    mach_port_t dock_port = MACH_PORT_NULL;
    kern_return_t kr = bootstrap_look_up(bp, "com.apple.dock.server", &dock_port);
    if (kr != KERN_SUCCESS) {
        pthread_mutex_unlock(&dock_port_lock);
        return MACH_PORT_NULL;
    }
    cached_dock_port = dock_port;
    pthread_mutex_unlock(&dock_port_lock);
    return dock_port;
}

static void invalidate_dock_server_port(mach_port_t stale_port) {
    pthread_mutex_lock(&dock_port_lock);
    if (cached_dock_port != MACH_PORT_NULL && cached_dock_port == stale_port) {
        mach_port_deallocate(mach_task_self(), cached_dock_port);
        cached_dock_port = MACH_PORT_NULL;
    }
    pthread_mutex_unlock(&dock_port_lock);
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
bool native_dock_get_psn_for_pid(pid_t pid, NativeDockPSN *out_psn) {
    if (!out_psn || pid <= 0) return false;
    ProcessSerialNumber psn = {0, 0};
    OSStatus status = GetProcessForPID(pid, &psn);
    if (status != noErr) return false;
    out_psn->high = psn.highLongOfPSN;
    out_psn->low = psn.lowLongOfPSN;
    return true;
}
#pragma clang diagnostic pop

int32_t native_dock_draw_half_float_bytes(NativeDockPSN psn, const void *pixels, uint32_t side) {
    if (!pixels || side == 0 || side > 1024) return KERN_INVALID_ARGUMENT;

    mach_port_t dock_port = acquire_dock_server_port();
    if (dock_port == MACH_PORT_NULL) return KERN_FAILURE;

    const uint32_t bytes_per_row = side * 8;
    const uint32_t data_length = side * bytes_per_row;
    const uint32_t bitmap_info = kCGBitmapFloatComponents | kCGBitmapByteOrder16Little | kCGImageAlphaPremultipliedLast; // 0x1101

    DockNativeTileFrameMsg msg;
    memset(&msg, 0, sizeof(msg));
    msg.header.msgh_bits = MACH_MSGH_BITS_COMPLEX | MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
    msg.header.msgh_size = sizeof(DockNativeTileFrameMsg);
    msg.header.msgh_remote_port = dock_port;
    msg.header.msgh_local_port = MACH_PORT_NULL;
    msg.header.msgh_id = 0x1791B;

    msg.body.msgh_descriptor_count = 1;
    msg.pixels.address = (void *)pixels;
    msg.pixels.size = data_length;
    msg.pixels.deallocate = false;
    msg.pixels.copy = MACH_MSG_PHYSICAL_COPY;
    msg.pixels.type = MACH_MSG_OOL_DESCRIPTOR;

    msg.ndr = NDR_record;
    msg.psn_hi = psn.high;
    msg.psn_lo = psn.low;
    msg.flags = 0;
    msg.side = side;
    msg.bytes_per_row = bytes_per_row;
    msg.bitmap_info = bitmap_info;
    msg.data_length = data_length;

    // 16ms budget (1 frame at 60Hz) so a momentary Dock.app stall NEVER freezes the 120Hz HoverTooltipPanel spring!
    kern_return_t kr = mach_msg(
        &msg.header,
        MACH_SEND_MSG | MACH_SEND_TIMEOUT,
        sizeof(DockNativeTileFrameMsg),
        0,
        MACH_PORT_NULL,
        16,
        MACH_PORT_NULL
    );

    if (kr != KERN_SUCCESS && kr != MACH_SEND_TIMED_OUT) {
        invalidate_dock_server_port(dock_port);
    }
    return (int32_t)kr;
}

int32_t native_dock_draw_tile(NativeDockPSN psn, CGImageRef image, uint32_t side) {
    if (!image || side == 0 || side > 1024) return KERN_INVALID_ARGUMENT;

    const uint32_t bytes_per_row = side * 8;
    const uint32_t bitmap_info = kCGBitmapFloatComponents | kCGBitmapByteOrder16Little | kCGImageAlphaPremultipliedLast;

    CGColorSpaceRef color_space = CGColorSpaceCreateWithName(kCGColorSpaceExtendedSRGB);
    if (!color_space) return KERN_FAILURE;

    CGContextRef ctx = CGBitmapContextCreate(NULL, side, side, 16, bytes_per_row, color_space, bitmap_info);
    CGColorSpaceRelease(color_space);
    if (!ctx) return KERN_FAILURE;

    CGContextSetBlendMode(ctx, kCGBlendModeCopy);
    CGContextClearRect(ctx, CGRectMake(0, 0, side, side));
    CGContextDrawImage(ctx, CGRectMake(0, 0, side, side), image);

    void *pixel_data = CGBitmapContextGetData(ctx);
    int32_t kr = pixel_data ? native_dock_draw_half_float_bytes(psn, pixel_data, side) : KERN_FAILURE;
    CGContextRelease(ctx);
    return kr;
}

int32_t native_dock_release_tile(NativeDockPSN psn) {
    kern_return_t kr = KERN_FAILURE;
    for (int attempt = 0; attempt < 3; attempt++) {
        mach_port_t dock_port = acquire_dock_server_port();
        if (dock_port == MACH_PORT_NULL) return KERN_FAILURE;

        DockNativeTileReleaseMsg msg;
        memset(&msg, 0, sizeof(msg));
        msg.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
        msg.header.msgh_size = sizeof(DockNativeTileReleaseMsg);
        msg.header.msgh_remote_port = dock_port;
        msg.header.msgh_local_port = MACH_PORT_NULL;
        msg.header.msgh_id = 0x1791C;

        msg.ndr = NDR_record;
        msg.psn_hi = psn.high;
        msg.psn_lo = psn.low;

        kr = mach_msg(
            &msg.header,
            MACH_SEND_MSG | MACH_SEND_TIMEOUT,
            sizeof(DockNativeTileReleaseMsg),
            0,
            MACH_PORT_NULL,
            24,
            MACH_PORT_NULL
        );
        if (kr == KERN_SUCCESS) break;
        if (kr != MACH_SEND_TIMED_OUT) {
            invalidate_dock_server_port(dock_port);
        }
    }

    return (int32_t)kr;
}
