#!/usr/bin/env sh

set -e
CIRCUIT="${1:-simple}"

NOIR_VERSION_REQUIRED="1.0.0-beta.4"
# BB_VERSION_REQUIRED="0.69.0"

# Version checks
if [[ ! $(nargo --version | head -n 1) == "nargo version = $NOIR_VERSION_REQUIRED" ]]; then
    echo "Error: nargo version $NOIR_VERSION_REQUIRED required"
    exit 1
fi
# if [[ ! $(bb --version) == "$BB_VERSION_REQUIRED" ]]; then
#     echo "Error: bb version $BB_VERSION_REQUIRED required"
#     exit 1
# fi

# Solve the witness
nargo execute --force --package $CIRCUIT $CIRCUIT

# Write verification key
# bb write_vk_ultra_honk -v -b target/$CIRCUIT.json -o target/$CIRCUIT.vkey
bb write_vk -v -b target/$CIRCUIT.json -o target
