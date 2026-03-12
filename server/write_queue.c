#define _GNU_SOURCE

#include "server_internal.h"
#include "logger.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <pthread.h>
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

typedef struct write_job {
    char logical_key[128];
    char storage_key[256];
    char account_id[128];
    char log_id[96];
    char pending_path[512];
    char *payload;
    size_t payload_len;
    int refcount;
    int completed;
    int abandoned;
    int status_code;
    int sqlite_rc;
    int sqlite_ext;
    int retry_count;
    char backup_path[512];
    pthread_mutex_t mutex;
    pthread_cond_t cond;
    struct write_job *next;
} write_job_t;

typedef struct {
    pthread_mutex_t mutex;
    pthread_cond_t cond;
    pthread_t thread;
    int running;
    int stopping;
    int refcount;
    sqlite3 *db;
    sqlite3_stmt *upsert_stmt;
    char db_path[512];
    int queue_depth;
    char last_success_logid[96];
    char last_error_logid[96];
    write_job_t *head;
    write_job_t *tail;
} write_dispatcher_t;

static write_dispatcher_t g_dispatcher = {
    .mutex = PTHREAD_MUTEX_INITIALIZER,
    .cond = PTHREAD_COND_INITIALIZER,
};

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

static int remove_pending_write(const char *path) {
    if (!path || path[0] == '\0') return -1;
    if (unlink(path) != 0) return -1;
    return fsync_directory("pending_writes");
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

static void write_job_release(write_job_t *job) {
    int should_free = 0;
    pthread_mutex_lock(&job->mutex);
    job->refcount--;
    should_free = (job->refcount == 0);
    pthread_mutex_unlock(&job->mutex);
    if (!should_free) return;

    pthread_cond_destroy(&job->cond);
    pthread_mutex_destroy(&job->mutex);
    free(job->payload);
    free(job);
}

static void finalize_job(write_job_t *job) {
    pthread_mutex_lock(&job->mutex);
    job->completed = 1;
    pthread_cond_broadcast(&job->cond);
    pthread_mutex_unlock(&job->mutex);
}

static void abandon_job(write_job_t *job) {
    pthread_mutex_lock(&job->mutex);
    job->abandoned = 1;
    pthread_cond_broadcast(&job->cond);
    pthread_mutex_unlock(&job->mutex);
}

static int dispatcher_open_db(write_dispatcher_t *dispatcher) {
    if (dispatcher->db) return 0;

    if (sqlite3_open_v2(
            dispatcher->db_path,
            &dispatcher->db,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            NULL) != SQLITE_OK) {
        log_error("write dispatcher failed to open db: %s", dispatcher->db ? sqlite3_errmsg(dispatcher->db) : "unknown");
        if (dispatcher->db) sqlite3_close(dispatcher->db);
        dispatcher->db = NULL;
        return -1;
    }

    sqlite3_exec(dispatcher->db, "PRAGMA busy_timeout=250;", NULL, NULL, NULL);
    sqlite3_exec(dispatcher->db, "PRAGMA synchronous=FULL;", NULL, NULL, NULL);
    sqlite3_exec(dispatcher->db, "PRAGMA fullfsync=ON;", NULL, NULL, NULL);
    sqlite3_exec(dispatcher->db, "PRAGMA checkpoint_fullfsync=ON;", NULL, NULL, NULL);
    sqlite3_exec(dispatcher->db, "PRAGMA temp_store=MEMORY;", NULL, NULL, NULL);
    sqlite3_exec(dispatcher->db, "PRAGMA mmap_size=268435456;", NULL, NULL, NULL);
    sqlite3_exec(dispatcher->db, "PRAGMA cache_size=-32768;", NULL, NULL, NULL);

    const char *upsert_sql =
        "INSERT INTO kv_store (data_key, data_value, updated_at) VALUES (?1, ?2, strftime('%s', 'now'))"
        " ON CONFLICT(data_key) DO UPDATE SET data_value=excluded.data_value, updated_at=excluded.updated_at";
    if (sqlite3_prepare_v2(dispatcher->db, upsert_sql, -1, &dispatcher->upsert_stmt, NULL) != SQLITE_OK) {
        log_error("write dispatcher failed to prepare statements: %s", sqlite3_errmsg(dispatcher->db));
        sqlite3_close(dispatcher->db);
        dispatcher->db = NULL;
        dispatcher->upsert_stmt = NULL;
        return -1;
    }

    return 0;
}

static void dispatcher_close_db(write_dispatcher_t *dispatcher) {
    sqlite3_finalize(dispatcher->upsert_stmt);
    dispatcher->upsert_stmt = NULL;
    if (dispatcher->db) sqlite3_close(dispatcher->db);
    dispatcher->db = NULL;
}

static void *write_dispatcher_thread_entry(void *arg) {
    write_dispatcher_t *dispatcher = (write_dispatcher_t *)arg;

    while (1) {
        pthread_mutex_lock(&dispatcher->mutex);
        while (!dispatcher->stopping && dispatcher->head == NULL) {
            pthread_cond_wait(&dispatcher->cond, &dispatcher->mutex);
        }

        if (dispatcher->stopping && dispatcher->head == NULL) {
            pthread_mutex_unlock(&dispatcher->mutex);
            break;
        }

        write_job_t *job = dispatcher->head;
        if (job) {
            dispatcher->head = job->next;
            if (!dispatcher->head) dispatcher->tail = NULL;
            job->next = NULL;
            if (dispatcher->queue_depth > 0) {
                dispatcher->queue_depth--;
            }
        }
        int stopping = dispatcher->stopping;
        pthread_mutex_unlock(&dispatcher->mutex);

        if (!job) continue;
        if (stopping) {
            abandon_job(job);
            write_job_release(job);
            continue;
        }

        if (dispatcher_open_db(dispatcher) != 0) {
            job->status_code = 500;
            pthread_mutex_lock(&dispatcher->mutex);
            snprintf(dispatcher->last_error_logid, sizeof(dispatcher->last_error_logid), "%s", job->log_id);
            pthread_mutex_unlock(&dispatcher->mutex);
            finalize_job(job);
            write_job_release(job);
            continue;
        }

        while (1) {
            sqlite3_reset(dispatcher->upsert_stmt);
            sqlite3_clear_bindings(dispatcher->upsert_stmt);
            sqlite3_bind_text(dispatcher->upsert_stmt, 1, job->storage_key, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(dispatcher->upsert_stmt, 2, job->payload, -1, SQLITE_TRANSIENT);

            int rc = sqlite3_step(dispatcher->upsert_stmt);
            int ext = sqlite3_extended_errcode(dispatcher->db);

            if (rc == SQLITE_DONE) {
                if (remove_pending_write(job->pending_path) != 0) {
                    job->status_code = 500;
                    pthread_mutex_lock(&dispatcher->mutex);
                    snprintf(dispatcher->last_error_logid, sizeof(dispatcher->last_error_logid), "%s", job->log_id);
                    pthread_mutex_unlock(&dispatcher->mutex);
                    log_error(
                        "DATA WRITE failed key=%s reason=pending_write_cleanup_failed path=%s account=%s logid=%s",
                        job->logical_key,
                        job->pending_path,
                        job->account_id,
                        job->log_id);
                } else {
                    job->status_code = 204;
                    pthread_mutex_lock(&dispatcher->mutex);
                    snprintf(dispatcher->last_success_logid, sizeof(dispatcher->last_success_logid), "%s", job->log_id);
                    pthread_mutex_unlock(&dispatcher->mutex);
                    log_info(
                        "DATA WRITE key=%s status=stored bytes=%zu account=%s logid=%s retries=%d",
                        job->logical_key,
                        job->payload_len,
                        job->account_id,
                        job->log_id,
                        job->retry_count);
                }
                finalize_job(job);
                break;
            }

            if (rc == SQLITE_BUSY || rc == SQLITE_LOCKED || ext == SQLITE_BUSY_SNAPSHOT || ext == SQLITE_BUSY_TIMEOUT) {
                job->retry_count++;
                log_warn(
                    "DATA WRITE retrying key=%s account=%s logid=%s attempt=%d rc=%d bytes=%zu",
                    job->logical_key,
                    job->account_id,
                    job->log_id,
                    job->retry_count,
                    rc,
                    job->payload_len);

                pthread_mutex_lock(&dispatcher->mutex);
                int should_stop = dispatcher->stopping;
                pthread_mutex_unlock(&dispatcher->mutex);
                if (should_stop) {
                    abandon_job(job);
                    break;
                }

                struct timespec ts = {.tv_sec = 0, .tv_nsec = (long)(20000000 * (job->retry_count < 10 ? job->retry_count : 10))};
                nanosleep(&ts, NULL);
                continue;
            }

            job->status_code = 500;
            job->sqlite_rc = rc;
            job->sqlite_ext = ext;
            if (persist_failed_payload(
                    job->logical_key,
                    job->payload,
                    job->payload_len,
                    rc,
                    ext,
                    job->backup_path,
                    sizeof(job->backup_path)) != 0) {
                job->backup_path[0] = '\0';
            }
            log_error(
                "DATA WRITE failed key=%s reason=sqlite_step_error rc=%d rc_name=%s ext=%d ext_name=%s errmsg=%s bytes=%zu backup=%s account=%s logid=%s retries=%d",
                job->logical_key,
                rc,
                sqlite3_errstr(rc),
                ext,
                sqlite3_errstr(ext),
                sqlite3_errmsg(dispatcher->db),
                job->payload_len,
                job->backup_path[0] != '\0' ? job->backup_path : "none",
                job->account_id,
                job->log_id,
                job->retry_count);
            pthread_mutex_lock(&dispatcher->mutex);
            snprintf(dispatcher->last_error_logid, sizeof(dispatcher->last_error_logid), "%s", job->log_id);
            pthread_mutex_unlock(&dispatcher->mutex);
            finalize_job(job);
            break;
        }

        write_job_release(job);
    }

    dispatcher_close_db(dispatcher);
    return NULL;
}

int write_dispatcher_acquire(const char *db_path) {
    if (!db_path || db_path[0] == '\0') return -1;

    pthread_mutex_lock(&g_dispatcher.mutex);
    if (g_dispatcher.refcount > 0 && strcmp(g_dispatcher.db_path, db_path) != 0) {
        pthread_mutex_unlock(&g_dispatcher.mutex);
        log_error("write dispatcher path mismatch existing=%s requested=%s", g_dispatcher.db_path, db_path);
        return -1;
    }

    if (g_dispatcher.refcount == 0) {
        snprintf(g_dispatcher.db_path, sizeof(g_dispatcher.db_path), "%s", db_path);
        g_dispatcher.stopping = 0;
        g_dispatcher.queue_depth = 0;
        g_dispatcher.last_success_logid[0] = '\0';
        g_dispatcher.last_error_logid[0] = '\0';
        g_dispatcher.head = NULL;
        g_dispatcher.tail = NULL;
        if (pthread_create(&g_dispatcher.thread, NULL, write_dispatcher_thread_entry, &g_dispatcher) != 0) {
            g_dispatcher.db_path[0] = '\0';
            pthread_mutex_unlock(&g_dispatcher.mutex);
            log_error("failed to start write dispatcher thread");
            return -1;
        }
        g_dispatcher.running = 1;
    }

    g_dispatcher.refcount++;
    pthread_mutex_unlock(&g_dispatcher.mutex);
    return 0;
}

void write_dispatcher_release(void) {
    pthread_mutex_lock(&g_dispatcher.mutex);
    if (g_dispatcher.refcount == 0) {
        pthread_mutex_unlock(&g_dispatcher.mutex);
        return;
    }

    g_dispatcher.refcount--;
    if (g_dispatcher.refcount > 0) {
        pthread_mutex_unlock(&g_dispatcher.mutex);
        return;
    }

    g_dispatcher.stopping = 1;
    pthread_cond_broadcast(&g_dispatcher.cond);
    write_job_t *jobs = g_dispatcher.head;
    g_dispatcher.head = NULL;
    g_dispatcher.tail = NULL;
    pthread_mutex_unlock(&g_dispatcher.mutex);

    while (jobs) {
        write_job_t *next = jobs->next;
        jobs->next = NULL;
        abandon_job(jobs);
        write_job_release(jobs);
        jobs = next;
    }

    if (g_dispatcher.running) {
        pthread_join(g_dispatcher.thread, NULL);
    }

    pthread_mutex_lock(&g_dispatcher.mutex);
    g_dispatcher.running = 0;
    g_dispatcher.stopping = 0;
    g_dispatcher.db_path[0] = '\0';
    pthread_mutex_unlock(&g_dispatcher.mutex);
}

int write_dispatch_submit(
    const char *logical_key,
    const char *storage_key,
    const char *payload,
    size_t payload_len,
    const char *pending_path,
    const char *account_id,
    const char *log_id,
    int wait_timeout_ms,
    write_dispatch_result_t *out_result) {
    if (!logical_key || !storage_key || !payload || !pending_path || !account_id || !log_id || !out_result) return -1;
    memset(out_result, 0, sizeof(*out_result));

    write_job_t *job = (write_job_t *)calloc(1, sizeof(write_job_t));
    if (!job) return -1;

    job->payload = (char *)malloc(payload_len + 1);
    if (!job->payload) {
        free(job);
        return -1;
    }

    memcpy(job->payload, payload, payload_len);
    job->payload[payload_len] = '\0';
    job->payload_len = payload_len;
    job->refcount = 2;
    snprintf(job->logical_key, sizeof(job->logical_key), "%s", logical_key);
    snprintf(job->storage_key, sizeof(job->storage_key), "%s", storage_key);
    snprintf(job->account_id, sizeof(job->account_id), "%s", account_id);
    snprintf(job->log_id, sizeof(job->log_id), "%s", log_id);
    snprintf(job->pending_path, sizeof(job->pending_path), "%s", pending_path);
    pthread_mutex_init(&job->mutex, NULL);
    pthread_cond_init(&job->cond, NULL);

    pthread_mutex_lock(&g_dispatcher.mutex);
    if (!g_dispatcher.running || g_dispatcher.stopping) {
        pthread_mutex_unlock(&g_dispatcher.mutex);
        write_job_release(job);
        write_job_release(job);
        return -1;
    }

    if (g_dispatcher.tail) {
        g_dispatcher.tail->next = job;
    } else {
        g_dispatcher.head = job;
    }
    g_dispatcher.tail = job;
    g_dispatcher.queue_depth++;
    pthread_cond_signal(&g_dispatcher.cond);
    pthread_mutex_unlock(&g_dispatcher.mutex);

    pthread_mutex_lock(&job->mutex);
    if (!job->completed && !job->abandoned && wait_timeout_ms > 0) {
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        ts.tv_sec += wait_timeout_ms / 1000;
        ts.tv_nsec += (long)(wait_timeout_ms % 1000) * 1000000L;
        if (ts.tv_nsec >= 1000000000L) {
            ts.tv_sec += 1;
            ts.tv_nsec -= 1000000000L;
        }

        while (!job->completed && !job->abandoned) {
            int wait_rc = pthread_cond_timedwait(&job->cond, &job->mutex, &ts);
            if (wait_rc == ETIMEDOUT) break;
        }
    }

    int completed = job->completed;
    if (completed) {
        out_result->completed = 1;
        out_result->status_code = job->status_code;
        out_result->sqlite_rc = job->sqlite_rc;
        out_result->sqlite_ext = job->sqlite_ext;
        out_result->retry_count = job->retry_count;
        snprintf(out_result->backup_path, sizeof(out_result->backup_path), "%s", job->backup_path);
    }
    pthread_mutex_unlock(&job->mutex);

    write_job_release(job);
    return completed ? 0 : 1;
}

void write_dispatch_diagnostics_snapshot(write_dispatch_diagnostics_t *out_diag) {
    if (!out_diag) return;
    memset(out_diag, 0, sizeof(*out_diag));

    pthread_mutex_lock(&g_dispatcher.mutex);
    out_diag->running = g_dispatcher.running && !g_dispatcher.stopping;
    out_diag->queue_depth = g_dispatcher.queue_depth;
    snprintf(out_diag->last_success_logid, sizeof(out_diag->last_success_logid), "%s", g_dispatcher.last_success_logid);
    snprintf(out_diag->last_error_logid, sizeof(out_diag->last_error_logid), "%s", g_dispatcher.last_error_logid);
    pthread_mutex_unlock(&g_dispatcher.mutex);
}
