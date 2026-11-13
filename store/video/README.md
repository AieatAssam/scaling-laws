# Scaling Laws promo video

A 33 s, 1920x1080, 30 fps YouTube/Play promo. Footage is real gameplay captured from the Godot build; the title, captions and end card are Remotion (React) in `src/`.

## Layout

- `src/Root.tsx`: registers the `ScalingLawsPromo` composition (1920x1080, 30 fps, 990 frames).
- `src/Composition.tsx`: scenes and timing (title 0–4 s, lab 4–9 s, training 9–14 s, research 14–19 s, funding 19–24 s, landscape HUD 24–29 s, end card 29–33 s).
- `src/font.ts`: loads the game's pixel font (`public/fonts/PressStart2P-Regular.ttf`, OFL, see `public/fonts/OFL.txt`).
- `public/clips/*.mp4`: captured footage. Portrait clips are 540x960; `hud.mp4` is 1920x1080.
- `out/scaling-laws-promo.mp4`: the rendered video (git-ignored; re-render below).

Captures and clips come from `tools/dev_promo_capture.gd` in the repo root. It runs the real main scene with a fixed seed, early-game state only (no Paradigm or Singularity tabs), and dumps one PNG per frame.

## Re-capture the clips

From the repo root (Godot 4.7.2):

```sh
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
for clip in lab_fill training research funding; do
  "$GODOT" --path . --fixed-fps 30 -s tools/dev_promo_capture.gd -- "$clip" "$PWD/store/video/out/frames/$clip"
done
"$GODOT" --path . --fixed-fps 30 -s tools/dev_promo_capture.gd -- hud "$PWD/store/video/out/frames/hud"
```

Each run writes 180 frames (6 s) and prints `PROMO OK <clip> 180 frames at <size>`. Portrait clips are 360x640 and the HUD clip is 1280x720. `--write-movie` is not used: its writer takes its size from the project's 1280x720 window override, so portrait frames come out wrong.

Convert the frames to clips. This is nearest-neighbour scaling by 1.5x (360x640 → 540x960, 1280x720 → 1920x1080). The base sizes do not allow an integer upscale to these display sizes:

```sh
cd store/video
for clip in lab_fill training research funding; do
  ffmpeg -y -framerate 30 -i out/frames/$clip/%04d.png -vf scale=540:960:flags=neighbor \
    -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -movflags +faststart -an public/clips/$clip.mp4
done
ffmpeg -y -framerate 30 -i out/frames/hud/%04d.png -vf scale=1920:1080:flags=neighbor \
  -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -movflags +faststart -an public/clips/hud.mp4
```

## Render

```sh
cd store/video
npm install
npx tsc --noEmit
npx remotion render ScalingLawsPromo out/scaling-laws-promo.mp4 --codec h264 --pixel-format yuv420p --crf 16
```

Preview in Studio with `npm run dev`. Stills for checking a frame: `npx remotion still ScalingLawsPromo out/check.png --frame=200`.

## YouTube upload

Google Play needs a public or unlisted YouTube URL for the store listing, so upload `out/scaling-laws-promo.mp4` to YouTube and paste that URL into the Play listing. Keep the video free of ads (no ad breaks, no sponsored content), as the brief requires. The end card claims only what the README supports: browser play, Android, and the repository URL.

## Not in the video

No music (silent). No Paradigm, Singularity, late rooms or endings.
