#define _GNU_SOURCE
#include "server_internal.h"
#include "logger.h"

#include <errno.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#if defined(__linux__)
#include <sys/epoll.h>
#elif defined(__APPLE__)
#include <sys/event.h>
#include <sys/time.h>
#else
#error "Unsupported platform: only Linux and macOS are supported"
#endif

static void close_conn(int qfd, conn_t **conns, int fd) {
    if (fd < 0) return;
#if defined(__linux__)
    epoll_ctl(qfd, EPOLL_CTL_DEL, fd, NULL);
#elif defined(__APPLE__)
    struct kevent ev;
    EV_SET(&ev, fd, EVFILT_READ, EV_DELETE, 0, 0, NULL);
    kevent(qfd, &ev, 1, NULL, 0, NULL);
#endif
    if (conns[fd]) {
        free(conns[fd]->buf);
        free(conns[fd]);
        conns[fd] = NULL;
    }
    close(fd);
}

static int register_listen_fd(int qfd, int listen_fd) {
#if defined(__linux__)
    struct epoll_event ev;
    memset(&ev, 0, sizeof(ev));
    ev.events = EPOLLIN;
#ifdef EPOLLEXCLUSIVE
    ev.events |= EPOLLEXCLUSIVE;
#endif
    ev.data.fd = listen_fd;
    return epoll_ctl(qfd, EPOLL_CTL_ADD, listen_fd, &ev);
#elif defined(__APPLE__)
    struct kevent ev;
    EV_SET(&ev, listen_fd, EVFILT_READ, EV_ADD | EV_ENABLE, 0, 0, NULL);
    return kevent(qfd, &ev, 1, NULL, 0, NULL);
#endif
}

static int register_client_fd(int qfd, int fd) {
#if defined(__linux__)
    struct epoll_event ev;
    memset(&ev, 0, sizeof(ev));
    ev.events = EPOLLIN | EPOLLRDHUP;
    ev.data.fd = fd;
    return epoll_ctl(qfd, EPOLL_CTL_ADD, fd, &ev);
#elif defined(__APPLE__)
    struct kevent ev;
    EV_SET(&ev, fd, EVFILT_READ, EV_ADD | EV_ENABLE, 0, 0, NULL);
    return kevent(qfd, &ev, 1, NULL, 0, NULL);
#endif
}

static int queue_wait(int qfd, int listen_fd, int *fds, int *is_err, int max_events) {
#if defined(__linux__)
    struct epoll_event events[EVENT_MAX_EVENTS];
    int n = epoll_wait(qfd, events, max_events, -1);
    if (n < 0) return n;
    for (int i = 0; i < n; i++) {
        fds[i] = events[i].data.fd;
        is_err[i] = (events[i].events & (EPOLLERR | EPOLLHUP | EPOLLRDHUP)) != 0 && events[i].data.fd != listen_fd;
    }
    return n;
#elif defined(__APPLE__)
    struct kevent events[EVENT_MAX_EVENTS];
    int n = kevent(qfd, NULL, 0, events, max_events, NULL);
    if (n < 0) return n;
    for (int i = 0; i < n; i++) {
        fds[i] = (int)events[i].ident;
        is_err[i] = ((events[i].flags & EV_EOF) != 0 || events[i].filter == EV_ERROR) && (int)events[i].ident != listen_fd;
    }
    return n;
#endif
}

static int accept_client(int listen_fd) {
#if defined(__linux__)
    int client_fd = accept4(listen_fd, NULL, NULL, SOCK_NONBLOCK | SOCK_CLOEXEC);
    if (client_fd >= 0) return client_fd;
    if (!(errno == ENOSYS || errno == EINVAL)) return -1;
#endif
    int fd = accept(listen_fd, NULL, NULL);
    if (fd >= 0) {
        if (set_nonblocking(fd) != 0) {
            close(fd);
            return -1;
        }
    }
    return fd;
}

