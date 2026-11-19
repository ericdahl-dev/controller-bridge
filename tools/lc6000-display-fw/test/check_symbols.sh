#!/bin/sh
# The firmware sources build freestanding and need nothing from libc but the four functions GCC's freestanding mode
# expects (memcpy, memmove, memset, memcmp): no allocation, no stdio (#455). Apple clang spells memset as bzero. Builds src/*.c without sanitizers and lists what they leave undefined.
set -eu
out=${1:-build/freestanding}
mkdir -p "$out"
bad=""
for source in src/*.c; do
    object="$out/$(basename "$source" .c).o"
    ${CC:-cc} -std=c99 -Wall -Wextra -Werror -pedantic -O2 -ffreestanding -fno-stack-protector -c "$source" -o "$object"
    for symbol in $(nm -u "$object" | awk '{print $NF}' | sed 's/^_//'); do
        case "$symbol" in
            memcpy|memmove|memset|memcmp|bzero) ;;
            *) bad="$bad $symbol($source)" ;;
        esac
    done
done
if [ -n "$bad" ]; then
    echo "not allowed in firmware sources:$bad" >&2
    exit 1
fi
echo "freestanding: only memcpy, memmove, memset and memcmp"
