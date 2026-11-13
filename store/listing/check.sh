#!/bin/bash
# Checks the Play Store pack: text limits, plain ASCII text, image sizes and no alpha.
# Usage: store/listing/check.sh   (run from anywhere; exits 1 on the first failed group, after listing all)
set -u
here="$(cd "$(dirname "$0")" && pwd)"
store="$(dirname "$here")"
fails=0

fail() { echo "FAIL  $1"; fails=$((fails + 1)); }
pass() { echo "ok    $1"; }

# Text: length limits in characters, not counting the final newline.
check_len() {
	local file="$1" max="$2" text n
	text="$(cat "$file")"  # command substitution drops trailing newlines
	n=$(printf '%s' "$text" | LC_ALL=C wc -c | tr -d ' ')
	if [ "$n" -le "$max" ]; then pass "$(basename "$file") length $n <= $max"; else fail "$(basename "$file") length $n > $max"; fi
}

# Text: any byte outside 7-bit ASCII is a failure.
check_ascii() {
	local file="$1" bad
	bad=$(LC_ALL=C tr -d '\000-\177' < "$file" | LC_ALL=C wc -c | tr -d ' ')
	if [ "$bad" -eq 0 ]; then pass "$(basename "$file") is ASCII"; else fail "$(basename "$file") has $bad non-ASCII bytes"; fi
}

# Image: PNG of the given size, RGB colour with no alpha channel.
check_png() {
	local file="$1" w="$2" h="$3" info
	if [ ! -f "$file" ]; then fail "$file missing"; return; fi
	info="$(file -b "$file")"
	case "$info" in
		*"$w x $h,"*) ;;
		*) fail "$(basename "$file") is not ${w}x${h}: $info"; return ;;
	esac
	case "$info" in
		*"8-bit/color RGB,"*) ;;
		*) fail "$(basename "$file") is not 8-bit RGB: $info"; return ;;
	esac
	case "$info" in
		*RGBA*|*"with alpha"*) fail "$(basename "$file") has an alpha channel: $info" ;;
		*) pass "$(basename "$file") ${w}x${h} RGB, no alpha" ;;
	esac
}

# A folder must hold exactly the named PNG files (no extras, none missing).
check_set() {
	local dir="$1" w="$2" h="$3"; shift 3
	local expected="$*" count
	count=$(find "$dir" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')
	local want; want=$(echo "$expected" | wc -w | tr -d ' ')
	if [ "$count" -ne "$want" ]; then fail "$dir has $count PNGs, expected $want"; fi
	for name in $expected; do check_png "$dir/$name" "$w" "$h"; done
	local f
	for f in "$dir"/*.png; do
		[ -e "$f" ] || continue
		case " $expected " in *" $(basename "$f") "*) ;; *) fail "unexpected $(basename "$f") in $dir" ;; esac
	done
}

echo "== text"
check_len "$here/en-GB/title.txt" 30
check_len "$here/en-GB/short_description.txt" 80
check_len "$here/en-GB/full_description.txt" 4000
check_len "$here/en-GB/release_notes.txt" 500
for f in "$here"/en-GB/*.txt; do check_ascii "$f"; done
for f in "$store/privacy-policy.md"; do [ -f "$f" ] && check_ascii "$f" || fail "$f missing"; done

echo "== graphics"
check_png "$store/graphics/icon-512.png" 512 512
check_png "$store/graphics/feature-graphic-1024x500.png" 1024 500

echo "== screenshots"
check_set "$store/screenshots/phone" 1080 1920 \
	01-buy-compute.png 02-train-models.png 03-publish-papers.png \
	04-hire-a-team.png 05-track-everything.png 06-come-back-to-progress.png
check_set "$store/screenshots/tablet7" 1920 1080 01-lab-producers.png 02-hire-a-team.png
check_set "$store/screenshots/tablet10" 1920 1080 01-training.png 02-research-desk.png

if [ "$fails" -eq 0 ]; then echo "ALL CHECKS PASSED"; exit 0; fi
echo "$fails check(s) failed"
exit 1
