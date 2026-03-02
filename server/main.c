#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <sqlite3.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/epoll.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#include "server.h"

#define REQ_BUF_SIZE 65536
#define HEADER_BUF_SIZE 2048
#define DEFAULT_WORKERS 64
#define EPOLL_MAX_EVENTS 1024
#define CONN_INIT_BUF 8192

typedef struct {
    int listen_fd;
    char db_path[512];
    size_t max_fds;
} worker_ctx_t;

typedef struct {
    sqlite3 *db;
    sqlite3_stmt *get_stmt;
    sqlite3_stmt *upsert_stmt;
    sqlite3_stmt *json_valid_stmt;
} worker_db_t;

typedef struct {
    int fd;
    size_t len;
    size_t cap;
    char *buf;
} conn_t;

static const char *DATA_KEYS[] = {
    "activities",
    "activity_metric_insights",
    "meal_plans",
    "custom_foods",
    "workouts",
    "events",
    "profile",
    "lactate_history_records",
};
static const size_t DATA_KEYS_COUNT = sizeof(DATA_KEYS) / sizeof(DATA_KEYS[0]);

bool is_valid_key(const char *key) {
    for (size_t i = 0; i < DATA_KEYS_COUNT; i++) {
        if (strcmp(DATA_KEYS[i], key) == 0) {
            return true;
        }
    }
    return false;
}

int parse_bind_addr(const char *bind_addr_str, char *host, size_t host_len, int *port) {
    if (sscanf(bind_addr_str, "%127[^:]:%d", host, port) != 2) {
        return -1;
    }
    if (*port <= 0 || *port > 65535) {
        return -1;
    }
    if (strlen(host) == 0 || strlen(host) >= host_len) {
        return -1;
    }
    return 0;
}

static int tune_fd_limit(void) {
    struct rlimit lim;
    if (getrlimit(RLIMIT_NOFILE, &lim) != 0) {
        return -1;
    }
    rlim_t target = lim.rlim_cur;
    if (target < 200000) {
        target = lim.rlim_max < 200000 ? lim.rlim_max : 200000;
    }
    if (target > lim.rlim_cur) {
        lim.rlim_cur = target;
        if (setrlimit(RLIMIT_NOFILE, &lim) != 0) {
            return -1;
        }
    }
    return 0;
}

static int set_nonblocking(int fd) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0) return -1;
    if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) return -1;
    return 0;
}

static int init_db(const char *db_path) {
    sqlite3 *db = NULL;
    if (sqlite3_open_v2(db_path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, NULL) != SQLITE_OK) {
        fprintf(stderr, "failed to open db: %s\n", sqlite3_errmsg(db));
        if (db) sqlite3_close(db);
        return -1;
    }

    const char *schema_sql =
        "PRAGMA journal_mode=WAL;"
        "PRAGMA synchronous=NORMAL;"
        "PRAGMA temp_store=MEMORY;"
        "PRAGMA mmap_size=268435456;"
        "CREATE TABLE IF NOT EXISTS kv_store ("
        "data_key TEXT PRIMARY KEY,"
        "data_value TEXT NOT NULL,"
        "updated_at INTEGER NOT NULL"
        ");";

    char *err = NULL;
    if (sqlite3_exec(db, schema_sql, NULL, NULL, &err) != SQLITE_OK) {
        fprintf(stderr, "failed to init schema: %s\n", err ? err : "unknown");
        sqlite3_free(err);
        sqlite3_close(db);
        return -1;
    }

    sqlite3_stmt *stmt = NULL;
    const char *upsert =
        "INSERT OR IGNORE INTO kv_store (data_key, data_value, updated_at) VALUES (?1, ?2, strftime('%s', 'now'));";
    if (sqlite3_prepare_v2(db, upsert, -1, &stmt, NULL) != SQLITE_OK) {
        fprintf(stderr, "failed to prepare init insert: %s\n", sqlite3_errmsg(db));
        sqlite3_close(db);
        return -1;
    }

    for (size_t i = 0; i < DATA_KEYS_COUNT; i++) {
        const char *default_json = strcmp(DATA_KEYS[i], "profile") == 0 ? "{}" : "[]";
        sqlite3_bind_text(stmt, 1, DATA_KEYS[i], -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 2, default_json, -1, SQLITE_STATIC);
        if (sqlite3_step(stmt) != SQLITE_DONE) {
            fprintf(stderr, "failed to seed key %s: %s\n", DATA_KEYS[i], sqlite3_errmsg(db));
            sqlite3_finalize(stmt);
            sqlite3_close(db);
            return -1;
        }
        sqlite3_reset(stmt);
        sqlite3_clear_bindings(stmt);
    }

    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return 0;
}

