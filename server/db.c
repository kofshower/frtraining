#define _GNU_SOURCE

#include "server_internal.h"
#include "server.h"
#include "logger.h"

#include <ctype.h>
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

static void extract_log_id_from_pending_name(const char *name, char *out, size_t out_len) {
    if (!out || out_len == 0) return;
    out[0] = '\0';
    if (!name) return;

    const char *marker = strstr(name, "-lid-");
    if (!marker) return;
    marker += 5;

    const char *end = strstr(marker, ".json");
    if (!end || end <= marker) {
        end = marker + strlen(marker);
    }

    size_t len = (size_t)(end - marker);
    if (len >= out_len) {
        len = out_len - 1;
    }
    memcpy(out, marker, len);
    out[len] = '\0';
}

static int extract_pending_key_from_name(const char *name, char *out_key, size_t out_key_len) {
    if (!name || !out_key || out_key_len == 0) return 0;
    out_key[0] = '\0';

    size_t len = strlen(name);
    if (len < 6 || strcmp(name + len - 5, ".json") != 0) {
        return 0;
    }

    char local[512] = {0};
    if (len >= sizeof(local)) return 0;
    memcpy(local, name, len - 5);
    local[len - 5] = '\0';

    char *lid = strstr(local, "-lid-");
    if (lid) {
        *lid = '\0';
    }

    char *cursor = local + strlen(local);
    for (int i = 0; i < 3; i++) {
        char *dash = strrchr(local, '-');
        if (!dash || dash >= cursor) return 0;
        char *digits = dash + 1;
        if (*digits == '\0') return 0;
        for (char *p = digits; *p != '\0'; p++) {
            if (!isdigit((unsigned char)(*p))) {
                return 0;
            }
        }
        *dash = '\0';
        cursor = dash;
    }

    size_t key_len = strlen(local);
    if (key_len == 0 || key_len >= out_key_len) return 0;
    memcpy(out_key, local, key_len + 1);
    return 1;
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

        char dash_key[256] = {0};
        if (!extract_pending_key_from_name(ent->d_name, dash_key, sizeof(dash_key)) ||
            !is_valid_storage_key(dash_key)) {
            continue;
        }

        char path[512] = {0};
        if (snprintf(path, sizeof(path), "%s/%s", PENDING_WRITES_DIR, ent->d_name) >= (int)sizeof(path)) {
            rc = -1;
            break;
        }
        char log_id[96] = {0};
        extract_log_id_from_pending_name(ent->d_name, log_id, sizeof(log_id));
        const char *effective_log_id = log_id[0] != '\0' ? log_id : "-";
        log_info("DATA WRITE replaying key=%s pending=%s logid=%s", dash_key, path, effective_log_id);

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
            log_error(
                "DATA WRITE replay failed key=%s pending=%s logid=%s reason=sqlite_step_error errmsg=%s",
                dash_key,
                path,
                effective_log_id,
                sqlite3_errmsg(db));
            rc = -1;
            break;
        }

        if (unlink(path) != 0) {
            rc = -1;
            break;
        }
        log_info("DATA WRITE replayed key=%s status=stored pending=%s logid=%s", dash_key, path, effective_log_id);
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
