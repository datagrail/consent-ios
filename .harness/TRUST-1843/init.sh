#!/bin/bash
# init.sh — TRUST-1843 environment bootstrap + smoke test
# Run from inside a VM workspace. Detects which surface it's in.
set -uo pipefail

if [ -f "output/universal/test-server/server.py" ]; then
  SURFACE="consent-test-server"
  SRV="output/universal/test-server"
elif [ -f "server.py" ]; then
  SURFACE="consent-test-server"
  SRV="."
elif [ -f "Package.swift" ] && grep -q DataGrailConsent Package.swift 2>/dev/null; then
  SURFACE="consent-ios"
else
  echo "init.sh: could not detect surface (expected test-server or consent-ios)"; exit 1
fi
echo "=== TRUST-1843 init: surface=$SURFACE ==="

if [ "$SURFACE" = "consent-test-server" ]; then
  cd "$SRV" || exit 1
  echo "--- uv sync ---"
  uv sync || { echo "uv sync failed"; exit 1; }
  echo "--- smoke: start server, hit /healthz ---"
  uv run uvicorn server:app --port 8080 >/tmp/srv.log 2>&1 &
  SRV_PID=$!
  for i in $(seq 1 20); do
    code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/healthz 2>/dev/null || echo 000)
    [ "$code" = "200" ] && break
    sleep 0.5
  done
  echo "healthz -> $code"
  kill "$SRV_PID" 2>/dev/null || true
  [ "$code" = "200" ] && echo "SMOKE OK" || { echo "SMOKE FAILED (see /tmp/srv.log)"; cat /tmp/srv.log; exit 1; }
fi

if [ "$SURFACE" = "consent-ios" ]; then
  echo "NOTE: Swift/tvOS cannot compile in this Linux VM."
  echo "This agent makes edits + commits only; the human verifies via xcodebuild on the host."
  echo "Sanity check: list Swift sources."
  ls Sources/DataGrailConsent/ 2>/dev/null || ls Sources 2>/dev/null || echo "(no Sources dir found)"
fi
echo "=== init done ==="
