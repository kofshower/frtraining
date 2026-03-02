#include "logger.h"

#include <stdarg.h>
#include <stdio.h>
#include <time.h>

static void log_v(const char *level, const char *fmt, va_list ap) {
    time_t now = time(NULL);
    struct tm tm_now;
#if defined(__APPLE__) || defined(__linux__)
    localtime_r(&now, &tm_now);
#else
    struct tm *tmp = localtime(&now);
    if (!tmp) return;
    tm_now = *tmp;
#endif

    char ts[32];
    if (strftime(ts, sizeof(ts), "%Y-%m-%d %H:%M:%S", &tm_now) == 0) {
        ts[0] = '\0';
    }

    fprintf(stderr, "[%s] [%s] ", ts, level);
    vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
}

void log_info(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    log_v("INFO", fmt, ap);
    va_end(ap);
}

void log_warn(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    log_v("WARN", fmt, ap);
    va_end(ap);
}

void log_error(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    log_v("ERROR", fmt, ap);
    va_end(ap);
}
