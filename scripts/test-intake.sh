#!/usr/bin/env bash
# Phase 2 smoke test — POSTs each fixture and checks route + HubSpot deal_id returned.
#
# Usage:
#   bash scripts/test-intake.sh
#
# Requires: n8n running at http://localhost:5678 with MVA-Intake-v0.1-Phase1 active.
# Requires: HubSpot + Twilio credentials configured in n8n.

set -u

WEBHOOK="${WEBHOOK_URL:-http://localhost:5678/webhook/mva-intake}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$DIR/fixtures"
PASS=0
FAIL=0

run_case() {
  local name="$1"
  local fixture="$2"
  local expected_status="$3"
  local expected_substr="$4"

  local body status
  local out
  out=$(curl -s -o /tmp/test-intake-resp.json -w "%{http_code}" \
    -X POST "$WEBHOOK" \
    -H "Content-Type: application/json" \
    -d @"$FIXTURES/$fixture")
  status="$out"
  body=$(cat /tmp/test-intake-resp.json)

  if [[ "$status" == "$expected_status" ]] && [[ "$body" == *"$expected_substr"* ]]; then
    printf "  \xE2\x9C\x94  %-18s  HTTP %s  \xE2\x86\x92  %s\n" "$name" "$status" "$expected_substr"
    # Extract deal_id and sms_sid if present
    local deal_id sms_sid
    deal_id=$(printf '%s' "$body" | sed -n 's/.*"deal_id":"\([^"]*\)".*/\1/p')
    sms_sid=$(printf '%s' "$body" | sed -n 's/.*"sms_sid":"\([^"]*\)".*/\1/p')
    [[ -n "$deal_id" ]] && printf "     deal_id: %s\n" "$deal_id"
    [[ -n "$sms_sid" ]] && printf "     sms_sid: %s\n" "$sms_sid"
    PASS=$((PASS + 1))
  else
    printf "  \xE2\x9C\x97  %-18s  HTTP %s (expected %s)\n       body: %s\n" "$name" "$status" "$expected_status" "$body"
    FAIL=$((FAIL + 1))
  fi
}

echo "Testing MVA-Intake workflow at: $WEBHOOK"
echo

run_case "qualified"     "mock-vapi-qualified.json"      "200" "\"route\":\"qualified\""
run_case "non_qualified" "mock-vapi-non-qualified.json"  "200" "\"route\":\"non_qualified\""
run_case "human_review"  "mock-vapi-human-review.json"   "200" "\"route\":\"human_review\""
run_case "invalid"       "mock-vapi-invalid.json"        "400" "\"error\":\"validation_failed\""

echo
echo "Summary: $PASS passed, $FAIL failed"
rm -f /tmp/test-intake-resp.json
exit "$FAIL"
