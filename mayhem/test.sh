#!/usr/bin/env bash
#
# mayhem/test.sh — RUN ESP32Marauder's upstream Unity suite (test/test_*, built by
# mayhem/build.sh into mayhem/build/tests/). Each binary prints Unity's summary
# "<N> Tests <F> Failures <I> Ignored"; every test case's assertions check
# known-input -> known-output values. A binary that exits without that summary
# (crash, no-op) counts all of its expected tests as failed.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

TESTS="$SRC/mayhem/build/tests"
passed=0 failed=0 skipped=0 suites=0
for t in "$SRC"/test/test_*/; do
  n=$(basename "$t")
  suites=$((suites + 1))
  # Expected case count from the source (RUN_TEST lines), used when a binary
  # dies or produces no summary.
  expected=$(grep -c 'RUN_TEST(' "$t"*.cpp | awk -F: '{s+=$NF} END{print s+0}')
  [ "$expected" -gt 0 ] || expected=1
  if [ ! -x "$TESTS/$n" ]; then
    echo "FAIL $n: test binary missing (build.sh should have built it)" >&2
    failed=$((failed + expected)); continue
  fi
  out=$(cd "$TESTS" && "./$n" 2>&1); rc=$?
  summary=$(printf '%s\n' "$out" | grep -E '^[0-9]+ Tests [0-9]+ Failures [0-9]+ Ignored' | tail -1)
  if [ -z "$summary" ]; then
    echo "FAIL $n: no Unity summary (rc=$rc)" >&2
    printf '%s\n' "$out" | tail -5 >&2
    failed=$((failed + expected)); continue
  fi
  read -r total _ fails _ ign _ <<<"$summary"
  if [ "$total" -lt "$expected" ]; then
    echo "FAIL $n: ran $total of $expected tests" >&2
    fails=$((fails + expected - total)); total=$expected
  fi
  [ "$rc" -eq 0 ] || [ "$fails" -gt 0 ] || fails=1
  printf '%s\n' "$out" | grep -E ':FAIL' >&2 || true
  passed=$((passed + total - fails - ign)); failed=$((failed + fails)); skipped=$((skipped + ign))
  echo "$n: $summary (rc=$rc)"
done
echo "ran $suites suites"
emit_ctrf "unity" "$passed" "$failed" "$skipped"
