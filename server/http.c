#define _GNU_SOURCE

#include "server.h"
#include "server_internal.h"
#include "logger.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <sqlite3.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define PENDING_WRITES_DIR "pending_writes"
#define LOG_ID_MAX_LEN 96
#define ACCOUNT_ID_MAX_LEN 128

typedef struct {
    char log_id[LOG_ID_MAX_LEN];
    char account_id[ACCOUNT_ID_MAX_LEN];
    int retry_attempt;
} request_log_context_t;

static int fsync_directory(const char *dir_path) {
    DIR *d = opendir(dir_path);
    if (!d) return -1;
    int fd = dirfd(d);
    if (fd < 0) {
        closedir(d);
        return -1;
    }
    int rc = fsync(fd);
    closedir(d);
    return rc;
}

static int ensure_pending_writes_dir(void) {
    struct stat st;
    if (stat(PENDING_WRITES_DIR, &st) == 0) {
        if (!S_ISDIR(st.st_mode)) return -1;
        return 0;
    }
    if (errno != ENOENT) return -1;
    if (mkdir(PENDING_WRITES_DIR, 0700) != 0 && errno != EEXIST) return -1;
    return fsync_directory(".");
}

static void sanitize_log_id(const char *input, char *out, size_t out_len) {
    if (!out || out_len == 0) return;
    size_t idx = 0;
    if (input) {
        for (size_t i = 0; input[i] != '\0' && idx + 1 < out_len; i++) {
            unsigned char ch = (unsigned char)input[i];
            if (isalnum(ch) || ch == '-' || ch == '_' || ch == '.' || ch == ':') {
                out[idx++] = (char)ch;
            }
        }
    }
    out[idx] = '\0';
}

static void sanitize_log_id_for_filename(const char *input, char *out, size_t out_len) {
    if (!out || out_len == 0) return;
    size_t idx = 0;
    if (input) {
        for (size_t i = 0; input[i] != '\0' && idx + 1 < out_len; i++) {
            unsigned char ch = (unsigned char)input[i];
            if (isalnum(ch) || ch == '-' || ch == '_') {
                out[idx++] = (char)ch;
            } else {
                out[idx++] = '_';
            }
        }
    }
    out[idx] = '\0';
}

static void sanitize_account_id(const char *input, char *out, size_t out_len) {
    if (!out || out_len == 0) return;
    size_t idx = 0;
    if (input) {
        for (size_t i = 0; input[i] != '\0' && idx + 1 < out_len; i++) {
            unsigned char ch = (unsigned char)input[i];
            if (isalnum(ch) || ch == '-' || ch == '_' || ch == '.') {
                out[idx++] = (char)ch;
            }
        }
    }
    out[idx] = '\0';
}

static void generate_server_log_id(char *out, size_t out_len) {
    if (!out || out_len == 0) return;
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    int n = snprintf(out, out_len, "srv-%jd-%ld-%ld", (intmax_t)ts.tv_sec, ts.tv_nsec, (long)getpid());
    if (n <= 0 || (size_t)n >= out_len) {
        snprintf(out, out_len, "srv-%ld", (long)getpid());
    }
}

static int read_header_value(
    const char *req,
    const char *header_end,
    const char *header_name,
    char *out_value,
    size_t out_value_len) {
    if (!req || !header_end || !header_name || !out_value || out_value_len == 0) return 0;
    out_value[0] = '\0';

    size_t name_len = strlen(header_name);
    const char *line = strstr(req, "\r\n");
    if (!line) return 0;
    line += 2;

    while (line < header_end) {
        const char *line_end = strstr(line, "\r\n");
        if (!line_end || line_end > header_end) {
            line_end = header_end;
        }

        const char *colon = memchr(line, ':', (size_t)(line_end - line));
        if (colon) {
            size_t key_len = (size_t)(colon - line);
            if (key_len == name_len && strncasecmp(line, header_name, name_len) == 0) {
                const char *value_start = colon + 1;
                while (value_start < line_end && (*value_start == ' ' || *value_start == '\t')) {
                    value_start++;
                }
                const char *value_end = line_end;
                while (value_end > value_start && (value_end[-1] == ' ' || value_end[-1] == '\t')) {
                    value_end--;
                }
                size_t copy_len = (size_t)(value_end - value_start);
                if (copy_len >= out_value_len) {
                    copy_len = out_value_len - 1;
                }
                memcpy(out_value, value_start, copy_len);
                out_value[copy_len] = '\0';
                return copy_len > 0;
            }
        }

        if (line_end >= header_end) break;
        line = line_end + 2;
    }

    return 0;
}

