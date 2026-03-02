#include "server.h"
#include "server_internal.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/resource.h>

const char *DATA_KEYS[] = {
    "activities",
    "activity_metric_insights",
    "meal_plans",
    "custom_foods",
    "workouts",
    "events",
    "profile",
    "lactate_history_records",
};
const size_t DATA_KEYS_COUNT = sizeof(DATA_KEYS) / sizeof(DATA_KEYS[0]);

bool is_valid_key(const char *key) {
    for (size_t i = 0; i < DATA_KEYS_COUNT; i++) {
        if (strcmp(DATA_KEYS[i], key) == 0) return true;
    }
    return false;
}

int parse_bind_addr(const char *bind_addr_str, char *host, size_t host_len, int *port) {
    if (sscanf(bind_addr_str, "%127[^:]:%d", host, port) != 2) return -1;
    if (*port <= 0 || *port > 65535) return -1;
    if (strlen(host) == 0 || strlen(host) >= host_len) return -1;
    return 0;
}

int read_content_length(const char *req, const char *header_end) {
    int content_length = 0;
    char *line = strstr(req, "\r\n");
    line = line ? line + 2 : NULL;
    while (line && line < header_end) {
        char *line_end = strstr(line, "\r\n");
        if (!line_end || line_end > header_end) break;
        size_t len = (size_t)(line_end - line);
        if (len >= strlen("Content-Length:") && strncasecmp(line, "Content-Length:", strlen("Content-Length:")) == 0) {
            content_length = atoi(line + strlen("Content-Length:"));
            break;
        }
        line = line_end + 2;
    }
    return content_length;
}

int tune_fd_limit(void) {
    struct rlimit lim;
    if (getrlimit(RLIMIT_NOFILE, &lim) != 0) return -1;
    rlim_t target = lim.rlim_cur;
    if (target < 200000) target = lim.rlim_max < 200000 ? lim.rlim_max : 200000;
    if (target > lim.rlim_cur) {
        lim.rlim_cur = target;
        if (setrlimit(RLIMIT_NOFILE, &lim) != 0) return -1;
    }
    return 0;
}

int set_nonblocking(int fd) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0) return -1;
    if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) return -1;
    return 0;
}
