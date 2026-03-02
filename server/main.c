#include <arpa/inet.h>
#include <errno.h>
#include <limits.h>
#include <netinet/in.h>
#include <pthread.h>
#include <sqlite3.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <unistd.h>

#include "server.h"

#define REQ_BUF_SIZE 65536
#define HEADER_BUF_SIZE 2048
#define DEFAULT_QUEUE_CAPACITY 65536
#define DEFAULT_WORKERS 64

typedef struct {
    int *fds;
    size_t head;
    size_t tail;
    size_t size;
    size_t capacity;
    pthread_mutex_t mutex;
    pthread_cond_t not_empty;
    pthread_cond_t not_full;
} fd_queue_t;

typedef struct {
    fd_queue_t *queue;
    char db_path[512];
} worker_ctx_t;

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

static int fd_queue_init(fd_queue_t *q, size_t capacity) {
    q->fds = (int *)calloc(capacity, sizeof(int));
    if (!q->fds) return -1;
    q->capacity = capacity;
    q->head = q->tail = q->size = 0;
    if (pthread_mutex_init(&q->mutex, NULL) != 0) return -1;
    if (pthread_cond_init(&q->not_empty, NULL) != 0) return -1;
    if (pthread_cond_init(&q->not_full, NULL) != 0) return -1;
    return 0;
}

static void fd_queue_push(fd_queue_t *q, int fd) {
    pthread_mutex_lock(&q->mutex);
    while (q->size == q->capacity) {
        pthread_cond_wait(&q->not_full, &q->mutex);
    }
    q->fds[q->tail] = fd;
    q->tail = (q->tail + 1) % q->capacity;
    q->size++;
    pthread_cond_signal(&q->not_empty);
    pthread_mutex_unlock(&q->mutex);
}

static int fd_queue_pop(fd_queue_t *q) {
    pthread_mutex_lock(&q->mutex);
    while (q->size == 0) {
        pthread_cond_wait(&q->not_empty, &q->mutex);
    }
    int fd = q->fds[q->head];
    q->head = (q->head + 1) % q->capacity;
    q->size--;
    pthread_cond_signal(&q->not_full);
    pthread_mutex_unlock(&q->mutex);
    return fd;
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
    send(fd, header, (size_t)header_len, 0);
    if (body_len > 0) send(fd, body, body_len, 0);
}

static int json_is_valid(sqlite3 *db, const char *json) {
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, "SELECT json_valid(?1)", -1, &stmt, NULL) != SQLITE_OK) return 0;
    sqlite3_bind_text(stmt, 1, json, -1, SQLITE_TRANSIENT);
    int ok = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) ok = sqlite3_column_int(stmt, 0);
    sqlite3_finalize(stmt);
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

static void handle_get_data(int fd, sqlite3 *db, const char *key) {
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, "SELECT data_value FROM kv_store WHERE data_key=?1", -1, &stmt, NULL) != SQLITE_OK) {
        send_response(fd, 500, "Internal Server Error", "{\"error\":\"database error\"}");
        return;
    }
    sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT);
    int rc = sqlite3_step(stmt);
    if (rc == SQLITE_ROW) {
        const unsigned char *value = sqlite3_column_text(stmt, 0);
        send_response(fd, 200, "OK", (const char *)value);
    } else {
        const char *default_json = strcmp(key, "profile") == 0 ? "{}" : "[]";
        send_response(fd, 200, "OK", default_json);
    }
    sqlite3_finalize(stmt);
}

static void handle_put_data(int fd, sqlite3 *db, const char *key, const char *payload) {
    if (!json_is_valid(db, payload)) {
        send_response(fd, 400, "Bad Request", "{\"error\":\"invalid json payload\"}");
        return;
    }

    sqlite3_stmt *stmt = NULL;
    const char *upsert =
        "INSERT INTO kv_store (data_key, data_value, updated_at) VALUES (?1, ?2, strftime('%s', 'now'))"
        " ON CONFLICT(data_key) DO UPDATE SET data_value=excluded.data_value, updated_at=excluded.updated_at";

    if (sqlite3_prepare_v2(db, upsert, -1, &stmt, NULL) != SQLITE_OK) {
        send_response(fd, 500, "Internal Server Error", "{\"error\":\"database error\"}");
        return;
    }

    sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, payload, -1, SQLITE_TRANSIENT);
    if (sqlite3_step(stmt) != SQLITE_DONE) {
        sqlite3_finalize(stmt);
        send_response(fd, 500, "Internal Server Error", "{\"error\":\"database error\"}");
        return;
    }

    sqlite3_finalize(stmt);
    send_response(fd, 204, "No Content", "");
}

