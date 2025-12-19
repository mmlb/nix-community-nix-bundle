#!/usr/bin/env bash

# TODO make this into a go binary that does it all, handles extraction, opengl bind mounts, chroot and run...
# can even use embedded package to embed to whole xz archive too and not have to worry about self-extraction

set -euo pipefail

d=$(dirname "$0")
d=$(cd "$d" && pwd)
f=$d/$(basename "$0")
t=$(mktemp -d)
trap 'rm -rf $t' EXIT
cd "$t"
DECOMPRESSOR='cat'
NUM_LINES_TO_SKIP=0
RUN=/bin/sh
echo "extracting self, please wait (can take a few seconds)" >&2
(LC_ALL=C tail -n+$NUM_LINES_TO_SKIP "$f" | $DECOMPRESSOR | tar -x)
lib=$(ld --verbose -lnvidia-ml -o /dev/null 2>/dev/null | grep "attempt to open.*succeeded" | awk '/libnvidia-ml/ {print $(NF-1)}' || :)
if [[ -n $lib ]]; then
	mkdir -p nix/var/nix/opengl-driver/lib/
	(
		dest=$(cd nix/var/nix/opengl-driver/lib/ && pwd)
		cd "$(dirname "$lib")"
		cp -a "$lib" "$dest/"
		until ! [[ -L $lib ]]; do
			lib=$(readlink "$lib")
			cp -a "$lib" "$dest/"
		done
	)
fi
ret=0
$RUN "$@" || ret=$?
exit "$ret"
