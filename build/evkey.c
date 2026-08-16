/* evkey - print keycodes of key-down events from Linux input devices,
 * one decimal per line. PaperTerminal's navigation uses this because the
 * Kindle 3's busybox lacks od/hexdump, so binary event parsing in shell
 * is impossible there.
 *
 * usage: evkey /dev/input/event0 [/dev/input/event1 ...]
 * Build (static, ARMv5 musl - see build-https-stack.sh for the toolchain):
 *   arm-buildroot-linux-musleabi-gcc -Os -static -no-pie -o evkey evkey.c
 */
#include <fcntl.h>
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

    for (int i = 1; i < argc && n < 8; i++) {
        int fd = open(argv[i], O_RDONLY);
        if (fd >= 0) {
            pfd[n].fd = fd;
            pfd[n].events = POLLIN;
            n++;
        }
    }
    if (n == 0)
        return 1;

    setvbuf(stdout, NULL, _IOLBF, 0);
    for (;;) {
        if (poll(pfd, n, -1) <= 0)
            continue;
        for (int i = 0; i < n; i++) {
            if (!(pfd[i].revents & POLLIN))
                continue;
            struct input_event_32 e;
            if (read(pfd[i].fd, &e, sizeof(e)) == (ssize_t)sizeof(e)
                && e.type == 1 /* EV_KEY */ && e.value == 1 /* down */)
                printf("%u\n", (unsigned)e.code);
        }
    }
}
