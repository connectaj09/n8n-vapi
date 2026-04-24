#!/usr/bin/env bash
# Phase 3 smoke test — POSTs each fixture with a session-unique call_id,
# checks route + HubSpot deal_id. Also verifies dedup by replaying the
# qualified call_id and expecting duplicate:true.
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

# Session ID makes call_ids unique per run — avoids dedup false positives.
SESSION=$(date +%s)

patched_body() {
  local fixture="$1"
  local suffix="$2"
  # Replace the value of "call_id" with "<original>_<SESSION>_<suffix>"
  sed -E "s/(\"call_id\": *\")([^\"]*)(\")/\1\2_${SESSION}_${suffix}\3/" "$FIXTURES/$fixture"
}

post_body() {
  local body="$1"
  local out_file="$2"
  curl -s -o "$out_file" -w "%{http_code}" \
    -X POST "$WEBHOOK" \
    -H "Content-Type: application/json" \
    -d "$body"
}

run_case() {
  local name="$1" fixture="$2" expected_status="$3" expected_substr="$4"
  local body status out_file
  out_file=$(mktemp)
  body=$(patched_body "$fixture" "$name")
  status=$(post_body "$body" "$out_file")
  local resp
  resp=$(cat "$out_file")
  rm -f "$out_file"

  if [[ "$status" == "$expected_status" ]] && [[ "$resp" == *"$expected_substr"* ]]; then
    printf "  \xE2\x9C\x94  %-18s  HTTP %s  \xE2\x86\x92  %s\n" "$name" "$status" "$expected_substr"
    local deal_id sms_sid
    deal_id=$(printf '%s' "$resp" | sed -n 's/.*"deal_id":"\([^"]*\)".*/\1/p')
    sms_sid=$(printf '%s' "$resp" | sed -n 's/.*"sms_sid":"\([^"]*\)".*/\1/p')
    [[ -n "$deal_id" ]] && printf "     deal_id: %s\n" "$deal_id"
    [[ -n "$sms_sid" ]] && printf "     sms_sid: %s\n" "$sms_sid"
    PASS=$((PASS + 1))
  else
    printf "  \xE2\x9C\x97  %-18s  HTTP %s (expected %s)\n       body: %s\n" "$name" "$status" "$expected_status" "$resp"
    FAIL=$((FAIL + 1))
  fi
}

run_dedup_case() {
  # POSTs mock-vapi-qualified twice with the SAME call_id — second hit should short-circuit.
  # Note: HubSpot's search index has ~5-10s eventual-consistency lag after a deal is created.
  # We sleep 12s before the second POST so the search finds the first-created deal.
  # In production, Vapi retries generally arrive >30s apart, well past the lag window.
  local body1 body2 status1 status2 resp1 resp2 out_file
  out_file=$(mktemp)
  body1=$(patched_body "mock-vapi-qualified.json" "dedup")

  status1=$(post_body "$body1" "$out_file")
  resp1=$(cat "$out_file")

  printf "     (sleeping 12s for HubSpot search indexing)\n"
  sleep 12

  status2=$(post_body "$body1" "$out_file")
  resp2=$(cat "$out_file")
  rm -f "$out_file"

  if [[ "$status1" == "200" ]] && [[ "$resp1" == *"\"route\":\"qualified\""* ]] \
     && [[ "$status2" == "200" ]] && [[ "$resp2" == *"\"duplicate\":true"* ]]; then
    printf "  \xE2\x9C\x94  %-18s  first HTTP %s \xE2\x86\x92 route:qualified; second HTTP %s \xE2\x86\x92 duplicate:true\n" "dedup" "$status1" "$status2"
    PASS=$((PASS + 1))
  else
    printf "  \xE2\x9C\x97  %-18s\n       first  HTTP %s body: %s\n       second HTTP %s body: %s\n" "dedup" "$status1" "$resp1" "$status2" "$resp2"
    FAIL=$((FAIL + 1))
  fi
}

echo "Testing MVA-Intake workflow at: $WEBHOOK"
echo "Session ID: $SESSION (call_ids get this suffix)"
echo

run_case "qualified"     "mock-vapi-qualified.json"      "200" "\"route\":\"qualified\""
run_case "non_qualified" "mock-vapi-non-qualified.json"  "200" "\"route\":\"non_qualified\""
run_case "human_review"  "mock-vapi-human-review.json"   "200" "\"route\":\"human_review\""
run_case "invalid"       "mock-vapi-invalid.json"        "400" "\"error\":\"validation_failed\""
run_dedup_case

echo
echo "Summary: $PASS passed, $FAIL failed"
exit "$FAIL"
