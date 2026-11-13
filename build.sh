#!/bin/bash

# Copyright 2026 Hypernova Oy

PM_FILE='Koha/Plugin/Fi/Hypernova/SimpleStatistics.pm'
VERSION=`git log -1 --pretty=oneline --decorate | egrep -o "tag: v[0-9.]+" | sed -e "s/tag: v//"`
if [ -z "$VERSION" ]; then
  VERSION=$(grep -oP "^\s*version\s*=>\s*'\K[^']+" "$PM_FILE" | head -1)
fi
RELEASE_FILE="koha-plugin-simple-statistics-${VERSION}.kpz"
echo "Building release package ${RELEASE_FILE}"
if [ -e ${RELEASE_FILE} ]; then
  rm ${RELEASE_FILE}
fi
rm -rf dist
mkdir -p dist
cp -r Koha dist/.
cd dist
# Build a reproducible zip (fixed timestamps) using Python's zipfile.
python3 - <<PYEOF
import zipfile, os
out = '../${RELEASE_FILE}'
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk('Koha'):
        dirs.sort()
        for name in sorted(files):
            path = os.path.join(root, name)
            info = zipfile.ZipInfo(path, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(path, 'rb') as fh:
                z.writestr(info, fh.read())
PYEOF
cd ..
rm -rf dist
