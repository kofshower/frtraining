#define _GNU_SOURCE

#include <assert.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <sqlite3.h>

#include "../server.h"
#include "../server_internal.h"

static void test_valid_key(void) {
    assert(is_valid_key("activities"));
    assert(is_valid_key("profile"));
    assert(is_valid_key("app_settings"));
    assert(is_valid_key("wellness_samples"));
    assert(is_valid_key("lactate_history_records"));
    assert(is_valid_key("exported_file_1234"));
    assert(!is_valid_key("exported_file_"));
    assert(!is_valid_key("unknown"));
    assert(is_valid_storage_key("acct_1::activities"));
    assert(is_valid_storage_key("acct_1::profile"));
    assert(!is_valid_storage_key("acct::unknown"));
    assert(!is_valid_storage_key("::activities"));
}

static void test_parse_bind_addr(void) {
    char host[128] = {0};
    int port = 0;
    assert(parse_bind_addr("127.0.0.1:8080", host, sizeof(host), &port) == 0);
    assert(strcmp(host, "127.0.0.1") == 0);
    assert(port == 8080);

    assert(parse_bind_addr("0.0.0.0:1", host, sizeof(host), &port) == 0);
    assert(parse_bind_addr("0.0.0.0:65535", host, sizeof(host), &port) == 0);
    assert(parse_bind_addr("0.0.0.0:0", host, sizeof(host), &port) != 0);
    assert(parse_bind_addr("bad", host, sizeof(host), &port) != 0);
}

static void test_read_content_length(void) {
    const char *req =
        "PUT /v1/data/activities HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Content-Length: 17\r\n"
        "Content-Type: application/json\r\n\r\n"
        "[{\"sport\":\"run\"}]";
    const char *header_end = strstr(req, "\r\n\r\n");
    assert(header_end != NULL);
    assert(read_content_length(req, header_end) == 17);

    const char *no_cl = "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n";
    const char *no_cl_end = strstr(no_cl, "\r\n\r\n");
    assert(read_content_length(no_cl, no_cl_end) == 0);

    const char *mixed =
        "PUT /v1/data/profile HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "content-length: 2\r\n\r\n{}";
    const char *mixed_end = strstr(mixed, "\r\n\r\n");
    assert(read_content_length(mixed, mixed_end) == 2);
}

static void test_socket_send_flags(void) {
#ifdef MSG_NOSIGNAL
    assert(socket_send_flags() == MSG_NOSIGNAL);
#else
    assert(socket_send_flags() == 0);
#endif
}

static void test_configure_socket_after_accept(void) {
    int fds[2] = {-1, -1};
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, fds) == 0);
    assert(configure_socket_after_accept(fds[0]) == 0);
    assert(configure_socket_after_accept(fds[1]) == 0);
    close(fds[0]);
    close(fds[1]);
}

static void must_write_all(int fd, const char *buf, size_t len) {
    size_t off = 0;
    while (off < len) {
        ssize_t n = write(fd, buf + off, len - off);
        assert(n > 0);
        off += (size_t)n;
    }
}

