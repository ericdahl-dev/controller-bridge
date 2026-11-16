#!/bin/sh
# Serves website/ (#169) on this Mac only, for a look before anything is published: http://localhost:8000
# Checks the site first. Ctrl-C stops it. Nothing is deployed.
set -eu
cd "$(dirname "$0")/.."
python3 -I scripts/check_site.py website
echo "Preview: http://localhost:8000  (Ctrl-C to stop)"
exec python3 -I -m http.server 8000 --bind 127.0.0.1 --directory website