static void process_client(int fd, sqlite3 *db) {
    char req[REQ_BUF_SIZE + 1];
    ssize_t n = recv(fd, req, REQ_BUF_SIZE, 0);
    if (n <= 0) return;
    req[n] = '\0';

    char *header_end = strstr(req, "\r\n\r\n");
    if (!header_end) {
        send_response(fd, 400, "Bad Request", "{\"error\":\"malformed request\"}");
        return;
    }

    size_t header_len = (size_t)(header_end - req) + 4;
    char method[8] = {0};
    char path[512] = {0};
    if (sscanf(req, "%7s %511s", method, path) != 2) {
        send_response(fd, 400, "Bad Request", "{\"error\":\"malformed request line\"}");
        return;
    }

    if (strcmp(path, "/health") == 0 && strcmp(method, "GET") == 0) {
        send_response(fd, 200, "OK", "{\"status\":\"ok\"}");
        return;
    }

    const char *prefix = "/v1/data/";
    if (strncmp(path, prefix, strlen(prefix)) != 0) {
        send_response(fd, 404, "Not Found", "{\"error\":\"not found\"}");
        return;
    }

    const char *key = path + strlen(prefix);
    if (!is_valid_key(key)) {
        send_response(fd, 404, "Not Found", "{\"error\":\"unknown key\"}");
        return;
    }

    if (strcmp(method, "GET") == 0) {
        handle_get_data(fd, db, key);
        return;
    }

    if (strcmp(method, "PUT") == 0) {
        int content_length = read_content_length(req, header_end);
        if (content_length < 0 || (size_t)content_length > REQ_BUF_SIZE - header_len) {
            send_response(fd, 400, "Bad Request", "{\"error\":\"invalid content length\"}");
            return;
        }
        char *body = req + header_len;
        if ((size_t)content_length > (size_t)n - header_len) {
            send_response(fd, 400, "Bad Request", "{\"error\":\"request body truncated\"}");
            return;
        }
        body[content_length] = '\0';
        handle_put_data(fd, db, key, body);
        return;
    }

    send_response(fd, 405, "Method Not Allowed", "{\"error\":\"method not allowed\"}");
}

static void *worker_loop(void *arg) {
    worker_ctx_t *ctx = (worker_ctx_t *)arg;
    sqlite3 *db = NULL;
    if (sqlite3_open_v2(ctx->db_path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, NULL) != SQLITE_OK) {
        fprintf(stderr, "worker failed to open db: %s\n", sqlite3_errmsg(db));
        if (db) sqlite3_close(db);
        return NULL;
    }
    sqlite3_exec(db, "PRAGMA busy_timeout=5000;", NULL, NULL, NULL);

    while (1) {
        int fd = fd_queue_pop(ctx->queue);
        process_client(fd, db);
        close(fd);
    }

    sqlite3_close(db);
    return NULL;
}

#ifndef FRICU_UNIT_TEST
int main(void) {
    const char *bind_env = getenv("FRICU_SERVER_BIND");
    const char *db_env = getenv("FRICU_DB_PATH");
    const char *workers_env = getenv("FRICU_SERVER_WORKERS");
    const char *queue_env = getenv("FRICU_SERVER_QUEUE");
    const char *bind_addr_str = bind_env ? bind_env : "0.0.0.0:8080";
    const char *db_path = db_env ? db_env : "fricu_server.db";

    size_t worker_count = workers_env ? (size_t)strtoul(workers_env, NULL, 10) : DEFAULT_WORKERS;
    if (worker_count == 0 || worker_count > 1024) worker_count = DEFAULT_WORKERS;
    size_t queue_capacity = queue_env ? (size_t)strtoul(queue_env, NULL, 10) : DEFAULT_QUEUE_CAPACITY;
    if (queue_capacity < 1024) queue_capacity = DEFAULT_QUEUE_CAPACITY;

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

    if (listen(server_fd, SOMAXCONN) < 0) {
        perror("listen");
        close(server_fd);
        return 1;
    }

    fd_queue_t queue;
    if (fd_queue_init(&queue, queue_capacity) != 0) {
        fprintf(stderr, "failed to initialize fd queue\n");
        close(server_fd);
        return 1;
    }

    worker_ctx_t *workers = (worker_ctx_t *)calloc(worker_count, sizeof(worker_ctx_t));
    pthread_t *threads = (pthread_t *)calloc(worker_count, sizeof(pthread_t));
    if (!workers || !threads) {
        fprintf(stderr, "failed to allocate workers\n");
        close(server_fd);
        return 1;
    }

    for (size_t i = 0; i < worker_count; i++) {
        workers[i].queue = &queue;
        strncpy(workers[i].db_path, db_path, sizeof(workers[i].db_path) - 1);
        workers[i].db_path[sizeof(workers[i].db_path) - 1] = '\0';
        if (pthread_create(&threads[i], NULL, worker_loop, &workers[i]) != 0) {
            fprintf(stderr, "failed to start worker %zu\n", i);
            close(server_fd);
            return 1;
        }
    }

    printf("fricu-server listening on %s (workers=%zu queue=%zu)\n", bind_addr_str, worker_count, queue_capacity);

    while (1) {
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);
        int client_fd = accept(server_fd, (struct sockaddr *)&client_addr, &client_len);
        if (client_fd < 0) {
            if (errno == EINTR) continue;
            perror("accept");
            continue;
        }
        fd_queue_push(&queue, client_fd);
    }

    close(server_fd);
    return 0;
}

#endif
