#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#include "logger.h"
#include "server.h"
#include "server_internal.h"

typedef struct {
    int listen_fd;
    char db_path[512];
    size_t max_fds;
} worker_ctx_t;

static void *worker_entry(void *arg) {
    worker_ctx_t *ctx = (worker_ctx_t *)arg;
    if (run_worker_loop(ctx->listen_fd, ctx->db_path, ctx->max_fds) != 0) {
        log_error("worker loop exited with error");
    }
    return NULL;
}

#ifndef FRICU_UNIT_TEST
int main(void) {
    const char *bind_env = getenv("FRICU_SERVER_BIND");
    const char *db_env = getenv("FRICU_DB_PATH");
    const char *workers_env = getenv("FRICU_SERVER_WORKERS");
    const char *bind_addr_str = bind_env ? bind_env : "0.0.0.0:8080";
    const char *db_path = db_env ? db_env : "fricu_server.db";

    size_t worker_count = workers_env ? (size_t)strtoul(workers_env, NULL, 10) : DEFAULT_WORKERS;
    if (worker_count == 0 || worker_count > 1024) worker_count = DEFAULT_WORKERS;

    if (tune_fd_limit() != 0) {
        log_warn("failed to tune fd limit, continuing");
    }

    if (init_db(db_path) != 0) return 1;

    char host[128] = {0};
    int port = 8080;
    if (parse_bind_addr(bind_addr_str, host, sizeof(host), &port) != 0) {
        log_error("invalid FRICU_SERVER_BIND: %s", bind_addr_str);
        return 1;
    }

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) {
        log_error("socket creation failed: errno=%d", errno);
        return 1;
    }

    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
#ifdef SO_REUSEPORT
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEPORT, &opt, sizeof(opt));
#endif

    int backlog = 65535;
    setsockopt(server_fd, SOL_SOCKET, SO_RCVBUF, &backlog, sizeof(backlog));
    setsockopt(server_fd, SOL_SOCKET, SO_SNDBUF, &backlog, sizeof(backlog));

    if (set_nonblocking(server_fd) != 0) {
        log_error("set_nonblocking failed: errno=%d", errno);
        close(server_fd);
        return 1;
    }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, host, &addr.sin_addr) <= 0) {
        log_error("invalid bind host: %s", host);
        close(server_fd);
        return 1;
    }

    if (bind(server_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        log_error("bind failed: errno=%d", errno);
        close(server_fd);
        return 1;
    }

    if (listen(server_fd, 65535) < 0) {
        log_error("listen failed: errno=%d", errno);
        close(server_fd);
        return 1;
    }

    struct rlimit lim;
    if (getrlimit(RLIMIT_NOFILE, &lim) != 0) {
        log_warn("getrlimit failed, using fallback max_fds");
        lim.rlim_cur = 65535;
    }
    size_t max_fds = (size_t)lim.rlim_cur;

    worker_ctx_t *workers = (worker_ctx_t *)calloc(worker_count, sizeof(worker_ctx_t));
    pthread_t *threads = (pthread_t *)calloc(worker_count, sizeof(pthread_t));
    if (!workers || !threads) {
        log_error("failed to allocate worker structures");
        close(server_fd);
        free(workers);
        free(threads);
        return 1;
    }

    for (size_t i = 0; i < worker_count; i++) {
        workers[i].listen_fd = server_fd;
        workers[i].max_fds = max_fds;
        strncpy(workers[i].db_path, db_path, sizeof(workers[i].db_path) - 1);
        workers[i].db_path[sizeof(workers[i].db_path) - 1] = '\0';
        if (pthread_create(&threads[i], NULL, worker_entry, &workers[i]) != 0) {
            log_error("failed to start worker %zu", i);
            close(server_fd);
            free(workers);
            free(threads);
            return 1;
        }
    }

    log_info("fricu-server listening on %s (workers=%zu, async_io=auto)", bind_addr_str, worker_count);

    for (size_t i = 0; i < worker_count; i++) {
        pthread_join(threads[i], NULL);
    }

    close(server_fd);
    free(workers);
    free(threads);
    return 0;
}

#endif
