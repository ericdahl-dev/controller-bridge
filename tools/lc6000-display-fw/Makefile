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
	sh test/check_symbols.sh $(BUILD)/freestanding

# The shared message vectors (#456), as a C header for the vectors walk.
$(BUILD)/vectors.h: vectors/messages.json test/vectors_to_c.py
	@mkdir -p $(BUILD)
	python3 -I test/vectors_to_c.py $< > $@

$(BUILD)/tests: $(SRC) $(TESTS) test/harness.c test/harness.h $(wildcard src/*.h) $(BUILD)/vectors.h
	$(CC) $(CFLAGS) $(SAN) -Isrc -Itest -I$(BUILD) -o $@ $(SRC) $(TESTS) test/harness.c

clean:
	rm -rf $(BUILD)

# The hook into the stock wd image (#467): its portable logic, tested natively (`make arm-test`).
ARM_TESTS := $(wildcard arm/test/test_*.c)
.PHONY: arm-test
arm-test: $(BUILD)/hook-tests
	$(BUILD)/hook-tests
	sh arm/check_symbols.sh $(BUILD)/freestanding-arm

$(BUILD)/hook-tests: $(SRC) arm/hook.c arm/hook.h $(ARM_TESTS) test/harness.c test/harness.h $(wildcard src/*.h)
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) $(SAN) -Isrc -Itest -Iarm -o $@ $(SRC) arm/hook.c $(ARM_TESTS) test/harness.c
