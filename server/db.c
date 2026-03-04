#define _GNU_SOURCE

#include "server_internal.h"
#include "server.h"
#include "logger.h"

#include <dirent.h>
#include <errno.h>
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define PENDING_WRITES_DIR "pending_writes"

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

static int replay_pending_writes(sqlite3 *db) {
    if (ensure_pending_writes_dir() != 0) {
        log_error("failed to ensure pending writes dir");
        return -1;
    }

    sqlite3_stmt *stmt = NULL;
    const char *upsert_sql =
        "INSERT INTO kv_store (data_key, data_value, updated_at) VALUES (?1, ?2, strftime('%s', 'now'))"
        " ON CONFLICT(data_key) DO UPDATE SET data_value=excluded.data_value, updated_at=excluded.updated_at";
    if (sqlite3_prepare_v2(db, upsert_sql, -1, &stmt, NULL) != SQLITE_OK) {
        log_error("failed to prepare replay upsert: %s", sqlite3_errmsg(db));
        return -1;
    }

    DIR *dir = opendir(PENDING_WRITES_DIR);
    if (!dir) {
        sqlite3_finalize(stmt);
        return -1;
    }

    int rc = 0;
    struct dirent *ent = NULL;
    while ((ent = readdir(dir)) != NULL) {
        if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0) continue;

        char dash_key[128] = {0};
        if (sscanf(ent->d_name, "%127[^-]-", dash_key) != 1 || !is_valid_key(dash_key)) {
            continue;
        }

        char path[512] = {0};
        if (snprintf(path, sizeof(path), "%s/%s", PENDING_WRITES_DIR, ent->d_name) >= (int)sizeof(path)) {
            rc = -1;
            break;
        }

        FILE *f = fopen(path, "rb");
        if (!f) {
            rc = -1;
            break;
        }
        if (fseek(f, 0, SEEK_END) != 0) {
            fclose(f);
            rc = -1;
            break;
        }
        long file_len = ftell(f);
        if (file_len < 0 || file_len > 4 * 1024 * 1024) {
            fclose(f);
            rc = -1;
            break;
        }
        if (fseek(f, 0, SEEK_SET) != 0) {
            fclose(f);
            rc = -1;
            break;
        }

        char *payload = (char *)malloc((size_t)file_len + 1);
        if (!payload) {
            fclose(f);
            rc = -1;
            break;
        }
        size_t nread = fread(payload, 1, (size_t)file_len, f);
        fclose(f);
        if (nread != (size_t)file_len) {
            free(payload);
            rc = -1;
            break;
        }
        payload[file_len] = '\0';

        sqlite3_reset(stmt);
        sqlite3_clear_bindings(stmt);
        sqlite3_bind_text(stmt, 1, dash_key, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, payload, -1, SQLITE_TRANSIENT);
        int step_rc = sqlite3_step(stmt);
        free(payload);
        if (step_rc != SQLITE_DONE) {
            log_error("failed to replay pending write %s: %s", ent->d_name, sqlite3_errmsg(db));
            rc = -1;
            break;
        }

        if (unlink(path) != 0) {
            rc = -1;
            break;
        }
        log_warn("replayed pending write: %s", ent->d_name);
    }

    closedir(dir);
    sqlite3_finalize(stmt);
    if (rc == 0 && fsync_directory(PENDING_WRITES_DIR) != 0) return -1;
    return rc;
}

