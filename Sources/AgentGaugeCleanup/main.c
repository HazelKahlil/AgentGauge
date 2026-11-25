#include "NativeDockTile.h"
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct {
    uint32_t op; // 1 = add, 2 = remove, 3 = clear all
    uint32_t high;
    uint32_t low;
} WatchCmd;

int main(int argc, char **argv) {
    // Kernel-atomic APFS directory swap helper for zero-downtime OTA/installer upgrades & rollback.
    if (argc == 4 && strcmp(argv[1], "--atomic-swap") == 0) {
        if (renamex_np(argv[2], argv[3], RENAME_SWAP) == 0) {
            return 0;
        }
        fprintf(stderr, "renamex_np swap failed: %s\n", strerror(errno));
        return 1;
    }

    NativeDockPSN active[64];
    int count = 0;

    WatchCmd cmd;
    while (1) {
        ssize_t n = read(STDIN_FILENO, &cmd, sizeof(cmd));
        if (n <= 0) {
            // Parent exited or crashed -> release every tracked PSN immediately!
            break;
        }
        if ((size_t)n != sizeof(cmd)) continue;

        if (cmd.op == 1) {
            int exists = 0;
            for (int i = 0; i < count; i++) {
                if (active[i].high == cmd.high && active[i].low == cmd.low) {
                    exists = 1;
                    break;
                }
            }
            if (!exists && count < 64) {
                active[count].high = cmd.high;
                active[count].low = cmd.low;
                count++;
            }
        } else if (cmd.op == 2) {
            for (int i = 0; i < count; i++) {
                if (active[i].high == cmd.high && active[i].low == cmd.low) {
                    active[i] = active[count - 1];
                    count--;
                    break;
                }
            }
        } else if (cmd.op == 3) {
            count = 0;
        }
    }

    for (int i = 0; i < count; i++) {
        native_dock_release_tile(active[i]);
    }
    return 0;
}
