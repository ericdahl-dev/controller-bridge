# The drawn jog display's firmware code (#455, #457), built natively for its tests. `make test` builds and runs them.
CC ?= cc
CFLAGS ?= -std=c99 -Wall -Wextra -Werror -pedantic -O1 -g
SAN := -fsanitize=address,undefined -fno-omit-frame-pointer
BUILD := build
SRC := $(wildcard src/*.c)
TESTS := $(wildcard test/test_*.c)

.PHONY: test clean
test: $(BUILD)/tests
	$(BUILD)/tests

$(BUILD)/tests: $(SRC) $(TESTS) test/harness.c test/harness.h $(wildcard src/*.h)
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) $(SAN) -Isrc -Itest -o $@ $(SRC) $(TESTS) test/harness.c

clean:
	rm -rf $(BUILD)
