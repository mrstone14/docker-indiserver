#!/bin/sh
set -eu

echo "Running driver ldd checks:"
for f in /usr/lib/*indidriver* /usr/lib/*indi*; do
  if [ -e "$f" ]; then
    echo "== $f =="
    ldd "$f" || true
  fi
done

echo "done"