int init_db(const char *db_path) {
    sqlite3 *db = NULL;
    if (sqlite3_open_v2(db_path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, NULL) != SQLITE_OK) {
        log_error("failed to open db: %s", sqlite3_errmsg(db));
        if (db) sqlite3_close(db);
        return -1;
    }

    const char *schema_sql =
        "PRAGMA journal_mode=WAL;"
        "PRAGMA synchronous=FULL;"
        "PRAGMA fullfsync=ON;"
        "PRAGMA checkpoint_fullfsync=ON;"
        "PRAGMA temp_store=MEMORY;"
        "PRAGMA mmap_size=268435456;"
        "CREATE TABLE IF NOT EXISTS kv_store ("
        "data_key TEXT PRIMARY KEY,"
        "data_value TEXT NOT NULL,"
        "updated_at INTEGER NOT NULL"
        ");";

    char *err = NULL;
    if (sqlite3_exec(db, schema_sql, NULL, NULL, &err) != SQLITE_OK) {
        log_error("failed to init schema: %s", err ? err : "unknown");
        sqlite3_free(err);
        sqlite3_close(db);
        return -1;
    }

    if (replay_pending_writes(db) != 0) {
        log_error("failed to replay pending writes");
        sqlite3_close(db);
        return -1;
    }

    sqlite3_stmt *stmt = NULL;
    const char *upsert = "INSERT OR IGNORE INTO kv_store (data_key, data_value, updated_at) VALUES (?1, ?2, strftime('%s', 'now'));";
    if (sqlite3_prepare_v2(db, upsert, -1, &stmt, NULL) != SQLITE_OK) {
        log_error("failed to prepare init insert: %s", sqlite3_errmsg(db));
        sqlite3_close(db);
        return -1;
    }

    for (size_t i = 0; i < DATA_KEYS_COUNT; i++) {
        int is_object_key = strcmp(DATA_KEYS[i], "profile") == 0 || strcmp(DATA_KEYS[i], "app_settings") == 0;
        const char *default_json = is_object_key ? "{}" : "[]";
        sqlite3_bind_text(stmt, 1, DATA_KEYS[i], -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 2, default_json, -1, SQLITE_STATIC);
        if (sqlite3_step(stmt) != SQLITE_DONE) {
            log_error("failed to seed key %s: %s", DATA_KEYS[i], sqlite3_errmsg(db));
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

int worker_db_open(worker_db_t *db, const char *db_path) {
    memset(db, 0, sizeof(*db));
    if (sqlite3_open_v2(db_path, &db->db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, NULL) != SQLITE_OK) {
        log_error("worker failed to open db: %s", sqlite3_errmsg(db->db));
        if (db->db) sqlite3_close(db->db);
        return -1;
    }

    sqlite3_exec(db->db, "PRAGMA busy_timeout=5000;", NULL, NULL, NULL);
    sqlite3_exec(db->db, "PRAGMA synchronous=FULL;", NULL, NULL, NULL);
    sqlite3_exec(db->db, "PRAGMA fullfsync=ON;", NULL, NULL, NULL);
    sqlite3_exec(db->db, "PRAGMA checkpoint_fullfsync=ON;", NULL, NULL, NULL);
    sqlite3_exec(db->db, "PRAGMA temp_store=MEMORY;", NULL, NULL, NULL);
    sqlite3_exec(db->db, "PRAGMA mmap_size=268435456;", NULL, NULL, NULL);
    sqlite3_exec(db->db, "PRAGMA cache_size=-32768;", NULL, NULL, NULL);

    if (sqlite3_prepare_v2(db->db, "SELECT data_value FROM kv_store WHERE data_key=?1", -1, &db->get_stmt, NULL) != SQLITE_OK ||
        sqlite3_prepare_v2(db->db,
                           "INSERT INTO kv_store (data_key, data_value, updated_at) VALUES (?1, ?2, strftime('%s', 'now'))"
                           " ON CONFLICT(data_key) DO UPDATE SET data_value=excluded.data_value, updated_at=excluded.updated_at",
                           -1,
                           &db->upsert_stmt,
                           NULL) != SQLITE_OK ||
        sqlite3_prepare_v2(db->db, "SELECT json_valid(?1)", -1, &db->json_valid_stmt, NULL) != SQLITE_OK) {
        log_error("worker failed to prepare statements: %s", sqlite3_errmsg(db->db));
        worker_db_close(db);
        return -1;
    }

    return 0;
}

void worker_db_close(worker_db_t *db) {
    sqlite3_finalize(db->get_stmt);
    sqlite3_finalize(db->upsert_stmt);
    sqlite3_finalize(db->json_valid_stmt);
    if (db->db) sqlite3_close(db->db);
    memset(db, 0, sizeof(*db));
}
