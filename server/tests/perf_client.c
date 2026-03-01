#include <arpa/inet.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

typedef struct {
    const char *host;
    int port;
    int requests;
    atomic_int *success;
    atomic_int *failed;
} worker_args_t;

static int send_all(int fd, const char *buf, size_t len) {
    size_t sent = 0;
    while (sent < len) {
        ssize_t n = send(fd, buf + sent, len - sent, 0);
        if (n <= 0) return -1;
        sent += (size_t)n;
    }
    return 0;
}

static int request_once(const char *host, int port, const char *req) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, host, &addr.sin_addr) <= 0) {
        close(fd);
        return -1;
    }
    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        return -1;
    }

    if (send_all(fd, req, strlen(req)) != 0) {
        close(fd);
        return -1;
    }

    char buf[1024];
    ssize_t n = recv(fd, buf, sizeof(buf) - 1, 0);
    close(fd);
    if (n <= 0) return -1;
    buf[n] = '\0';
    return (strstr(buf, "HTTP/1.1 200") == buf || strstr(buf, "HTTP/1.1 204") == buf) ? 0 : -1;
}

static void *worker(void *arg) {
    worker_args_t *w = (worker_args_t *)arg;
    const char *get_req = "GET /v1/data/activities HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n";
    for (int i = 0; i < w->requests; i++) {
        if (request_once(w->host, w->port, get_req) == 0) {
            atomic_fetch_add(w->success, 1);
        } else {
            atomic_fetch_add(w->failed, 1);
        }
    }
    return NULL;
}

int main(int argc, char **argv) {
    int total = argc > 1 ? atoi(argv[1]) : 50000;
    int concurrency = argc > 2 ? atoi(argv[2]) : 512;
    const char *host = argc > 3 ? argv[3] : "127.0.0.1";
    int port = argc > 4 ? atoi(argv[4]) : 8080;

    if (total <= 0 || concurrency <= 0) {
        fprintf(stderr, "invalid args\n");
        return 1;
    }

    const char *put_req =
        "PUT /v1/data/activities HTTP/1.1\r\n"
        "Host: 127.0.0.1\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 21\r\n"
        "Connection: close\r\n\r\n"
        "[{\"sport\":\"cycling\"}]";
    if (request_once(host, port, put_req) != 0) {
        fprintf(stderr, "warmup put failed\n");
        return 1;
    }

    pthread_t *threads = calloc((size_t)concurrency, sizeof(pthread_t));
    worker_args_t *args = calloc((size_t)concurrency, sizeof(worker_args_t));
    if (!threads || !args) return 1;

    atomic_int success = 0;
    atomic_int failed = 0;

    int base = total / concurrency;
    int rem = total % concurrency;

    struct timeval start, end;
    gettimeofday(&start, NULL);

    for (int i = 0; i < concurrency; i++) {
        args[i].host = host;
        args[i].port = port;
        args[i].requests = base + (i < rem ? 1 : 0);
        args[i].success = &success;
        args[i].failed = &failed;
        pthread_create(&threads[i], NULL, worker, &args[i]);
    }

    for (int i = 0; i < concurrency; i++) pthread_join(threads[i], NULL);

    gettimeofday(&end, NULL);
    double elapsed = (end.tv_sec - start.tv_sec) + (end.tv_usec - start.tv_usec) / 1000000.0;

    int s = atomic_load(&success);
    int f = atomic_load(&failed);
    printf("total_requests=%d\n", total);
    printf("success=%d\n", s);
    printf("failed=%d\n", f);
    printf("elapsed_ms=%.0f\n", elapsed * 1000);
    printf("rps=%.2f\n", elapsed > 0 ? (double)s / elapsed : 0.0);

    free(threads);
    free(args);
    return f == 0 ? 0 : 1;
}
