/*
 * RescueX v3.5.9-r1 optional native watchdog launcher.
 *
 * This binary deliberately owns only elapsed-time measurement and PID lifecycle.
 * All policy, health checks, rescue decisions and Android root operations remain
 * in watchdog.sh / common.sh. At deadline it execs watchdog.sh --trigger, so
 * Shell remains the authoritative, auditable fallback.
 */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#ifndef O_CLOEXEC
#define O_CLOEXEC 0
#endif

#ifndef SIGHUP
#define SIGHUP 1
#endif

#ifdef __ANDROID__
#define rx_fsync(fd) fsync(fd)
#define rx_fchmod(fd, mode) fchmod((fd), (mode))
#else
#define rx_fsync(fd) 0
#define rx_fchmod(fd, mode) 0
#endif

static volatile sig_atomic_t g_stop = 0;
static char g_pid_path[512];

static void on_signal(int ignored) { (void)ignored; g_stop = 1; }

static int write_pid_file(const char *path) {
    int fd;
    char buf[64];
    int n;
    if (!path || strlen(path) >= sizeof(g_pid_path)) return -1;
    strncpy(g_pid_path, path, sizeof(g_pid_path) - 1);
    fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    if (fd < 0) return -1;
    n = snprintf(buf, sizeof(buf), "%ld\n", (long)getpid());
    if (n <= 0 || write(fd, buf, (size_t)n) != n || rx_fsync(fd) != 0) {
        close(fd); unlink(path); return -1;
    }
    if (rx_fchmod(fd, 0600) != 0) { close(fd); unlink(path); return -1; }
    return close(fd);
}

static void cleanup_pid_file(void) {
    if (g_pid_path[0]) unlink(g_pid_path);
}

static int parse_timeout(const char *text, long *out) {
    char *end = NULL;
    long value;
    if (!text || !*text) return -1;
    errno = 0;
    value = strtol(text, &end, 10);
    if (errno || !end || *end || value < 10 || value > 1800) return -1;
    *out = value;
    return 0;
}

static long elapsed_ms(const struct timespec *start, const struct timespec *now) {
    return (now->tv_sec - start->tv_sec) * 1000L +
           (now->tv_nsec - start->tv_nsec) / 1000000L;
}

int main(int argc, char **argv) {
    long timeout_sec, timeout_ms;
    struct timespec start, now, pause = { .tv_sec = 0, .tv_nsec = 250000000L };
    if (argc == 2 && strcmp(argv[1], "--self-test") == 0) return 0;
    if (argc != 4 || parse_timeout(argv[1], &timeout_sec) != 0) {
        fprintf(stderr, "usage: %s <10..1800 timeout sec> <watchdog.sh> <pid file>\n", argv[0]);
        return 64;
    }
    if (access(argv[2], R_OK) != 0) return 66;
    if (write_pid_file(argv[3]) != 0) return 73;
    atexit(cleanup_pid_file);
    signal(SIGTERM, on_signal); signal(SIGINT, on_signal); signal(SIGHUP, on_signal);
    if (clock_gettime(CLOCK_MONOTONIC, &start) != 0) return 74;
    timeout_ms = timeout_sec * 1000L;
    while (!g_stop) {
        if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return 74;
        if (elapsed_ms(&start, &now) >= timeout_ms) break;
        while (nanosleep(&pause, &pause) != 0 && errno == EINTR && !g_stop) {}
        pause.tv_sec = 0; pause.tv_nsec = 250000000L;
    }
    if (g_stop) return 0;
    /* Keep the same PID across the hand-off for stop_watchdog verification. */
    execl("/system/bin/sh", "sh", argv[2], "--trigger", (char *)NULL);
    return 127;
}
