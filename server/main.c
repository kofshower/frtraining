#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <pthread.h>
#include <sqlite3.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <unistd.h>

#define REQ_BUF_SIZE 65536
#define HEADER_BUF_SIZE 2048

static const char *DATA_KEYS[] = {
    "activities",
    "activity_metric_insights",
    "meal_plans",
    "custom_foods",
    "workouts",
    "events",
    "profile",
};
static const size_t DATA_KEYS_COUNT = sizeof(DATA_KEYS) / sizeof(DATA_KEYS[0]);

typedef struct {
    int client_fd;
    char db_path[512];
} client_args_t;

static bool is_valid_key(const char *key) {
    for (size_t i = 0; i < DATA_KEYS_COUNT; i++) {
        if (strcmp(DATA_KEYS[i], key) == 0) {
            return true;
        }
    }
    return false;
}

static int init_db(const char *db_path) {
    sqlite3 *db = NULL;
    if (sqlite3_open(db_path, &db) != SQLITE_OK) {
        fprintf(stderr, "failed to open db: %s\n", sqlite3_errmsg(db));
        if (db) sqlite3_close(db);
        return -1;
    }

    const char *schema_sql =
        "PRAGMA journal_mode = WAL;"
        "PRAGMA synchronous = NORMAL;"
        "PRAGMA temp_store = MEMORY;"
        "CREATE TABLE IF NOT EXISTS kv_store ("
        "  data_key TEXT PRIMARY KEY,"
        "  data_value TEXT NOT NULL,"
        "  updated_at INTEGER NOT NULL"
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
        body_len
    );
    send(fd, header, (size_t)header_len, 0);
    if (body_len > 0) {
        send(fd, body, body_len, 0);
    }
}

static int json_is_valid(sqlite3 *db, const char *json) {
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, "SELECT json_valid(?1)", -1, &stmt, NULL) != SQLITE_OK) {
        return 0;
    }
    sqlite3_bind_text(stmt, 1, json, -1, SQLITE_TRANSIENT);
    int ok = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        ok = sqlite3_column_int(stmt, 0);
    }
    sqlite3_finalize(stmt);
    return ok;
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

static void *handle_client(void *arg) {
    client_args_t *ctx = (client_args_t *)arg;
    int fd = ctx->client_fd;
    char db_path[512];
    strncpy(db_path, ctx->db_path, sizeof(db_path) - 1);
    db_path[sizeof(db_path) - 1] = '\0';
    free(ctx);

    char req[REQ_BUF_SIZE + 1];
    ssize_t n = recv(fd, req, REQ_BUF_SIZE, 0);
    if (n <= 0) {
        close(fd);
        return NULL;
    }
    req[n] = '\0';

    char *header_end = strstr(req, "\r\n\r\n");
    if (!header_end) {
        send_response(fd, 400, "Bad Request", "{\"error\":\"malformed request\"}");
        close(fd);
        return NULL;
    }

    size_t header_len = (size_t)(header_end - req) + 4;

    char method[8] = {0};
    char path[512] = {0};
    if (sscanf(req, "%7s %511s", method, path) != 2) {
        send_response(fd, 400, "Bad Request", "{\"error\":\"malformed request line\"}");
        close(fd);
        return NULL;
    }

    int content_length = 0;
    char *line = strstr(req, "\r\n") ? strstr(req, "\r\n") + 2 : NULL;
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

    if (strcmp(path, "/health") == 0 && strcmp(method, "GET") == 0) {
        send_response(fd, 200, "OK", "{\"status\":\"ok\"}");
        close(fd);
        return NULL;
    }

    const char *prefix = "/v1/data/";
    if (strncmp(path, prefix, strlen(prefix)) != 0) {
        send_response(fd, 404, "Not Found", "{\"error\":\"not found\"}");
        close(fd);
        return NULL;
    }

    const char *key = path + strlen(prefix);
    if (!is_valid_key(key)) {
        send_response(fd, 404, "Not Found", "{\"error\":\"unknown key\"}");
        close(fd);
        return NULL;
    }

    sqlite3 *db = NULL;
    if (sqlite3_open(db_path, &db) != SQLITE_OK) {
        send_response(fd, 500, "Internal Server Error", "{\"error\":\"database open error\"}");
        if (db) sqlite3_close(db);
        close(fd);
        return NULL;
    }

    if (strcmp(method, "GET") == 0) {
        handle_get_data(fd, db, key);
    } else if (strcmp(method, "PUT") == 0) {
        if (content_length < 0 || (size_t)content_length > REQ_BUF_SIZE - header_len) {
            send_response(fd, 400, "Bad Request", "{\"error\":\"invalid content length\"}");
        } else {
            char *body = req + header_len;
            if ((size_t)content_length > (size_t)n - header_len) {
                send_response(fd, 400, "Bad Request", "{\"error\":\"request body truncated\"}");
            } else {
                body[content_length] = '\0';
                handle_put_data(fd, db, key, body);
            }
        }
    } else {
        send_response(fd, 405, "Method Not Allowed", "{\"error\":\"method not allowed\"}");
    }

    sqlite3_close(db);
    close(fd);
    return NULL;
}

int main(void) {
    const char *bind_env = getenv("FRICU_SERVER_BIND");
    const char *db_env = getenv("FRICU_DB_PATH");
    const char *bind_addr_str = bind_env ? bind_env : "0.0.0.0:8080";
    const char *db_path = db_env ? db_env : "fricu_server.db";

    if (init_db(db_path) != 0) {
        return 1;
    }

    char host[128] = {0};
    int port = 8080;
    if (sscanf(bind_addr_str, "%127[^:]:%d", host, &port) != 2) {
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

    if (listen(server_fd, 1024) < 0) {
        perror("listen");
        close(server_fd);
        return 1;
    }

    printf("fricu-server listening on %s\n", bind_addr_str);

    while (1) {
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);
        int client_fd = accept(server_fd, (struct sockaddr *)&client_addr, &client_len);
        if (client_fd < 0) {
            if (errno == EINTR) continue;
            perror("accept");
            continue;
        }

        client_args_t *args = (client_args_t *)malloc(sizeof(client_args_t));
        if (!args) {
            close(client_fd);
            continue;
        }
        args->client_fd = client_fd;
        strncpy(args->db_path, db_path, sizeof(args->db_path) - 1);
        args->db_path[sizeof(args->db_path) - 1] = '\0';

        pthread_t tid;
        if (pthread_create(&tid, NULL, handle_client, args) != 0) {
            close(client_fd);
            free(args);
            continue;
        }
        pthread_detach(tid);
    }

    close(server_fd);
    return 0;
}
