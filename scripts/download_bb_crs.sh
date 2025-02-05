#!/bin/bash
set -eu

# Download CRS for Barretenberg

# Takes optional argument for size exponent (defaults to 22)
subgroup_size_exp="${1:-22}"

# Save to current directory
crs_path=.

# Download BN254 transcript
# 2^N points + 1 because the first is the generator, *64 bytes per point, -1 because the Range header is inclusive.
crs_size=$((2**subgroup_size_exp+1))
crs_size_bytes=$((crs_size*64))
g1=$crs_path/bn254_g1.dat
g2=$crs_path/bn254_g2.dat
if [ ! -f "$g1" ] || [ $(stat -c%s "$g1") -lt $crs_size_bytes ]; then
  echo "Downloading CRS of size: ${crs_size} ($((crs_size_bytes/(1024*1024)))MB)"
  mkdir -p $crs_path
  curl -s -H "Range: bytes=0-$((crs_size_bytes-1))" -o $g1 \
    https://aztec-ignition.s3.amazonaws.com/MAIN%20IGNITION/flat/g1.dat
  chmod a-w $crs_path/bn254_g1.dat
fi
if [ ! -f "$g2" ]; then
  curl -s https://aztec-ignition.s3.amazonaws.com/MAIN%20IGNITION/flat/g2.dat -o $g2
fi

# Download Grumpkin transcript
grumpkin_g1=$crs_path/grumpkin_g1.dat
grumpkin_num_points=$((2**16 + 1)) # 2^16 + 1 = 65537
grumpkin_start=28
grumpkin_size_bytes=$((grumpkin_num_points * 64))
grumpkin_end=$((grumpkin_start + grumpkin_size_bytes - 1))
if [ ! -f "$grumpkin_g1" ]; then
  echo "Downloading Grumpkin transcript..."
  curl -s -H "Range: bytes=$grumpkin_start-$grumpkin_end" \
    -o "$grumpkin_g1" \
    'https://aztec-ignition.s3.amazonaws.com/TEST%20GRUMPKIN/monomial/transcript00.dat'
  # Save grumpkin_num_points to file
  echo -n "$grumpkin_num_points" > grumpkin_size
fi
