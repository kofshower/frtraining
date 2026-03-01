CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra -Werror -std=c11 -pthread
LDFLAGS ?= -lsqlite3 -pthread

BIN := fricu-server
SRC := main.c

.PHONY: all clean run

all: $(BIN)

$(BIN): $(SRC)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

run: $(BIN)
	./$(BIN)

clean:
	rm -f $(BIN)
