#!/bin/bash
# listen.sh — Speak11 Speech-to-Text for macOS
# Record audio, press the hotkey again, get the transcription in your clipboard.
#
# Requirements: curl, python3 (built into macOS)
# Setup: Uses the same API key as speak.sh (stored in Keychain).

# ── Configuration ──────────────────────────────────────────────────
ELEVENLABS_API_KEY="${ELEVENLABS_API_KEY:-$(security find-generic-password -a "speak11" -s "speak11-api-key" -w 2>/dev/null)}"

# Load settings written by the menu bar settings app.
_CONFIG="$HOME/.config/speak11/config"
[ -f "$_CONFIG" ] && source "$_CONFIG"

# STT model — scribe_v2 is the latest and most accurate
STT_MODEL_ID="${ELEVENLABS_STT_MODEL_ID:-${STT_MODEL_ID:-scribe_v2}}"

# Language — empty string means auto-detect
STT_LANGUAGE="${ELEVENLABS_STT_LANGUAGE:-${STT_LANGUAGE:-}}"

# ── Preflight checks ───────────────────────────────────────────────
AUDIO_FILE="${1:-}"
if [ -z "$AUDIO_FILE" ] || [ ! -f "$AUDIO_FILE" ]; then
    osascript -e 'display dialog "No audio file provided or file not found." with title "Speak11" buttons {"OK"} default button "OK" with icon caution'
    exit 1
fi

if [ -z "$ELEVENLABS_API_KEY" ]; then
    osascript -e 'display dialog "ElevenLabs API key not found." & return & return & "Run install.command to store your key, or set the ELEVENLABS_API_KEY environment variable." with title "Speak11" buttons {"OK"} default button "OK" with icon caution'
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    osascript -e 'display dialog "python3 is required but not found." & return & return & "Install Xcode Command Line Tools: xcode-select --install" with title "Speak11" buttons {"OK"} default button "OK" with icon caution'
    exit 1
fi

# ── Call ElevenLabs Speech-to-Text API ────────────────────────────
TMP_RESPONSE=$(mktemp "${TMPDIR:-/tmp}/elevenlabs_stt_XXXXXXXXXX.json")
cleanup() { rm -f "$TMP_RESPONSE"; }
trap cleanup EXIT INT TERM

CURL_ARGS=(
    -s -w "%{http_code}"
    --max-time 60
    -o "$TMP_RESPONSE"
    -X POST
    "https://api.elevenlabs.io/v1/speech-to-text"
    -H "xi-api-key: ${ELEVENLABS_API_KEY}"
    -F "model_id=${STT_MODEL_ID}"
    -F "file=@${AUDIO_FILE}"
)

# Only add language_code if explicitly set (empty = auto-detect)
if [ -n "$STT_LANGUAGE" ]; then
    CURL_ARGS+=(-F "language_code=${STT_LANGUAGE}")
fi

HTTP_CODE=$(curl "${CURL_ARGS[@]}")

# ── Handle errors ──────────────────────────────────────────────────
if [ "$HTTP_CODE" != "200" ]; then
    SAFE_ERROR=$(cat "$TMP_RESPONSE" 2>/dev/null \
        | head -c 300 \
        | tr -d '\000-\037"\\')
    osascript -e "display dialog \"ElevenLabs STT API error (HTTP ${HTTP_CODE}):\" & return & return & \"${SAFE_ERROR:-Unknown error}\" with title \"Speak11\" buttons {\"OK\"} default button \"OK\" with icon caution"
    exit 1
fi

# ── Extract text from response ─────────────────────────────────────
TEXT=$(python3 -c "import json,sys; print(json.loads(sys.stdin.read())['text'])" < "$TMP_RESPONSE" 2>/dev/null)

if [ -z "${TEXT//[[:space:]]/}" ]; then
    osascript -e 'display dialog "No speech detected in the recording." with title "Speak11" buttons {"OK"} default button "OK" with icon note'
    exit 0
fi

# ── Copy to clipboard ──────────────────────────────────────────────
printf '%s' "$TEXT" | pbcopy
