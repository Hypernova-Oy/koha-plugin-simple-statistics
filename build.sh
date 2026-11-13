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
python3 -m zipfile -c ../${RELEASE_FILE} Koha
cd ..
rm -rf dist
