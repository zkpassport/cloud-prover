#!/usr/bin/env sh

set -e
CIRCUIT="${1:-simple}"

NOIR_VERSION_REQUIRED="1.0.0-beta.8"
BB_VERSION_REQUIRED="1.0.0-nightly.20250701"

# Version checks
if [[ ! $(nargo --version | head -n 1) == "nargo version = $NOIR_VERSION_REQUIRED" ]]; then
    echo "Error: nargo version $NOIR_VERSION_REQUIRED required"
    exit 1
fi
if [[ ! $(bb --version) == "v$BB_VERSION_REQUIRED" ]]; then
    echo "Error: bb version $BB_VERSION_REQUIRED required"
    exit 1
fi

# Solve the witness
nargo execute --force --package $CIRCUIT $CIRCUIT
cp target/${CIRCUIT}.json ../${CIRCUIT}_${BB_VERSION_REQUIRED}.json
cp target/${CIRCUIT}.gz ../${CIRCUIT}_${BB_VERSION_REQUIRED}.gz

# Write verification key
bb write_vk -v -b target/${CIRCUIT}.json -o target
cp target/vk ../${CIRCUIT}_${BB_VERSION_REQUIRED}.vkey