static void test_put_is_journaled_and_persisted(void) {
    char dir_template[] = "/tmp/fricu-test-put-XXXXXX";
    char *tmpdir = mkdtemp(dir_template);
    assert(tmpdir != NULL);

    int old_cwd = open(".", O_RDONLY);
    assert(old_cwd >= 0);
    assert(chdir(tmpdir) == 0);

    assert(init_db("state.db") == 0);
    worker_db_t db;
    assert(worker_db_open(&db, "state.db") == 0);

    int fds[2] = {-1, -1};
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, fds) == 0);

    const char *req =
        "PUT /v1/data/profile HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "X-Account-Id: tester\r\n"
        "Content-Length: 14\r\n\r\n"
        "{\"name\":\"Ana\"}";
    conn_t conn = {0};
    conn.cap = REQ_BUF_SIZE;
    conn.buf = (char *)malloc(conn.cap);
    assert(conn.buf != NULL);
    conn.len = strlen(req);
    memcpy(conn.buf, req, conn.len);
    assert(try_process_client(fds[0], &db, &conn) == 1);

    char resp[256] = {0};
    ssize_t n = read(fds[1], resp, sizeof(resp) - 1);
    assert(n > 0);
    assert(strstr(resp, "204 No Content") != NULL);
    assert(strstr(resp, "X-Log-Id: ") != NULL);

    sqlite3 *sqlite = NULL;
    assert(sqlite3_open_v2("state.db", &sqlite, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK);
    sqlite3_stmt *stmt = NULL;
    assert(sqlite3_prepare_v2(sqlite, "SELECT data_value FROM kv_store WHERE data_key='tester::profile'", -1, &stmt, NULL) == SQLITE_OK);
    assert(sqlite3_step(stmt) == SQLITE_ROW);
    const unsigned char *v = sqlite3_column_text(stmt, 0);
    assert(v != NULL);
    assert(strcmp((const char *)v, "{\"name\":\"Ana\"}") == 0);
    sqlite3_finalize(stmt);
    sqlite3_close(sqlite);

    DIR *dir = opendir("pending_writes");
    assert(dir != NULL);
    struct dirent *ent;
    int entries = 0;
    while ((ent = readdir(dir)) != NULL) {
        if (strcmp(ent->d_name, ".") != 0 && strcmp(ent->d_name, "..") != 0) {
            entries++;
        }
    }
    closedir(dir);
    assert(entries == 0);

    free(conn.buf);
    close(fds[0]);
    close(fds[1]);
    worker_db_close(&db);
    assert(fchdir(old_cwd) == 0);
    close(old_cwd);
    char cleanup_cmd[512] = {0};
    assert(snprintf(cleanup_cmd, sizeof(cleanup_cmd), "rm -rf '%s' >/dev/null 2>&1", tmpdir) > 0);
    assert(system(cleanup_cmd) == 0);
}

static void test_missing_account_id_rejected(void) {
    char dir_template[] = "/tmp/fricu-test-no-account-XXXXXX";
    char *tmpdir = mkdtemp(dir_template);
    assert(tmpdir != NULL);

    int old_cwd = open(".", O_RDONLY);
    assert(old_cwd >= 0);
    assert(chdir(tmpdir) == 0);

    assert(init_db("state.db") == 0);
    worker_db_t db;
    assert(worker_db_open(&db, "state.db") == 0);

    int fds[2] = {-1, -1};
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, fds) == 0);

    const char *req =
        "GET /v1/data/activities HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n\r\n";
    conn_t conn = {0};
    conn.cap = REQ_BUF_SIZE;
    conn.buf = (char *)malloc(conn.cap);
    assert(conn.buf != NULL);
    conn.len = strlen(req);
    memcpy(conn.buf, req, conn.len);
    assert(try_process_client(fds[0], &db, &conn) == 1);

    char resp[512] = {0};
    ssize_t n = read(fds[1], resp, sizeof(resp) - 1);
    assert(n > 0);
    assert(strstr(resp, "401 Unauthorized") != NULL);
    assert(strstr(resp, "missing X-Account-Id") != NULL);

    free(conn.buf);
    close(fds[0]);
    close(fds[1]);
    worker_db_close(&db);
    assert(fchdir(old_cwd) == 0);
    close(old_cwd);
    char cleanup_cmd[512] = {0};
    assert(snprintf(cleanup_cmd, sizeof(cleanup_cmd), "rm -rf '%s' >/dev/null 2>&1", tmpdir) > 0);
    assert(system(cleanup_cmd) == 0);
}

