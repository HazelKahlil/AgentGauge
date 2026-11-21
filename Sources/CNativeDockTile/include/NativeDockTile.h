#ifndef NATIVE_DOCK_TILE_H
#define NATIVE_DOCK_TILE_H

#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <stdint.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint32_t high;
    uint32_t low;
} NativeDockPSN;

/// Looks up the ProcessSerialNumber for a running macOS process PID.
bool native_dock_get_psn_for_pid(pid_t pid, NativeDockPSN *out_psn);

/// Sends pre-rendered half-float RGBA pixels (16bpc, 8 bytes/pixel, 0x1101) directly to com.apple.dock.server (0x1791B).
/// Zero allocations and zero CPU color conversion.
int32_t native_dock_draw_half_float_bytes(NativeDockPSN psn, const void *pixels, uint32_t side);

/// Sends a CGImage by converting to half-float RGBA on CPU and submitting to com.apple.dock.server (0x1791B).
int32_t native_dock_draw_tile(NativeDockPSN psn, CGImageRef image, uint32_t side);

/// Releases any native tile override for the given PSN (0x1791C), restoring the app's original Dock icon.
int32_t native_dock_release_tile(NativeDockPSN psn);

#ifdef __cplusplus
}
#endif

#endif /* NATIVE_DOCK_TILE_H */
