CC ?= gcc
CFLAGS ?= -O3 -Wall -Wextra -Werror -std=c11 -pthread
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
  CFLAGS += -march=native
endif
LDFLAGS ?= -lsqlite3 -pthread
SAN_FLAGS ?= -fsanitize=address,undefined -fno-omit-frame-pointer

BIN := fricu-server
SRC := main.c util.c db.c http.c event_loop.c logger.c
TEST_BIN := unit-tests
TEST_SRC := tests/unit_tests.c
PERF_BIN := perf-client
PERF_SRC := tests/perf_client.c

.PHONY: all clean run test perf-test build-perf-client test-asan

all: $(BIN)

$(BIN): $(SRC) server.h
	$(CC) $(CFLAGS) -o $@ $(SRC) $(LDFLAGS)

$(TEST_BIN): $(TEST_SRC) $(SRC) server.h
	$(CC) $(CFLAGS) -Wno-unused-function -DFRICU_UNIT_TEST -o $@ $(TEST_SRC) $(SRC) $(LDFLAGS)

$(PERF_BIN): $(PERF_SRC)
	$(CC) $(CFLAGS) -o $@ $(PERF_SRC)

build-perf-client: $(PERF_BIN)

run: $(BIN)
	./$(BIN)

test: $(TEST_BIN)
	./$(TEST_BIN)

test-asan:
	$(MAKE) clean
	$(MAKE) CFLAGS="$(CFLAGS) $(SAN_FLAGS)" LDFLAGS="$(LDFLAGS) $(SAN_FLAGS)" $(TEST_BIN)
	ASAN_OPTIONS=detect_leaks=1 ./$(TEST_BIN)

perf-test: $(BIN) $(PERF_BIN)
	./tests/perf_50k.sh

clean:
	rm -f $(BIN) $(TEST_BIN) $(PERF_BIN)
