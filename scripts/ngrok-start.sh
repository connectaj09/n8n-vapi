#!/usr/bin/env bash
# Start ngrok tunnel to local n8n so Vapi can reach our webhook.
#
# Prereqs:
#   1. `ngrok config add-authtoken <TOKEN>` (one-time; sign up at ngrok.com)
#   2. n8n running at http://localhost:5678
#
# Usage:
#   bash scripts/ngrok-start.sh
#
# After it prints the https URL, paste it into your Vapi assistant's
# "Server URL" field, appending /webhook/mva-intake:
#   https://<random>.ngrok-free.app/webhook/mva-intake
#
# Note: free tier URLs change on every restart. Update Vapi each session.

set -u

if ! command -v ngrok >/dev/null 2>&1; then
  echo "ngrok not found on PATH. Install from https://ngrok.com/download" >&2
  exit 1
fi

echo "Starting ngrok tunnel to localhost:5678 ..."
echo "(Ctrl+C to stop. Leave this running while testing Vapi calls.)"
echo
exec ngrok http 5678
