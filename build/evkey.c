/* evkey - print input events from Linux input devices as text lines:
 *
 *   A <xmax> <ymax>   once at startup, if a touch device is present
 *   K <code>          for every key-down event
 *   T <x> <y>         for every completed tap (at touch release)
 *
 * PaperTerminal's navigation uses this on keyboard Kindles (K3, whose
 * busybox lacks od/hexdump for shell event parsing) and on touch-only
 * Kindles (Basic/KT2 and later, which have no hardware keys at all).
 * Handles both single-touch (ABS_X/Y + BTN_TOUCH) and multitouch
 * (ABS_MT_POSITION_* + tracking id) protocols.
 *
 * usage: evkey /dev/input/event0 [/dev/input/event1 ...]
 * Build (static, ARMv5 musl - see build-https-stack.sh for the toolchain):
 *   arm-buildroot-linux-musleabi-gcc -Os -static -no-pie -o evkey evkey.c
 */
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

struct input_event_32 {
    uint32_t sec;
    uint32_t usec;
    uint16_t type;
    uint16_t code;
    int32_t value;
};

int main(int argc, char **argv)
{
    struct pollfd pfd[8];
    int n = 0;
    int xmax = 0, ymax = 0;

    for (int i = 1; i < argc && n < 8; i++) {
        int fd = open(argv[i], O_RDONLY);
        if (fd < 0)
            continue;
        struct input_absinfo ai;
        if (!ioctl(fd, EVIOCGABS(ABS_X), &ai) && ai.maximum > xmax)
            xmax = ai.maximum;
        if (!ioctl(fd, EVIOCGABS(ABS_Y), &ai) && ai.maximum > ymax)
            ymax = ai.maximum;
        if (!ioctl(fd, EVIOCGABS(ABS_MT_POSITION_X), &ai) && ai.maximum > xmax)
            xmax = ai.maximum;
        if (!ioctl(fd, EVIOCGABS(ABS_MT_POSITION_Y), &ai) && ai.maximum > ymax)
            ymax = ai.maximum;
        pfd[n].fd = fd;
        pfd[n].events = POLLIN;
        n++;
    }
    if (n == 0)
        return 1;

    setvbuf(stdout, NULL, _IOLBF, 0);
    if (xmax > 0 && ymax > 0)
        printf("A %d %d\n", xmax, ymax);

    int x = -1, y = -1, touched = 0;
    for (;;) {
        if (poll(pfd, n, -1) <= 0)
            continue;
        for (int i = 0; i < n; i++) {
            if (!(pfd[i].revents & POLLIN))
                continue;
            struct input_event_32 e;
            if (read(pfd[i].fd, &e, sizeof(e)) != (ssize_t)sizeof(e))
                continue;
            if (e.type == EV_ABS) {
                switch (e.code) {
                case ABS_X:
                case ABS_MT_POSITION_X:
                    x = e.value;
                    touched = 1;
                    break;
                case ABS_Y:
                case ABS_MT_POSITION_Y:
                    y = e.value;
                    touched = 1;
                    break;
                case ABS_MT_TRACKING_ID:
                    /* MT release; BTN_TOUCH release (below) is a no-op
                     * afterwards because touched is cleared here. */
                    if (e.value == -1 && touched && x >= 0 && y >= 0) {
                        printf("T %d %d\n", x, y);
                        touched = 0;
                    }
                    break;
                }
            } else if (e.type == EV_KEY) {
                if (e.code == BTN_TOUCH) {
                    if (e.value == 1) {
                        touched = 1;
                    } else if (e.value == 0 && touched && x >= 0 && y >= 0) {
                        printf("T %d %d\n", x, y);
                        touched = 0;
                    }
                } else if (e.value == 1) {
                    printf("K %u\n", (unsigned)e.code);
                }
            }
        }
    }
}