static void test_write_queue_diagnostics_endpoint(void) {
    char dir_template[] = "/tmp/fricu-test-diag-XXXXXX";
    char *tmpdir = mkdtemp(dir_template);
    assert(tmpdir != NULL);

    int old_cwd = open(".", O_RDONLY);
    assert(old_cwd >= 0);
    assert(chdir(tmpdir) == 0);

    assert(init_db("state.db") == 0);
    worker_db_t db;
    assert(worker_db_open(&db, "state.db") == 0);

    int put_fds[2] = {-1, -1};
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, put_fds) == 0);
    const char *put_req =
        "PUT /v1/data/profile HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "X-Account-Id: tester\r\n"
        "X-Log-Id: diag-success\r\n"
        "Content-Length: 14\r\n\r\n"
        "{\"name\":\"Ana\"}";
    conn_t put_conn = {0};
    put_conn.cap = REQ_BUF_SIZE;
    put_conn.buf = (char *)malloc(put_conn.cap);
    assert(put_conn.buf != NULL);
    put_conn.len = strlen(put_req);
    memcpy(put_conn.buf, put_req, put_conn.len);
    assert(try_process_client(put_fds[0], &db, &put_conn) == 1);
    char put_resp[256] = {0};
    ssize_t put_n = read(put_fds[1], put_resp, sizeof(put_resp) - 1);
    assert(put_n > 0);
    assert(strstr(put_resp, "204 No Content") != NULL);

    int diag_fds[2] = {-1, -1};
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, diag_fds) == 0);
    const char *diag_req =
        "GET /debug/write-queue HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Connection: close\r\n\r\n";
    conn_t diag_conn = {0};
    diag_conn.cap = REQ_BUF_SIZE;
    diag_conn.buf = (char *)malloc(diag_conn.cap);
    assert(diag_conn.buf != NULL);
    diag_conn.len = strlen(diag_req);
    memcpy(diag_conn.buf, diag_req, diag_conn.len);
    assert(try_process_client(diag_fds[0], &db, &diag_conn) == 1);

    char diag_resp[1024] = {0};
    ssize_t diag_n = read(diag_fds[1], diag_resp, sizeof(diag_resp) - 1);
    assert(diag_n > 0);
    assert(strstr(diag_resp, "200 OK") != NULL);
    assert(strstr(diag_resp, "\"queue_depth\":0") != NULL);
    assert(strstr(diag_resp, "\"last_success_logid\":\"diag-success\"") != NULL);
    assert(strstr(diag_resp, "\"last_error_logid\":\"\"") != NULL);

    free(put_conn.buf);
    free(diag_conn.buf);
    close(put_fds[0]);
    close(put_fds[1]);
    close(diag_fds[0]);
    close(diag_fds[1]);
    worker_db_close(&db);
    assert(fchdir(old_cwd) == 0);
    close(old_cwd);
    char cleanup_cmd[512] = {0};
    assert(snprintf(cleanup_cmd, sizeof(cleanup_cmd), "rm -rf '%s' >/dev/null 2>&1", tmpdir) > 0);
    assert(system(cleanup_cmd) == 0);
}


static void test_put_lock_is_queued_in_pending_writes(void) {
    char dir_template[] = "/tmp/fricu-test-lock-XXXXXX";
    char *tmpdir = mkdtemp(dir_template);
    assert(tmpdir != NULL);

    int old_cwd = open(".", O_RDONLY);
    assert(old_cwd >= 0);
    assert(chdir(tmpdir) == 0);

    assert(init_db("state.db") == 0);
    worker_db_t db;
    assert(worker_db_open(&db, "state.db") == 0);

    sqlite3 *locker = NULL;
    assert(sqlite3_open_v2("state.db", &locker, SQLITE_OPEN_READWRITE, NULL) == SQLITE_OK);
    assert(sqlite3_exec(locker, "BEGIN EXCLUSIVE;", NULL, NULL, NULL) == SQLITE_OK);

    int fds[2] = {-1, -1};
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, fds) == 0);

    const char *req =
        "PUT /v1/data/app_settings HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "X-Account-Id: tester\r\n"
        "Content-Length: 10\r\n\r\n"
        "{\"v\":true}";
    conn_t conn = {0};
    conn.cap = REQ_BUF_SIZE;
    conn.buf = (char *)malloc(conn.cap);
    assert(conn.buf != NULL);
    conn.len = strlen(req);
    memcpy(conn.buf, req, conn.len);
    assert(try_process_client(fds[0], &db, &conn) == 1);

    char resp[1024] = {0};
    ssize_t n = read(fds[1], resp, sizeof(resp) - 1);
    assert(n > 0);
    assert(strstr(resp, "202 Accepted") != NULL);
    assert(strstr(resp, "\"status\":\"queued\"") != NULL);
    assert(strstr(resp, "\"logid\":\"") != NULL);
    assert(strstr(resp, "X-Log-Id: ") != NULL);

    DIR *dir = opendir("pending_writes");
    assert(dir != NULL);
    struct dirent *ent;
    int entries = 0;
    int has_app_settings = 0;
    while ((ent = readdir(dir)) != NULL) {
        if (strcmp(ent->d_name, ".") != 0 && strcmp(ent->d_name, "..") != 0) {
            entries++;
            if (strncmp(ent->d_name, "tester::app_settings-", strlen("tester::app_settings-")) == 0) {
                has_app_settings = 1;
            }
        }
    }
    closedir(dir);
    assert(entries > 0);
    assert(has_app_settings == 1);

    assert(sqlite3_exec(locker, "ROLLBACK;", NULL, NULL, NULL) == SQLITE_OK);
    sqlite3_close(locker);

    free(conn.buf);
    close(fds[0]);
    close(fds[1]);
    worker_db_close(&db);

    assert(init_db("state.db") == 0);

    sqlite3 *sqlite = NULL;
    assert(sqlite3_open_v2("state.db", &sqlite, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK);
    sqlite3_stmt *stmt = NULL;
    assert(sqlite3_prepare_v2(sqlite, "SELECT data_value FROM kv_store WHERE data_key='tester::app_settings'", -1, &stmt, NULL) == SQLITE_OK);
    assert(sqlite3_step(stmt) == SQLITE_ROW);
    const unsigned char *v = sqlite3_column_text(stmt, 0);
    assert(v != NULL);
    assert(strcmp((const char *)v, "{\"v\":true}") == 0);
    sqlite3_finalize(stmt);
    sqlite3_close(sqlite);

    assert(fchdir(old_cwd) == 0);
    close(old_cwd);
    char cleanup_cmd[512] = {0};
    assert(snprintf(cleanup_cmd, sizeof(cleanup_cmd), "rm -rf '%s' >/dev/null 2>&1", tmpdir) > 0);
    assert(system(cleanup_cmd) == 0);
}

