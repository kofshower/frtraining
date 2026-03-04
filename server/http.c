#include "server.h"
#include "server_internal.h"
#include "logger.h"

#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <sqlite3.h>
#include <string.h>
#include <sys/stat.h>
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

static int persist_failed_payload(
    const char *key,
    const char *payload,
    size_t payload_len,
    int sqlite_rc,
    int sqlite_ext,
    char *out_path,
    size_t out_path_len) {
    const char *dir = "failed_writes";
    struct stat st;
    if (stat(dir, &st) != 0) {
        if (mkdir(dir, 0700) != 0 && errno != EEXIST) {
            return -1;
        }
    } else if (!S_ISDIR(st.st_mode)) {
        return -1;
    }

    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    int name_len = snprintf(
        out_path,
        out_path_len,
        "%s/%s-%jd-%ld-rc%d-ext%d.json",
        dir,
        key,
        (intmax_t)getpid(),
        ts.tv_nsec,
        sqlite_rc,
        sqlite_ext);
    if (name_len <= 0 || (size_t)name_len >= out_path_len) {
        return -1;
    }

    FILE *f = fopen(out_path, "wb");
    if (!f) return -1;
    size_t written = fwrite(payload, 1, payload_len, f);
    if (fclose(f) != 0 || written != payload_len) {
        unlink(out_path);
        return -1;
    }

    return 0;
}

static void log_http_request(const char *method, const char *path, int status_code, size_t payload_bytes) {
    if (status_code >= 500) {
        log_error("HTTP %s %s -> %d (%zu bytes)", method, path, status_code, payload_bytes);
    } else if (status_code >= 400) {
        log_warn("HTTP %s %s -> %d (%zu bytes)", method, path, status_code, payload_bytes);
    } else {
        log_info("HTTP %s %s -> %d (%zu bytes)", method, path, status_code, payload_bytes);
    }
}

static int handle_get_data(int fd, worker_db_t *db, const char *key) {
    sqlite3_stmt *stmt = db->get_stmt;
    if (!stmt) {
        send_response(fd, 500, "Internal Server Error", "{\"error\":\"database error\"}");
        return 500;
    }

    sqlite3_reset(stmt);
    sqlite3_clear_bindings(stmt);
    sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT);
    int rc = sqlite3_step(stmt);
    if (rc == SQLITE_ROW) {
        const unsigned char *value = sqlite3_column_text(stmt, 0);
        send_response(fd, 200, "OK", (const char *)value);
        log_info("DATA READ key=%s source=db", key);
        return 200;
    } else {
        int is_object_key = strcmp(key, "profile") == 0 || strcmp(key, "app_settings") == 0;
        const char *default_json = is_object_key ? "{}" : "[]";
        send_response(fd, 200, "OK", default_json);
        log_info("DATA READ key=%s source=default", key);
        return 200;
    }
}

static int handle_put_data(int fd, worker_db_t *db, const char *key, const char *payload, size_t payload_len) {
    if (!json_is_valid(db, payload)) {
        send_response(fd, 400, "Bad Request", "{\"error\":\"invalid json payload\"}");
        log_warn("DATA WRITE rejected key=%s reason=invalid_json bytes=%zu", key, payload_len);
        return 400;
    }

    sqlite3_stmt *stmt = db->upsert_stmt;
    if (!stmt) {
        send_response(fd, 500, "Internal Server Error", "{\"error\":\"database error\"}");
        log_error("DATA WRITE failed key=%s reason=missing_upsert_stmt bytes=%zu", key, payload_len);
        return 500;
    }

    sqlite3_reset(stmt);
    sqlite3_clear_bindings(stmt);
    sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, payload, -1, SQLITE_TRANSIENT);
    int rc = SQLITE_ERROR;
    const int max_retries = 8;
    for (int attempt = 0; attempt <= max_retries; attempt++) {
        rc = sqlite3_step(stmt);
        if (rc == SQLITE_DONE) {
            break;
        }

        if ((rc == SQLITE_BUSY || rc == SQLITE_LOCKED) && attempt < max_retries) {
            sqlite3_reset(stmt);
            struct timespec ts = {.tv_sec = 0, .tv_nsec = (long)(2000000 * (attempt + 1))};
            nanosleep(&ts, NULL);
            continue;
        }

        break;
    }

    if (rc != SQLITE_DONE) {
        int ext = sqlite3_extended_errcode(db->db);
        const char *errmsg = sqlite3_errmsg(db->db);
        const char *rc_name = sqlite3_errstr(rc);
        const char *ext_name = sqlite3_errstr(ext);
        char backup_path[512] = {0};
        int backup_ok = persist_failed_payload(key, payload, payload_len, rc, ext, backup_path, sizeof(backup_path));
        char response_body[512] = {0};
        if (backup_ok == 0) {
            snprintf(
                response_body,
                sizeof(response_body),
                "{\"error\":\"database error\",\"rc\":%d,\"ext\":%d,\"backup\":\"%s\"}",
                rc,
                ext,
                backup_path);
        } else {
            snprintf(response_body, sizeof(response_body), "{\"error\":\"database error\",\"rc\":%d,\"ext\":%d}", rc, ext);
        }

        send_response(fd, 500, "Internal Server Error", response_body);
        log_error(
            "DATA WRITE failed key=%s reason=sqlite_step_error rc=%d rc_name=%s ext=%d ext_name=%s errmsg=%s bytes=%zu backup=%s",
            key,
            rc,
            rc_name ? rc_name : "unknown",
            ext,
            ext_name ? ext_name : "unknown",
            errmsg ? errmsg : "unknown",
            payload_len,
            backup_ok == 0 ? backup_path : "none");
        return 500;
    }

    send_response(fd, 204, "No Content", "");
    log_info("DATA WRITE key=%s status=stored bytes=%zu", key, payload_len);
    return 204;
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
        log_http_request("UNKNOWN", "/", 400, 0);
        return 1;
    }

    if (strcmp(path, "/health") == 0 && strcmp(method, "GET") == 0) {
        send_response(fd, 200, "OK", "{\"status\":\"ok\"}");
        log_http_request(method, path, 200, 0);
        return 1;
    }

    const char *prefix = "/v1/data/";
    if (strncmp(path, prefix, strlen(prefix)) != 0) {
        send_response(fd, 404, "Not Found", "{\"error\":\"not found\"}");
        log_http_request(method, path, 404, 0);
        return 1;
    }

    const char *key = path + strlen(prefix);
    if (!is_valid_key(key)) {
        send_response(fd, 404, "Not Found", "{\"error\":\"unknown key\"}");
        log_http_request(method, path, 404, 0);
        return 1;
    }

    if (strcmp(method, "GET") == 0) {
        int status = handle_get_data(fd, db, key);
        log_http_request(method, path, status, 0);
        return 1;
    }

    if (strcmp(method, "PUT") == 0) {
        int content_length = read_content_length(conn->buf, header_end);
        if (content_length < 0 || (size_t)content_length > REQ_BUF_SIZE - header_len) {
            send_response(fd, 400, "Bad Request", "{\"error\":\"invalid content length\"}");
            log_http_request(method, path, 400, 0);
            return 1;
        }
        if ((size_t)content_length > conn->len - header_len) {
            return 0;
        }

        char *body = conn->buf + header_len;
        body[content_length] = '\0';
        int status = handle_put_data(fd, db, key, body, (size_t)content_length);
        log_http_request(method, path, status, (size_t)content_length);
        return 1;
    }

    send_response(fd, 405, "Method Not Allowed", "{\"error\":\"method not allowed\"}");
    log_http_request(method, path, 405, 0);
    return 1;
}