static request_log_context_t build_request_log_context(const char *req, const char *header_end) {
    request_log_context_t context;
    memset(&context, 0, sizeof(context));

    char raw_log_id[256] = {0};
    if (read_header_value(req, header_end, "X-Log-Id", raw_log_id, sizeof(raw_log_id))) {
        sanitize_log_id(raw_log_id, context.log_id, sizeof(context.log_id));
    }
    if (context.log_id[0] == '\0') {
        generate_server_log_id(context.log_id, sizeof(context.log_id));
    }

    char raw_retry_attempt[32] = {0};
    if (read_header_value(req, header_end, "X-Retry-Attempt", raw_retry_attempt, sizeof(raw_retry_attempt))) {
        char *end = NULL;
        long parsed = strtol(raw_retry_attempt, &end, 10);
        if (end != raw_retry_attempt && *end == '\0' && parsed >= 0 && parsed <= 100000) {
            context.retry_attempt = (int)parsed;
        }
    }

    char raw_account_id[256] = {0};
    if (read_header_value(req, header_end, "X-Account-Id", raw_account_id, sizeof(raw_account_id))) {
        sanitize_account_id(raw_account_id, context.account_id, sizeof(context.account_id));
    }

    return context;
}

static int build_storage_key(
    const char *account_id,
    const char *logical_key,
    char *out_storage_key,
    size_t out_storage_key_len) {
    if (!account_id || account_id[0] == '\0' || !logical_key || logical_key[0] == '\0') return -1;
    int written = snprintf(out_storage_key, out_storage_key_len, "%s::%s", account_id, logical_key);
    if (written <= 0 || (size_t)written >= out_storage_key_len) return -1;
    return 0;
}

static int create_pending_write(
    const char *key,
    const char *payload,
    size_t payload_len,
    const request_log_context_t *ctx,
    char *out_path,
    size_t out_path_len) {
    if (ensure_pending_writes_dir() != 0) return -1;

    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    unsigned long tid = (unsigned long)getpid();
    char log_id_token[64] = {0};
    sanitize_log_id_for_filename(ctx ? ctx->log_id : NULL, log_id_token, sizeof(log_id_token));
    if (log_id_token[0] == '\0') {
        memcpy(log_id_token, "none", 5);
    }
    int tmp_len = snprintf(
        out_path,
        out_path_len,
        "%s/%s-%lu-%jd-%ld-lid-%s.tmp",
        PENDING_WRITES_DIR,
        key,
        tid,
        (intmax_t)ts.tv_sec,
        ts.tv_nsec,
        log_id_token);
    if (tmp_len <= 0 || (size_t)tmp_len >= out_path_len) return -1;

    int fd = open(out_path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) return -1;
    ssize_t wr = write(fd, payload, payload_len);
    if (wr < 0 || (size_t)wr != payload_len || fsync(fd) != 0 || close(fd) != 0) {
        close(fd);
        unlink(out_path);
        return -1;
    }

    char final_path[512] = {0};
    int final_len = snprintf(
        final_path,
        sizeof(final_path),
        "%s/%s-%lu-%jd-%ld-lid-%s.json",
        PENDING_WRITES_DIR,
        key,
        tid,
        (intmax_t)ts.tv_sec,
        ts.tv_nsec,
        log_id_token);
    if (final_len <= 0 || (size_t)final_len >= sizeof(final_path)) {
        unlink(out_path);
        return -1;
    }
    if (rename(out_path, final_path) != 0 || fsync_directory(PENDING_WRITES_DIR) != 0) {
        unlink(out_path);
        unlink(final_path);
        return -1;
    }

    size_t copy_len = (size_t)final_len;
    if (copy_len + 1 > out_path_len) return -1;
    memcpy(out_path, final_path, copy_len + 1);
    return 0;
}

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

