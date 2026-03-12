#ifndef FRICU_SERVER_INTERNAL_H
#define FRICU_SERVER_INTERNAL_H

#include <sqlite3.h>
#include <stddef.h>

#define REQ_BUF_SIZE (8 * 1024 * 1024)
#define HEADER_BUF_SIZE 2048
#define DEFAULT_WORKERS 64
#define EVENT_MAX_EVENTS 1024
#define CONN_INIT_BUF 8192

typedef struct {
    sqlite3 *db;
    sqlite3_stmt *get_stmt;
    sqlite3_stmt *json_valid_stmt;
    char db_path[512];
} worker_db_t;

typedef struct {
    int fd;
    size_t len;
    size_t cap;
    char *buf;
} conn_t;

extern const char *DATA_KEYS[];
extern const size_t DATA_KEYS_COUNT;

int tune_fd_limit(void);
int set_nonblocking(int fd);
int socket_send_flags(void);
int configure_socket_after_accept(int fd);
int init_db(const char *db_path);
int worker_db_open(worker_db_t *db, const char *db_path);
void worker_db_close(worker_db_t *db);

typedef struct {
    int completed;
    int status_code;
    int sqlite_rc;
    int sqlite_ext;
    int retry_count;
    char backup_path[512];
} write_dispatch_result_t;

typedef struct {
    int running;
    int queue_depth;
    char last_success_logid[96];
    char last_error_logid[96];
} write_dispatch_diagnostics_t;

int write_dispatcher_acquire(const char *db_path);
void write_dispatcher_release(void);
int write_dispatch_submit(
    const char *logical_key,
    const char *storage_key,
    const char *payload,
    size_t payload_len,
    const char *pending_path,
    const char *account_id,
    const char *log_id,
    int wait_timeout_ms,
    write_dispatch_result_t *out_result);
void write_dispatch_diagnostics_snapshot(write_dispatch_diagnostics_t *out_diag);

void send_response(int fd, int code, const char *status, const char *body);
int try_process_client(int fd, worker_db_t *db, conn_t *conn);

int run_worker_loop(int listen_fd, const char *db_path, size_t max_fds);

#endif
