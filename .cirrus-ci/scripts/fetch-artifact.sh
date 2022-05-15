#!/bin/sh

set -ex
mkdir -p "$WORKSPACE/work"
pwd
if [ ! -f "$WORKSPACE/work/disk-test.img.zst" ]; then
    #fetch https://pdr.bofh.network/data/latest-per-pkg/disk-test.img.zst
    curl https://pdr.bofh.network/data/latest-per-pkg/disk-test.img.zst --output $WORKSPACE/work/disk-test.img.zst
fi