static void test_replay_pending_write_on_restart(void) {
    char dir_template[] = "/tmp/fricu-test-replay-XXXXXX";
    char *tmpdir = mkdtemp(dir_template);
    assert(tmpdir != NULL);

    int old_cwd = open(".", O_RDONLY);
    assert(old_cwd >= 0);
    assert(chdir(tmpdir) == 0);

    assert(init_db("state.db") == 0);
    assert(mkdir("pending_writes", 0700) == 0 || errno == EEXIST);
    FILE *f = fopen("pending_writes/tester::profile-999-1-1.json", "wb");
    assert(f != NULL);
    assert(fwrite("{\"name\":\"Recovered\"}", 1, 20, f) == 20);
    assert(fclose(f) == 0);

    assert(init_db("state.db") == 0);

    sqlite3 *sqlite = NULL;
    assert(sqlite3_open_v2("state.db", &sqlite, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK);
    sqlite3_stmt *stmt = NULL;
    assert(sqlite3_prepare_v2(sqlite, "SELECT data_value FROM kv_store WHERE data_key='tester::profile'", -1, &stmt, NULL) == SQLITE_OK);
    assert(sqlite3_step(stmt) == SQLITE_ROW);
    const unsigned char *v = sqlite3_column_text(stmt, 0);
    assert(v != NULL);
    assert(strcmp((const char *)v, "{\"name\":\"Recovered\"}") == 0);
    sqlite3_finalize(stmt);
    sqlite3_close(sqlite);

    assert(access("pending_writes/tester::profile-999-1-1.json", F_OK) != 0);

    assert(fchdir(old_cwd) == 0);
    close(old_cwd);
    char cleanup_cmd[512] = {0};
    assert(snprintf(cleanup_cmd, sizeof(cleanup_cmd), "rm -rf '%s' >/dev/null 2>&1", tmpdir) > 0);
    assert(system(cleanup_cmd) == 0);
}

int main(void) {
    test_valid_key();
    test_parse_bind_addr();
    test_read_content_length();
    test_socket_send_flags();
    test_configure_socket_after_accept();
    test_put_is_journaled_and_persisted();
    test_missing_account_id_rejected();
    test_write_queue_diagnostics_endpoint();
    test_replay_pending_write_on_restart();
    test_put_lock_is_queued_in_pending_writes();
    puts("unit tests passed");
    return 0;
}
