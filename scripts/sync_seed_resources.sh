#!/usr/bin/env bash
#
# Refresh the catalogue compiled into the app from the current remote-data
# content.
#
# The seed exists so a device with no network on first launch still has a
# usable catalogue. It is expected to be stale — the app labels it as such —
# but it should not be years out of date, so run this whenever remote-data
# changes meaningfully, and always before cutting a release build.
#
# Usage: ./scripts/sync_seed_resources.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/remote-data"
SEED="$ROOT/AccessoryAssist/Resources/Seed"
SEED_IMAGES="$ROOT/AccessoryAssist/Resources/SeedImages"

if [ ! -d "$SOURCE" ]; then
  echo "error: $SOURCE not found" >&2
  exit 1
fi

echo "Validating remote-data before seeding…"
python3 "$ROOT/scripts/validate_catalogue.py" "$SOURCE"

mkdir -p "$SEED" "$SEED_IMAGES"

for file in version.json catalogue.json bundles.json announcements.json; do
  cp "$SOURCE/$file" "$SEED/$file"
  echo "seeded $file"
done

rm -f "$SEED_IMAGES"/*.png
cp "$SOURCE"/images/*.png "$SEED_IMAGES"/
echo "seeded $(ls -1 "$SEED_IMAGES" | wc -l | tr -d ' ') images"

echo "Done. Rebuild the app to pick up the new seed."
