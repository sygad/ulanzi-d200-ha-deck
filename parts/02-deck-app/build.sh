#!/bin/sh
# Builds the device app for the deck (32-bit ARM Linux, static, no libc).
#
# The code is freestanding, so any ARM compiler will do. This script uses what
# a Mac already has: Apple's clang to compile, and an ELF-capable lld to link.
# Set LLD to point at one if yours lives somewhere else, or use a cross gcc:
#   arm-linux-gnueabihf-gcc -O2 -ffreestanding -nostdlib -static -o build/deckd deckd.c
set -e
cd "$(dirname "$0")"
mkdir -p build

LLD="${LLD:-}"
for c in ld.lld /opt/homebrew/opt/llvm/bin/ld.lld /opt/homebrew/opt/lld/bin/ld.lld \
         /opt/homebrew/opt/emscripten/libexec/llvm/bin/lld; do
  [ -n "$LLD" ] && break
  command -v "$c" >/dev/null 2>&1 && LLD="$c"
done
[ -n "$LLD" ] || { echo "No ELF linker found. Install one (brew install lld) or set LLD=." >&2; exit 1; }
case "$LLD" in *ld.lld) FLAVOR="" ;; *) FLAVOR="-flavor gnu" ;; esac

clang --target=armv7a-linux-gnueabihf -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard \
  -O2 -Wall -Wextra -ffreestanding -fno-builtin -fno-stack-protector -fomit-frame-pointer \
  -nostdlib -c deckd.c -o build/deckd.o
# shellcheck disable=SC2086
"$LLD" $FLAVOR -static -e _start -z noexecstack -o build/deckd build/deckd.o
# The copy beside the source is the published one: it is what the Mac app
# bundles and what anybody without a cross-compiler gets. Keeping it in step
# here is the only way it cannot drift — it silently shipped a version behind
# for three releases when this was a step somebody had to remember.
cp build/deckd deckd
ls -l deckd
