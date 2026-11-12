#!/bin/sh
# Prints the byte offset of the squashfs payload in the type 2 AppImage
# given as the only argument. The payload starts right after the ELF
# runtime, whose last part is its section header table, so the offset is
# e_shoff + e_shnum * e_shentsize from the ELF64 header (e_shoff at byte
# 40, e_shentsize at 58, e_shnum at 60). The header is little endian,
# which od reads as such on an x86_64 build host.
set -eu

appimage=$1

shoff=$(od -An -t u8 -j 40 -N 8 "$appimage" | tr -d ' ')
shentsize=$(od -An -t u2 -j 58 -N 2 "$appimage" | tr -d ' ')
shnum=$(od -An -t u2 -j 60 -N 2 "$appimage" | tr -d ' ')

echo $((shoff + shentsize * shnum))
