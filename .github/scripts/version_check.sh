#!/bin/bash
set -euo pipefail

echo "=== Version Consistency Check ==="

# Check pubspec.yaml version format
VERSION_LINE=$(grep '^version:' app/pubspec.yaml)
if ! echo "$VERSION_LINE" | grep -qE 'version: [0-9]+\.[0-9]+\.[0-9]+\+[0-9]+'; then
  echo "❌ ERROR: pubspec.yaml version format invalid."
  echo "   Expected: x.y.z+buildNumber"
  echo "   Got: $VERSION_LINE"
  exit 1
fi
echo "✅ pubspec.yaml version format valid: $VERSION_LINE"

# Check all workflow FLUTTER_VERSION are consistent
FLUTTER_VERSIONS=$(grep -rh 'FLUTTER_VERSION:' .github/workflows/ | sed 's/.*FLUTTER_VERSION: *["]*\([^"]*\)["]*/\1/' | sort -u)
COUNT=$(echo "$FLUTTER_VERSIONS" | wc -l)
if [ "$COUNT" -gt 1 ]; then
  echo "❌ ERROR: FLUTTER_VERSION inconsistent across workflows:"
  echo "$FLUTTER_VERSIONS"
  exit 1
fi
echo "✅ All workflows use consistent FLUTTER_VERSION: $FLUTTER_VERSIONS"

# Check .fvmrc matches CI
FVMRC_VERSION=$(grep '"flutter":' .fvmrc | sed 's/.*"flutter": *"\([^"]*\)".*/\1/')
CI_VERSION="$FLUTTER_VERSIONS"
if [ "$FVMRC_VERSION" != "$CI_VERSION" ]; then
  echo "❌ ERROR: .fvmrc ($FVMRC_VERSION) does not match CI ($CI_VERSION)"
  exit 1
fi
echo "✅ .fvmrc matches CI Flutter version"

echo ""
echo "=== All version checks passed ✅ ==="
