#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#include "../server.h"

static void test_valid_key(void) {
    assert(is_valid_key("activities"));
    assert(is_valid_key("profile"));
    assert(is_valid_key("lactate_history_records"));
    assert(!is_valid_key("unknown"));
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

int main(void) {
    test_valid_key();
    test_parse_bind_addr();
    test_read_content_length();
    test_socket_send_flags();
    test_configure_socket_after_accept();
    puts("unit tests passed");
    return 0;
}
