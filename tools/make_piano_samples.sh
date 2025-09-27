#!/usr/bin/env bash
set -euo pipefail

# Generates short piano note samples using FluidSynth + a GM soundfont.
# Outputs 44.1kHz mono WAVs to tools/samples/piano/{low,mid,high}.wav

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/tools/samples/piano"
# Allow overriding the soundfont path via first arg or SF2_PATH env.
SF2_PATH="${SF2_PATH:-$ROOT_DIR/tools/sf2/FatBoy-v0.790.sf2}"
if [ "${1:-}" != "" ]; then
  SF2_PATH="$1"
fi

mkdir -p "$OUT_DIR" "$ROOT_DIR/tools/sf2"

if ! command -v fluidsynth >/dev/null 2>&1; then
  echo "[make_piano_samples] Installing fluidsynth via Homebrew..."
  brew install fluidsynth
fi

ensure_sf2() {
  if [ -f "$SF2_PATH" ]; then
    # Validate RIFF header
    if head -c 4 "$SF2_PATH" | grep -q RIFF ; then
      return 0
    fi
    echo "[make_piano_samples] Existing SF2 seems invalid, re-downloading..."
    rm -f "$SF2_PATH"
  fi
  echo "[make_piano_samples] Downloading FatBoy GM soundfont..."
  mkdir -p "$(dirname "$SF2_PATH")"
  # Try a few mirrors in order
  urls=(
    "https://github.com/urish/c94-sf2/releases/download/v0.790/FatBoy-v0.790.sf2"
    "https://github.com/urish/c94-sf2/raw/master/FatBoy-v0.790.sf2"
    "https://raw.githubusercontent.com/urish/c94-sf2/master/FatBoy-v0.790.sf2"
  )
  for u in "${urls[@]}"; do
    echo "  -> $u"
    if curl -L --fail --silent --show-error -o "$SF2_PATH" "$u"; then
      if head -c 4 "$SF2_PATH" | grep -q RIFF ; then
        echo "[make_piano_samples] Downloaded valid SF2."
        return 0
      fi
    fi
  done
  echo "[make_piano_samples] Could not fetch a valid SF2 automatically."
  echo "Place a General MIDI piano SF2 at: $SF2_PATH"
  exit 1
}

if [ ! -f "$SF2_PATH" ]; then
  ensure_sf2
fi
echo "[make_piano_samples] Using soundfont: $SF2_PATH"

render_note() {
  local midi_note=$1   # e.g., 72 = C5
  local out_wav=$2
  local dur=${3:-0.09} # seconds
  local gain=${4:-0.8}

  # Render a single short note using FluidSynth CLI commands.
  # Channel 0, program 0 (Acoustic Grand Piano).
  fluidsynth -a file -F "$out_wav" -T wav -r 44100 -g "$gain" "$SF2_PATH" <<EOF
select 0 0 0
noteon 0 $midi_note 110
sleep $dur
noteoff 0 $midi_note
quit
EOF
  if [ ! -f "$out_wav" ]; then
    echo "[make_piano_samples] ERROR: Failed to render note $midi_note to $out_wav" >&2
    exit 1
  fi
}

post_process() {
  local in_wav=$1
  local out_wav=$2
  # Mono, add 15ms lead-in, fast fades in/out, trim to ~100ms, normalize lightly.
  ffmpeg -y -hide_banner -loglevel error \
    -i "$in_wav" \
    -af "aformat=channel_layouts=mono,adelay=15|15,afade=t=in:st=0:d=0.003,afade=t=out:st=0.10:d=0.004,volume=0.95,atrim=0:0.12" \
    -ar 44100 -ac 1 "$out_wav"
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

echo "[make_piano_samples] Rendering C5 (low), E5 (mid), G5 (high)..."
render_note 72 "$tmp_dir/low_raw.wav"   0.09 0.8   # C5
render_note 76 "$tmp_dir/mid_raw.wav"   0.09 0.8   # E5
render_note 79 "$tmp_dir/high_raw.wav"  0.09 0.8   # G5

post_process "$tmp_dir/low_raw.wav"  "$OUT_DIR/low.wav"
post_process "$tmp_dir/mid_raw.wav"  "$OUT_DIR/mid.wav"
post_process "$tmp_dir/high_raw.wav" "$OUT_DIR/high.wav"

echo "[make_piano_samples] Wrote:"
ls -1 "$OUT_DIR"/*.wav
echo "[make_piano_samples] Done. Next:"
echo "  dart run tools/generate_audio.dart"
echo "  flutter pub get"

