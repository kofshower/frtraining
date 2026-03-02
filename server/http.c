#include "server.h"
#include "server_internal.h"

#include <errno.h>
#include <stdio.h>
#include <sqlite3.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

static int send_all(int fd, const char *buf, size_t len) {
    size_t sent = 0;
    int retry = 0;
    while (sent < len) {
        ssize_t n = send(fd, buf + sent, len - sent, socket_send_flags());
        if (n > 0) {
            sent += (size_t)n;
            continue;
        }
        if (n < 0 && errno == EINTR) continue;
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

void send_response(int fd, int code, const char *status, const char *body) {
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

int try_process_client(int fd, worker_db_t *db, conn_t *conn) {
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
