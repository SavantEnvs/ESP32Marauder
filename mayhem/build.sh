#!/usr/bin/env bash
#
# mayhem/build.sh — build ESP32Marauder's host-buildable modules (the PlatformIO
# [env:native] source list in platformio.ini) as:
#   1) sanitized fuzz harnesses + standalone reproducers -> mayhem/build/
#   2) the upstream Unity test suite (test/test_*), normal flags -> mayhem/build/tests/
# The firmware proper (WiFiScan.cpp etc.) needs the ESP-IDF/Arduino core and is
# not built here. Unity (the test framework PlatformIO fetches) is pre-fetched by
# the Dockerfile into /opt/toolchains/deps/unity-2.6.0/src, so this is offline.
set -euo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
: "${UNITY_SRC:=/opt/toolchains/deps/unity-2.6.0/src/src}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
E="$SRC/esp32_marauder"
OUT="$SRC/mayhem/build"
mkdir -p "$OUT/obj-fuzz" "$OUT/obj-test" "$OUT/tests"

# Same list as platformio.ini [env:native] build_src_filter.
MODULES="MarauderMacAddress PcapHeader Switches DisplayLine BeaconFrame WdgResponse
FoxHuntTarget TargetListSort TDongleStats IPv4Range FirmwareMetadata MenuMarquee
GpsTrackerStats BootSplash MenuInputRepeat TDongleBus RemoteIdModel RemoteIdDecoder
MemoryGuard CsiMotionModel CensorText StationSelection"
# PIO_UNIT_TESTING: what PlatformIO defines for native builds (keeps configs.h/FS.h out).
COMMON="-std=gnu++17 -DPIO_UNIT_TESTING -I$E -I$SRC/test/support"

# 1) Sanitized project objects + harnesses. fuzzer-no-link adds the SanCov
#    instrumentation libFuzzer needs to every project object, not only the link.
FFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -O1 -fsanitize=fuzzer-no-link"
fuzz_objs=()
for m in $MODULES; do
  $CXX $COMMON $FFLAGS -c "$E/$m.cpp" -o "$OUT/obj-fuzz/$m.o"
  fuzz_objs+=("$OUT/obj-fuzz/$m.o")
done
$CXX $FFLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$OUT/obj-fuzz/lsan_off.o"
$CC $FFLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$OUT/obj-fuzz/standalone_main.o"

for h in fuzz_remote_id fuzz_firmware_metadata fuzz_text_helpers fuzz_csi_motion fuzz_beacon_ibeacon; do
  $CXX $COMMON $FFLAGS -c "$SRC/mayhem/harnesses/$h.cpp" -o "$OUT/obj-fuzz/$h.o"
  $CXX $FFLAGS $LIB_FUZZING_ENGINE "$OUT/obj-fuzz/$h.o" "${fuzz_objs[@]}" \
    "$OUT/obj-fuzz/lsan_off.o" -o "$OUT/$h"
  $CXX $FFLAGS "$OUT/obj-fuzz/$h.o" "$OUT/obj-fuzz/standalone_main.o" "${fuzz_objs[@]}" \
    "$OUT/obj-fuzz/lsan_off.o" -o "$OUT/$h-standalone"
done

# 2) Upstream Unity test suite with normal flags (what `pio test -e native` runs).
TFLAGS="-O1 $COVERAGE_FLAGS"
test_objs=()
for m in $MODULES; do
  $CXX $COMMON $TFLAGS -c "$E/$m.cpp" -o "$OUT/obj-test/$m.o"
  test_objs+=("$OUT/obj-test/$m.o")
done
$CC $TFLAGS -I"$UNITY_SRC" -c "$UNITY_SRC/unity.c" -o "$OUT/obj-test/unity.o"
$CC $TFLAGS -c "$SRC/mayhem/unity_weak.c" -o "$OUT/obj-test/unity_weak.o"
rm -f "$OUT/tests/"*
for t in "$SRC"/test/test_*/; do
  n=$(basename "$t")
  $CXX $COMMON $TFLAGS -I"$UNITY_SRC" "$t"*.cpp "${test_objs[@]}" \
    "$OUT/obj-test/unity.o" "$OUT/obj-test/unity_weak.o" -o "$OUT/tests/$n"
done
echo "build.sh: built $(ls "$OUT/tests" | wc -l) test binaries and 5 fuzz targets"