int run_worker_loop(int listen_fd, const char *db_path, size_t max_fds) {
    worker_db_t db;
    if (worker_db_open(&db, db_path) != 0) return -1;

#if defined(__linux__)
    int qfd = epoll_create1(0);
#else
    int qfd = kqueue();
#endif
    if (qfd < 0) {
        log_error("failed to create event queue: errno=%d", errno);
        worker_db_close(&db);
        return -1;
    }

    conn_t **conns = (conn_t **)calloc(max_fds + 1, sizeof(conn_t *));
    if (!conns) {
        close(qfd);
        worker_db_close(&db);
        return -1;
    }

    if (register_listen_fd(qfd, listen_fd) != 0) {
        log_error("failed to register listen fd in event queue: errno=%d", errno);
        free(conns);
        close(qfd);
        worker_db_close(&db);
        return -1;
    }

    int fds[EVENT_MAX_EVENTS];
    int errs[EVENT_MAX_EVENTS];

    while (1) {
        int n = queue_wait(qfd, listen_fd, fds, errs, EVENT_MAX_EVENTS);
        if (n < 0) {
            if (errno == EINTR) continue;
            log_warn("event wait error: errno=%d", errno);
            continue;
        }

        for (int i = 0; i < n; i++) {
            int fd = fds[i];
            if (fd == listen_fd) {
                while (1) {
                    int client_fd = accept_client(listen_fd);
                    if (client_fd < 0) {
                        if (errno == EAGAIN || errno == EWOULDBLOCK) break;
                        if (errno == EINTR) continue;
                        break;
                    }

                    if ((size_t)client_fd > max_fds) {
                        close(client_fd);
                        continue;
                    }

                    int nodelay = 1;
                    setsockopt(client_fd, IPPROTO_TCP, TCP_NODELAY, &nodelay, sizeof(nodelay));
                    if (configure_socket_after_accept(client_fd) != 0) {
                        close(client_fd);
                        continue;
                    }

                    conn_t *conn = (conn_t *)calloc(1, sizeof(conn_t));
                    if (!conn) {
                        close(client_fd);
                        continue;
                    }
                    conn->cap = CONN_INIT_BUF;
                    conn->buf = (char *)malloc(conn->cap + 1);
                    if (!conn->buf) {
                        free(conn);
                        close(client_fd);
                        continue;
                    }
                    conn->fd = client_fd;
                    conns[client_fd] = conn;

                    if (register_client_fd(qfd, client_fd) != 0) {
                        close_conn(qfd, conns, client_fd);
                    }
                }
                continue;
            }

            if (errs[i]) {
                close_conn(qfd, conns, fd);
                continue;
            }

            conn_t *conn = (fd >= 0 && (size_t)fd <= max_fds) ? conns[fd] : NULL;
            if (!conn) {
                close(fd);
                continue;
            }

            while (1) {
                if (conn->len == conn->cap && conn->cap < REQ_BUF_SIZE) {
                    size_t next = conn->cap * 2;
                    if (next > REQ_BUF_SIZE) next = REQ_BUF_SIZE;
                    char *nb = (char *)realloc(conn->buf, next + 1);
                    if (!nb) {
                        send_response(fd, 500, "Internal Server Error", "{\"error\":\"oom\"}");
                        close_conn(qfd, conns, fd);
                        break;
                    }
                    conn->buf = nb;
                    conn->cap = next;
                }

                ssize_t r = recv(fd, conn->buf + conn->len, conn->cap - conn->len, 0);
                if (r > 0) {
                    conn->len += (size_t)r;
                    if (conn->len >= REQ_BUF_SIZE) {
                        send_response(fd, 413, "Payload Too Large", "{\"error\":\"request too large\"}");
                        close_conn(qfd, conns, fd);
                        break;
                    }

                    int done = try_process_client(fd, &db, conn);
                    if (done == 1) {
                        close_conn(qfd, conns, fd);
                        break;
                    }
                    continue;
                }
                if (r == 0) {
                    close_conn(qfd, conns, fd);
                    break;
                }
                if (errno == EAGAIN || errno == EWOULDBLOCK) break;
                if (errno == EINTR) continue;
                close_conn(qfd, conns, fd);
                break;
            }
        }
    }
}
