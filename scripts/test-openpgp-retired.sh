#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

for retired_file in \
  "$ROOT/packages/BrevCrypto/Sources/BrevCrypto/OpenPGPKeyMaterialGenerator.swift" \
  "$ROOT/packages/BrevCrypto/Sources/BrevCrypto/PGPArmorBlock.swift" \
  "$ROOT/packages/BrevCrypto/Sources/BrevCrypto/PGPMIME.swift" \
  "$ROOT/packages/BrevCrypto/Sources/BrevCrypto/PGPOutboundMessagePreparer.swift" \
  "$ROOT/packages/BrevCrypto/Sources/BrevCrypto/WKDKeyResolution.swift" \
  "$ROOT/packages/BrevCrypto/Sources/BrevCrypto/WebKeyDirectory.swift" \
  "$ROOT/packages/BrevMail/Sources/BrevMail/DefaultSecurityOpenPGPKeyGenerator.swift" \
  "$ROOT/packages/BrevSettings/Sources/BrevSettings/RecipientKeyDiscoverySettings.swift" \
  "$ROOT/packages/BrevSettings/Sources/BrevSettings/SecurityOpenPGPKeyGeneration.swift"; do
  if [[ -e "$retired_file" ]]; then
    echo "test-openpgp-retired.sh: retired file remains at ${retired_file#$ROOT/}" >&2
    exit 1
  fi
done

if rg -n \
  'ObjectivePGP|OpenPGP|PGPArmor|PGPMIME|PGPOutbound|WKDKey|WebKeyDirectory|application/pgp' \
  "$ROOT/.package.resolved" "$ROOT/apps" "$ROOT/packages" \
  --glob '*.swift' --glob 'Package.swift' --glob 'Package.resolved' \
  --glob '!SecurityKeyMaterialMigration.swift' \
  --glob '!SecurityKeyMaterialMigrationTests.swift' \
  --glob '!**/.build/**' --glob '!**/DerivedData/**'; then
  echo "test-openpgp-retired.sh: active code or package metadata still exposes OpenPGP" >&2
  exit 1
fi

if rg -n 'OpenPGP WKD|recipient-key lookup|keys\.openpgp\.org' \
  "$ROOT/PRIVACY.md" "$ROOT/ADRs/0006-telemetry-and-privacy.md"; then
  echo "test-openpgp-retired.sh: current privacy documentation still promises WKD" >&2
  exit 1
fi

if [[ ! -f "$ROOT/packages/BrevCrypto/Sources/BrevCrypto/SMIMEOutboundMessagePreparer.swift" ]]; then
  echo "test-openpgp-retired.sh: native S/MIME support was removed with OpenPGP" >&2
  exit 1
fi

if [[ ! -f "$ROOT/THIRD_PARTY_LICENSES.md" ]]; then
  echo "test-openpgp-retired.sh: THIRD_PARTY_LICENSES.md is missing" >&2
  exit 1
fi

echo "test-openpgp-retired.sh: OK"