static int send_all(int fd, const char *buf, size_t len) {
    size_t sent = 0;
    int retry = 0;
    while (sent < len) {
        ssize_t n = send(fd, buf + sent, len - sent, MSG_NOSIGNAL);
        if (n > 0) {
            sent += (size_t)n;
            continue;
        }
        if (n < 0 && (errno == EINTR)) continue;
        if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) && retry < 4) {
            retry++;
            struct timespec ts = {.tv_sec = 0, .tv_nsec = 50000};
            nanosleep(&ts, NULL);
            continue;
        }
        return -1;
    }
    return 0;
}

static void send_response(int fd, int code, const char *status, const char *body) {
    size_t body_len = body ? strlen(body) : 0;
    char header[HEADER_BUF_SIZE];
    int header_len = snprintf(
        header,
        sizeof(header),
        "HTTP/1.1 %d %s\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: %zu\r\n"
        "Connection: close\r\n\r\n",
        code,
        status,
        body_len);
    if (header_len > 0) {
        send_all(fd, header, (size_t)header_len);
    }
    if (body_len > 0) {
        send_all(fd, body, body_len);
    }
}

static int json_is_valid(worker_db_t *db, const char *json) {
    sqlite3_stmt *stmt = db->json_valid_stmt;
    if (!stmt) return 0;
    sqlite3_reset(stmt);
    sqlite3_clear_bindings(stmt);
    sqlite3_bind_text(stmt, 1, json, -1, SQLITE_TRANSIENT);
    int ok = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) ok = sqlite3_column_int(stmt, 0);
    return ok;
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

static void handle_get_data(int fd, worker_db_t *db, const char *key) {
    sqlite3_stmt *stmt = db->get_stmt;
    if (!stmt) {
        send_response(fd, 500, "Internal Server Error", "{\"error\":\"database error\"}");
        return;
    }

    sqlite3_reset(stmt);
    sqlite3_clear_bindings(stmt);
    sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT);
    int rc = sqlite3_step(stmt);
    if (rc == SQLITE_ROW) {
        const unsigned char *value = sqlite3_column_text(stmt, 0);
        send_response(fd, 200, "OK", (const char *)value);
    } else {
        const char *default_json = strcmp(key, "profile") == 0 ? "{}" : "[]";
        send_response(fd, 200, "OK", default_json);
    }
}

static void handle_put_data(int fd, worker_db_t *db, const char *key, const char *payload) {
    if (!json_is_valid(db, payload)) {
        send_response(fd, 400, "Bad Request", "{\"error\":\"invalid json payload\"}");
        return;
    }

    sqlite3_stmt *stmt = db->upsert_stmt;
    if (!stmt) {
        send_response(fd, 500, "Internal Server Error", "{\"error\":\"database error\"}");
        return;
    }

    sqlite3_reset(stmt);
    sqlite3_clear_bindings(stmt);
    sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, payload, -1, SQLITE_TRANSIENT);
    if (sqlite3_step(stmt) != SQLITE_DONE) {
        send_response(fd, 500, "Internal Server Error", "{\"error\":\"database error\"}");
        return;
    }

    send_response(fd, 204, "No Content", "");
}