static void send_response_with_log_context(
    int fd,
    int code,
    const char *status,
    const char *body,
    const request_log_context_t *ctx) {
    size_t body_len = body ? strlen(body) : 0;
    char header[HEADER_BUF_SIZE];
    const char *log_id = (ctx && ctx->log_id[0] != '\0') ? ctx->log_id : NULL;
    int header_len = 0;
    if (log_id) {
        header_len = snprintf(
            header,
            sizeof(header),
            "HTTP/1.1 %d %s\r\n"
            "Content-Type: application/json\r\n"
            "X-Log-Id: %s\r\n"
            "Content-Length: %zu\r\n"
            "Connection: close\r\n\r\n",
            code,
            status,
            log_id,
            body_len);
    } else {
        header_len = snprintf(
            header,
            sizeof(header),
            "HTTP/1.1 %d %s\r\n"
            "Content-Type: application/json\r\n"
            "Content-Length: %zu\r\n"
            "Connection: close\r\n\r\n",
            code,
            status,
            body_len);
    }
    if (header_len > 0 && (size_t)header_len < sizeof(header)) {
        send_all(fd, header, (size_t)header_len);
    }
    if (body_len > 0) {
        send_all(fd, body, body_len);
    }
}

void send_response(int fd, int code, const char *status, const char *body) {
    send_response_with_log_context(fd, code, status, body, NULL);
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

static void log_http_request(
    const char *method,
    const char *path,
    int status_code,
    size_t payload_bytes,
    const request_log_context_t *ctx) {
    const char *log_id = (ctx && ctx->log_id[0] != '\0') ? ctx->log_id : "-";
    const char *account_id = (ctx && ctx->account_id[0] != '\0') ? ctx->account_id : "-";
    int retry_attempt = ctx ? ctx->retry_attempt : 0;
    if (status_code >= 500) {
        log_error("HTTP %s %s -> %d (%zu bytes) account=%s logid=%s retry=%d", method, path, status_code, payload_bytes, account_id, log_id, retry_attempt);
    } else if (status_code >= 400) {
        log_warn("HTTP %s %s -> %d (%zu bytes) account=%s logid=%s retry=%d", method, path, status_code, payload_bytes, account_id, log_id, retry_attempt);
    } else {
        log_info("HTTP %s %s -> %d (%zu bytes) account=%s logid=%s retry=%d", method, path, status_code, payload_bytes, account_id, log_id, retry_attempt);
    }
}

static int handle_get_data(int fd, worker_db_t *db, const char *key, const request_log_context_t *ctx) {
    sqlite3_stmt *stmt = db->get_stmt;
    if (!stmt) {
        send_response_with_log_context(fd, 500, "Internal Server Error", "{\"error\":\"database error\"}", ctx);
        return 500;
    }

    sqlite3_reset(stmt);
    sqlite3_clear_bindings(stmt);
    char storage_key[256] = {0};
    if (build_storage_key(ctx->account_id, key, storage_key, sizeof(storage_key)) != 0) {
        send_response_with_log_context(fd, 500, "Internal Server Error", "{\"error\":\"invalid account key\"}", ctx);
        return 500;
    }
    sqlite3_bind_text(stmt, 1, storage_key, -1, SQLITE_TRANSIENT);
    int rc = sqlite3_step(stmt);
    if (rc == SQLITE_ROW) {
        const unsigned char *value = sqlite3_column_text(stmt, 0);
        send_response_with_log_context(fd, 200, "OK", (const char *)value, ctx);
        log_info("DATA READ key=%s source=db account=%s logid=%s", key, ctx->account_id, ctx->log_id);
        return 200;
    } else {
        int is_object_key = strcmp(key, "profile") == 0 || strcmp(key, "app_settings") == 0;
        const char *default_json = is_object_key ? "{}" : "[]";
        send_response_with_log_context(fd, 200, "OK", default_json, ctx);
        log_info("DATA READ key=%s source=default account=%s logid=%s", key, ctx->account_id, ctx->log_id);
        return 200;
    }
}

static int handle_get_write_queue_diagnostics(int fd, const request_log_context_t *ctx) {
    write_dispatch_diagnostics_t diag;
    write_dispatch_diagnostics_snapshot(&diag);

    char body[512] = {0};
    snprintf(
        body,
        sizeof(body),
        "{\"running\":%s,\"queue_depth\":%d,\"last_success_logid\":\"%s\",\"last_error_logid\":\"%s\"}",
        diag.running ? "true" : "false",
        diag.queue_depth,
        diag.last_success_logid,
        diag.last_error_logid);
    send_response_with_log_context(fd, 200, "OK", body, ctx);
    return 200;
}

static int handle_put_data(
    int fd,
    worker_db_t *db,
    const char *key,
    const char *payload,
    size_t payload_len,
    const request_log_context_t *ctx) {
    if (!json_is_valid(db, payload)) {
        send_response_with_log_context(fd, 400, "Bad Request", "{\"error\":\"invalid json payload\"}", ctx);
        log_warn("DATA WRITE rejected key=%s reason=invalid_json bytes=%zu logid=%s", key, payload_len, ctx->log_id);
        return 400;
    }

    char storage_key[256] = {0};
    if (build_storage_key(ctx->account_id, key, storage_key, sizeof(storage_key)) != 0) {
        send_response_with_log_context(fd, 500, "Internal Server Error", "{\"error\":\"invalid account key\"}", ctx);
        return 500;
    }

    char pending_path[512] = {0};
    if (create_pending_write(storage_key, payload, payload_len, ctx, pending_path, sizeof(pending_path)) != 0) {
        send_response_with_log_context(fd, 500, "Internal Server Error", "{\"error\":\"durable journal error\"}", ctx);
        log_error("DATA WRITE failed key=%s reason=pending_write_create_failed bytes=%zu account=%s logid=%s", key, payload_len, ctx->account_id, ctx->log_id);
        return 500;
    }

    write_dispatch_result_t result;
    int dispatch_rc = write_dispatch_submit(
        key,
        storage_key,
        payload,
        payload_len,
        pending_path,
        ctx->account_id,
        ctx->log_id,
        150,
        &result);
    if (dispatch_rc < 0) {
        send_response_with_log_context(fd, 500, "Internal Server Error", "{\"error\":\"write queue unavailable\"}", ctx);
        log_error("DATA WRITE failed key=%s reason=dispatch_enqueue_failed bytes=%zu account=%s logid=%s", key, payload_len, ctx->account_id, ctx->log_id);
        return 500;
    }

    if (dispatch_rc > 0) {
        char response_body[512] = {0};
        snprintf(
            response_body,
            sizeof(response_body),
            "{\"status\":\"queued\",\"logid\":\"%s\",\"pending\":\"%s\"}",
            ctx->log_id,
            pending_path);
        send_response_with_log_context(fd, 202, "Accepted", response_body, ctx);
        log_warn(
            "DATA WRITE queued key=%s reason=writer_backlog bytes=%zu pending=%s account=%s logid=%s",
            key,
            payload_len,
            pending_path,
            ctx->account_id,
            ctx->log_id);
        return 202;
    }

    if (result.status_code != 204) {
        char response_body[512] = {0};
        if (result.backup_path[0] != '\0') {
            snprintf(
                response_body,
                sizeof(response_body),
                "{\"error\":\"database error\",\"rc\":%d,\"ext\":%d,\"backup\":\"%s\"}",
                result.sqlite_rc,
                result.sqlite_ext,
                result.backup_path);
        } else {
            snprintf(response_body, sizeof(response_body), "{\"error\":\"database error\",\"rc\":%d,\"ext\":%d}", result.sqlite_rc, result.sqlite_ext);
        }
        send_response_with_log_context(fd, 500, "Internal Server Error", response_body, ctx);
        return 500;
    }

    send_response_with_log_context(fd, 204, "No Content", "", ctx);
    return 204;
}

int try_process_client(int fd, worker_db_t *db, conn_t *conn) {
    conn->buf[conn->len] = '\0';
    char *header_end = strstr(conn->buf, "\r\n\r\n");
    if (!header_end) return 0;
    request_log_context_t log_ctx = build_request_log_context(conn->buf, header_end);

    size_t header_len = (size_t)(header_end - conn->buf) + 4;
    char method[8] = {0};
    char path[512] = {0};
    if (sscanf(conn->buf, "%7s %511s", method, path) != 2) {
        send_response_with_log_context(fd, 400, "Bad Request", "{\"error\":\"malformed request line\"}", &log_ctx);
        log_http_request("UNKNOWN", "/", 400, 0, &log_ctx);
        return 1;
    }

    if (strcmp(path, "/health") == 0 && strcmp(method, "GET") == 0) {
        send_response_with_log_context(fd, 200, "OK", "{\"status\":\"ok\"}", &log_ctx);
        log_http_request(method, path, 200, 0, &log_ctx);
        return 1;
    }

    if ((strcmp(path, "/debug/write-queue") == 0 || strcmp(path, "/v1/debug/write-queue") == 0) &&
        strcmp(method, "GET") == 0) {
        int status = handle_get_write_queue_diagnostics(fd, &log_ctx);
        log_http_request(method, path, status, 0, &log_ctx);
        return 1;
    }

    const char *prefix = "/v1/data/";
    if (strncmp(path, prefix, strlen(prefix)) != 0) {
        send_response_with_log_context(fd, 404, "Not Found", "{\"error\":\"not found\"}", &log_ctx);
        log_http_request(method, path, 404, 0, &log_ctx);
        return 1;
    }

    const char *key = path + strlen(prefix);
    if (!is_valid_key(key)) {
        send_response_with_log_context(fd, 404, "Not Found", "{\"error\":\"unknown key\"}", &log_ctx);
        log_http_request(method, path, 404, 0, &log_ctx);
        return 1;
    }

    if (log_ctx.account_id[0] == '\0') {
        send_response_with_log_context(fd, 401, "Unauthorized", "{\"error\":\"missing X-Account-Id\"}", &log_ctx);
        log_http_request(method, path, 401, 0, &log_ctx);
        return 1;
    }

    if (strcmp(method, "GET") == 0) {
        int status = handle_get_data(fd, db, key, &log_ctx);
        log_http_request(method, path, status, 0, &log_ctx);
        return 1;
    }

    if (strcmp(method, "PUT") == 0) {
        int content_length = read_content_length(conn->buf, header_end);
        if (content_length < 0 || (size_t)content_length > REQ_BUF_SIZE - header_len) {
            send_response_with_log_context(fd, 400, "Bad Request", "{\"error\":\"invalid content length\"}", &log_ctx);
            log_http_request(method, path, 400, 0, &log_ctx);
            return 1;
        }
        if ((size_t)content_length > conn->len - header_len) {
            return 0;
        }

        char *body = conn->buf + header_len;
        body[content_length] = '\0';
        int status = handle_put_data(fd, db, key, body, (size_t)content_length, &log_ctx);
        log_http_request(method, path, status, (size_t)content_length, &log_ctx);
        return 1;
    }

    send_response_with_log_context(fd, 405, "Method Not Allowed", "{\"error\":\"method not allowed\"}", &log_ctx);
    log_http_request(method, path, 405, 0, &log_ctx);
    return 1;
}
