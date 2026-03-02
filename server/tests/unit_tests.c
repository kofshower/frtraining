#include <assert.h>
#include <stdio.h>
#include <string.h>

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
}

int main(void) {
    test_valid_key();
    test_parse_bind_addr();
    test_read_content_length();
    puts("unit tests passed");
    return 0;
}