static int try_process_client(int fd, worker_db_t *db, conn_t *conn) {
    conn->buf[conn->len] = '\0';
    char *header_end = strstr(conn->buf, "\r\n\r\n");
    if (!header_end) return 0;

    size_t header_len = (size_t)(header_end - conn->buf) + 4;
    char method[8] = {0};
    char path[512] = {0};
    if (sscanf(conn->buf, "%7s %511s", method, path) != 2) {
        send_response(fd, 400, "Bad Request", "{\"error\":\"malformed request line\"}");
        return 1;
    }

    if (strcmp(path, "/health") == 0 && strcmp(method, "GET") == 0) {
        send_response(fd, 200, "OK", "{\"status\":\"ok\"}");
        return 1;
    }

    const char *prefix = "/v1/data/";
    if (strncmp(path, prefix, strlen(prefix)) != 0) {
        send_response(fd, 404, "Not Found", "{\"error\":\"not found\"}");
        return 1;
    }

    const char *key = path + strlen(prefix);
    if (!is_valid_key(key)) {
        send_response(fd, 404, "Not Found", "{\"error\":\"unknown key\"}");
        return 1;
    }

    if (strcmp(method, "GET") == 0) {
        handle_get_data(fd, db, key);
        return 1;
    }

    if (strcmp(method, "PUT") == 0) {
        int content_length = read_content_length(conn->buf, header_end);
        if (content_length < 0 || (size_t)content_length > REQ_BUF_SIZE - header_len) {
            send_response(fd, 400, "Bad Request", "{\"error\":\"invalid content length\"}");
            return 1;
        }
        if ((size_t)content_length > conn->len - header_len) {
            return 0;
        }

        char *body = conn->buf + header_len;
        body[content_length] = '\0';
        handle_put_data(fd, db, key, body);
        return 1;
    }

    send_response(fd, 405, "Method Not Allowed", "{\"error\":\"method not allowed\"}");
    return 1;
}

static void close_conn(int epfd, conn_t **conns, int fd) {
    if (fd < 0) return;
    epoll_ctl(epfd, EPOLL_CTL_DEL, fd, NULL);
    if (conns[fd]) {
        free(conns[fd]->buf);
        free(conns[fd]);
        conns[fd] = NULL;
    }
    close(fd);
}

