#ifndef FRICU_SERVER_INTERNAL_H
#define FRICU_SERVER_INTERNAL_H

#include <sqlite3.h>
#include <stddef.h>

#define REQ_BUF_SIZE 65536
#define HEADER_BUF_SIZE 2048
#define DEFAULT_WORKERS 64
#define EVENT_MAX_EVENTS 1024
#define CONN_INIT_BUF 8192

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

extern const char *DATA_KEYS[];
extern const size_t DATA_KEYS_COUNT;

int tune_fd_limit(void);
int set_nonblocking(int fd);
int socket_send_flags(void);
int configure_socket_after_accept(int fd);
int init_db(const char *db_path);
int worker_db_open(worker_db_t *db, const char *db_path);
void worker_db_close(worker_db_t *db);

void send_response(int fd, int code, const char *status, const char *body);
int try_process_client(int fd, worker_db_t *db, conn_t *conn);

int run_worker_loop(int listen_fd, const char *db_path, size_t max_fds);

#endif
