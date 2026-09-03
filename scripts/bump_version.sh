#!/usr/bin/env bash
# scripts/bump_version.sh — tang version app (MARKETING_VERSION / CURRENT_PROJECT_VERSION).
#
# Truoc day Info.plist ghi cung "1.0.0" / "1" thanh chuoi tinh, khong doc bien build setting
# nao ca — nen sua project.yml khong lam gi, "bump version" chi la sua so tren giay.
# Da doi Info.plist sang $(MARKETING_VERSION) / $(CURRENT_PROJECT_VERSION) nen tu day script
# nay la nguon that duy nhat.
#
# Dung:
#   scripts/bump_version.sh patch     # 2.0.0 -> 2.0.1, build so +1
#   scripts/bump_version.sh minor     # 2.0.0 -> 2.1.0, build so +1
#   scripts/bump_version.sh major     # 2.0.0 -> 3.0.0, build so +1
#   scripts/bump_version.sh build     # giu nguyen MARKETING_VERSION, chi tang build so
#   scripts/bump_version.sh set 2.3.1 # dat thang MARKETING_VERSION, build so +1

set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT_YML="project.yml"
[ -f "$PROJECT_YML" ] || { echo "Khong thay $PROJECT_YML" >&2; exit 1; }

CURRENT_MARKETING=$(grep -m1 'MARKETING_VERSION:' "$PROJECT_YML" | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')
CURRENT_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION:' "$PROJECT_YML" | sed -E 's/.*"([0-9]+)".*/\1/')

if [ -z "$CURRENT_MARKETING" ] || [ -z "$CURRENT_BUILD" ]; then
  echo "Khong doc duoc MARKETING_VERSION/CURRENT_PROJECT_VERSION hien tai trong $PROJECT_YML" >&2
  exit 1
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_MARKETING"
MODE="${1:-}"
NEW_BUILD=$((CURRENT_BUILD + 1))

case "$MODE" in
  major) NEW_MARKETING="$((MAJOR + 1)).0.0" ;;
  minor) NEW_MARKETING="${MAJOR}.$((MINOR + 1)).0" ;;
  patch) NEW_MARKETING="${MAJOR}.${MINOR}.$((PATCH + 1))" ;;
  build) NEW_MARKETING="$CURRENT_MARKETING" ;;
  set)
    NEW_MARKETING="${2:-}"
    if ! [[ "$NEW_MARKETING" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "Dung: scripts/bump_version.sh set <major.minor.patch>" >&2
      exit 1
    fi
    ;;
  *)
    echo "Dung: scripts/bump_version.sh {major|minor|patch|build|set <x.y.z>}" >&2
    exit 1
    ;;
esac

# macOS/BSD sed can -i '' ; GNU sed can -i. Thu macOS truoc, roi tu Linux.
sed_inplace() {
  if sed --version >/dev/null 2>&1; then
    sed -i -E "$1" "$2"
  else
    sed -i '' -E "$1" "$2"
  fi
}

sed_inplace "s/MARKETING_VERSION: \"[0-9]+\.[0-9]+\.[0-9]+\"/MARKETING_VERSION: \"${NEW_MARKETING}\"/" "$PROJECT_YML"
sed_inplace "s/CURRENT_PROJECT_VERSION: \"[0-9]+\"/CURRENT_PROJECT_VERSION: \"${NEW_BUILD}\"/" "$PROJECT_YML"

echo "Version: ${CURRENT_MARKETING} (build ${CURRENT_BUILD}) -> ${NEW_MARKETING} (build ${NEW_BUILD})"
echo "Nho chay 'xcodegen generate' lai tren may build (macOS) truoc khi build."