static void *worker_loop(void *arg) {
    worker_ctx_t *ctx = (worker_ctx_t *)arg;
    worker_db_t worker_db = {0};

    if (sqlite3_open_v2(ctx->db_path, &worker_db.db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, NULL) != SQLITE_OK) {
        fprintf(stderr, "worker failed to open db: %s\n", sqlite3_errmsg(worker_db.db));
        if (worker_db.db) sqlite3_close(worker_db.db);
        return NULL;
    }

    sqlite3_exec(worker_db.db, "PRAGMA busy_timeout=5000;", NULL, NULL, NULL);
    sqlite3_exec(worker_db.db, "PRAGMA synchronous=NORMAL;", NULL, NULL, NULL);
    sqlite3_exec(worker_db.db, "PRAGMA temp_store=MEMORY;", NULL, NULL, NULL);
    sqlite3_exec(worker_db.db, "PRAGMA mmap_size=268435456;", NULL, NULL, NULL);
    sqlite3_exec(worker_db.db, "PRAGMA cache_size=-32768;", NULL, NULL, NULL);

    if (sqlite3_prepare_v2(worker_db.db, "SELECT data_value FROM kv_store WHERE data_key=?1", -1, &worker_db.get_stmt, NULL) != SQLITE_OK ||
        sqlite3_prepare_v2(worker_db.db,
                           "INSERT INTO kv_store (data_key, data_value, updated_at) VALUES (?1, ?2, strftime('%s', 'now'))"
                           " ON CONFLICT(data_key) DO UPDATE SET data_value=excluded.data_value, updated_at=excluded.updated_at",
                           -1,
                           &worker_db.upsert_stmt,
                           NULL) != SQLITE_OK ||
        sqlite3_prepare_v2(worker_db.db, "SELECT json_valid(?1)", -1, &worker_db.json_valid_stmt, NULL) != SQLITE_OK) {
        fprintf(stderr, "worker failed to prepare statements: %s\n", sqlite3_errmsg(worker_db.db));
        sqlite3_finalize(worker_db.get_stmt);
        sqlite3_finalize(worker_db.upsert_stmt);
        sqlite3_finalize(worker_db.json_valid_stmt);
        sqlite3_close(worker_db.db);
        return NULL;
    }

    int epfd = epoll_create1(0);
    if (epfd < 0) {
        perror("epoll_create1");
        sqlite3_finalize(worker_db.get_stmt);
        sqlite3_finalize(worker_db.upsert_stmt);
        sqlite3_finalize(worker_db.json_valid_stmt);
        sqlite3_close(worker_db.db);
        return NULL;
    }

    conn_t **conns = (conn_t **)calloc(ctx->max_fds + 1, sizeof(conn_t *));
    if (!conns) {
        close(epfd);
        sqlite3_finalize(worker_db.get_stmt);
        sqlite3_finalize(worker_db.upsert_stmt);
        sqlite3_finalize(worker_db.json_valid_stmt);
        sqlite3_close(worker_db.db);
        return NULL;
    }

    struct epoll_event ev;
    memset(&ev, 0, sizeof(ev));
    ev.events = EPOLLIN;
#ifdef EPOLLEXCLUSIVE
    ev.events |= EPOLLEXCLUSIVE;
#endif
    ev.data.fd = ctx->listen_fd;
    if (epoll_ctl(epfd, EPOLL_CTL_ADD, ctx->listen_fd, &ev) < 0) {
        perror("epoll_ctl listen");
        free(conns);
        close(epfd);
        sqlite3_finalize(worker_db.get_stmt);
        sqlite3_finalize(worker_db.upsert_stmt);
        sqlite3_finalize(worker_db.json_valid_stmt);
        sqlite3_close(worker_db.db);
        return NULL;
    }

    struct epoll_event events[EPOLL_MAX_EVENTS];
    while (1) {
        int n = epoll_wait(epfd, events, EPOLL_MAX_EVENTS, -1);
        if (n < 0) {
            if (errno == EINTR) continue;
            perror("epoll_wait");
            continue;
        }

        for (int i = 0; i < n; i++) {
            int fd = events[i].data.fd;
            if (fd == ctx->listen_fd) {
                while (1) {
                    int client_fd = accept4(ctx->listen_fd, NULL, NULL, SOCK_NONBLOCK | SOCK_CLOEXEC);
                    if (client_fd < 0 && (errno == ENOSYS || errno == EINVAL)) {
                        client_fd = accept(ctx->listen_fd, NULL, NULL);
                        if (client_fd >= 0) set_nonblocking(client_fd);
                    }
                    if (client_fd < 0) {
                        if (errno == EAGAIN || errno == EWOULDBLOCK) break;
                        if (errno == EINTR) continue;
                        break;
                    }

                    if ((size_t)client_fd > ctx->max_fds) {
                        close(client_fd);
                        continue;
                    }

                    int nodelay = 1;
                    setsockopt(client_fd, IPPROTO_TCP, TCP_NODELAY, &nodelay, sizeof(nodelay));

                    conn_t *conn = (conn_t *)calloc(1, sizeof(conn_t));
                    if (!conn) {
                        close(client_fd);
                        continue;
                    }
                    conn->cap = CONN_INIT_BUF;
                    conn->buf = (char *)malloc(conn->cap + 1);
                    if (!conn->buf) {
                        free(conn);
                        close(client_fd);
                        continue;
                    }
                    conn->fd = client_fd;
                    conns[client_fd] = conn;

                    struct epoll_event cev;
                    memset(&cev, 0, sizeof(cev));
                    cev.events = EPOLLIN | EPOLLRDHUP;
                    cev.data.fd = client_fd;
                    if (epoll_ctl(epfd, EPOLL_CTL_ADD, client_fd, &cev) < 0) {
                        close_conn(epfd, conns, client_fd);
                    }
                }
                continue;
            }

            if ((events[i].events & (EPOLLERR | EPOLLHUP | EPOLLRDHUP)) != 0) {
                close_conn(epfd, conns, fd);
                continue;
            }

            conn_t *conn = (fd >= 0 && (size_t)fd <= ctx->max_fds) ? conns[fd] : NULL;
            if (!conn) {
                close(fd);
                continue;
            }

            while (1) {
                if (conn->len == conn->cap && conn->cap < REQ_BUF_SIZE) {
                    size_t next = conn->cap * 2;
                    if (next > REQ_BUF_SIZE) next = REQ_BUF_SIZE;
                    char *nb = (char *)realloc(conn->buf, next + 1);
                    if (!nb) {
                        send_response(fd, 500, "Internal Server Error", "{\"error\":\"oom\"}");
                        close_conn(epfd, conns, fd);
                        break;
                    }
                    conn->buf = nb;
                    conn->cap = next;
                }

                ssize_t r = recv(fd, conn->buf + conn->len, conn->cap - conn->len, 0);
                if (r > 0) {
                    conn->len += (size_t)r;
                    if (conn->len >= REQ_BUF_SIZE) {
                        send_response(fd, 413, "Payload Too Large", "{\"error\":\"request too large\"}");
                        close_conn(epfd, conns, fd);
                        break;
                    }

                    int done = try_process_client(fd, &worker_db, conn);
                    if (done == 1) {
                        close_conn(epfd, conns, fd);
                        break;
                    }
                    continue;
                }

                if (r == 0) {
                    close_conn(epfd, conns, fd);
                    break;
                }

                if (errno == EAGAIN || errno == EWOULDBLOCK) {
                    break;
                }
                if (errno == EINTR) {
                    continue;
                }
                close_conn(epfd, conns, fd);
                break;
            }
        }
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

    tune_fd_limit();

    if (init_db(db_path) != 0) return 1;

    char host[128] = {0};
    int port = 8080;
    if (parse_bind_addr(bind_addr_str, host, sizeof(host), &port) != 0) {
        fprintf(stderr, "invalid FRICU_SERVER_BIND: %s\n", bind_addr_str);
        return 1;
    }

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) {
        perror("socket");
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
        perror("set_nonblocking");
        close(server_fd);
        return 1;
    }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, host, &addr.sin_addr) <= 0) {
        fprintf(stderr, "invalid bind host: %s\n", host);
        close(server_fd);
        return 1;
    }

    if (bind(server_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("bind");
        close(server_fd);
        return 1;
    }

    if (listen(server_fd, 65535) < 0) {
        perror("listen");
        close(server_fd);
        return 1;
    }

    struct rlimit lim;
    getrlimit(RLIMIT_NOFILE, &lim);
    size_t max_fds = (size_t)lim.rlim_cur;

    worker_ctx_t *workers = (worker_ctx_t *)calloc(worker_count, sizeof(worker_ctx_t));
    pthread_t *threads = (pthread_t *)calloc(worker_count, sizeof(pthread_t));
    if (!workers || !threads) {
        fprintf(stderr, "failed to allocate workers\n");
        close(server_fd);
        return 1;
    }

    for (size_t i = 0; i < worker_count; i++) {
        workers[i].listen_fd = server_fd;
        workers[i].max_fds = max_fds;
        strncpy(workers[i].db_path, db_path, sizeof(workers[i].db_path) - 1);
        workers[i].db_path[sizeof(workers[i].db_path) - 1] = '\0';
        if (pthread_create(&threads[i], NULL, worker_loop, &workers[i]) != 0) {
            fprintf(stderr, "failed to start worker %zu\n", i);
            close(server_fd);
            return 1;
        }
    }

    printf("fricu-server listening on %s (workers=%zu async_io=epoll)\n", bind_addr_str, worker_count);

    for (size_t i = 0; i < worker_count; i++) {
        pthread_join(threads[i], NULL);
    }

    close(server_fd);
    return 0;
}

#endif
