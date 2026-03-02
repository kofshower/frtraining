#ifndef FRICU_SERVER_H
#define FRICU_SERVER_H

#include <stdbool.h>
#include <stddef.h>

bool is_valid_key(const char *key);
int parse_bind_addr(const char *bind_addr_str, char *host, size_t host_len, int *port);
int read_content_length(const char *req, const char *header_end);
int socket_send_flags(void);
int configure_socket_after_accept(int fd);

#endif
