---
name: animate
description: Make animated product videos, README GIFs, explainer clips and motion graphics in code. Each frame is a pure JavaScript function of time, rendered in headless Chrome, checked by eye and encoded with ffmpeg. Use when the user asks for an animated demo, promo video, product intro, README GIF, motion graphics, an explainer, or "animate the UI".
---

# Animate

Make a video as code. The scene is one HTML file. `render(t)` sets every style from the time `t` in seconds. A headless browser calls `render(t)` for each frame and takes a screenshot. ffmpeg joins the frames into an MP4 and a GIF.

This gives exact, repeatable frames. You can render any single frame, look at it, fix the code, and render again.

## Files

- `scripts/render.mjs`: the renderer. It renders frames, stills and contact sheets, and encodes MP4 and GIF. Read its header for all options.
- `templates/scene.html`: the starting scene, with math helpers, a timeline and the `render(t)` contract.

## Requirements

- Node 18 or later.
- `playwright` in the project: `npm i -D playwright` (or `pnpm add -D -w playwright`). The renderer looks for it in the current project first.
- Google Chrome, or `npx playwright install chromium`.
- `ffmpeg` on PATH, or `FFMPEG=/path/to/ffmpeg`.

Check these first. Tell the user which one is missing.

## Workflow

### 1. Intake

Get these facts. Ask only for what the request and the code do not show:

- The goal and the audience (README, landing page, social post, release note).
- The length. A README loop is 10 to 20 seconds.
- The size and the format. The default is 1280x800, 60 fps, MP4 plus GIF.
- Loop or not. A README GIF loops: the last frame leads back into frame 0.
- Visual input: screenshots, a design, or a clip the user likes.

### 2. Storyboard first

Write a storyboard before any code. Show it to the user and wait for a yes. A storyboard is cheaper to change than a scene.

Use a table with one row per beat: start and end time, what the viewer sees, and the motion (fade, rise, type, draw, camera move). Mark the key frame of each beat. The key frames are the stills you check later.

Keep one idea per beat. Give each beat time to read: about 0.3 seconds per word on screen, and at least 0.6 seconds of hold after a main reveal.

### 3. Match the real product

When the video shows an app, the UI must look like the real app. Users notice small differences, and they reject them.

- Inline the app's real stylesheet: `--css path/to/dist/assets` (the renderer takes the newest `.css` in a directory). Build the app first.
- Copy the markup and the class names from the real components. Do not restyle, and do not guess. Open the component source for each element you draw.
- Use the current design. If the app changed since an old scene, update the scene.
- Take a screenshot of the real app at the same viewport. Put it next to a still and compare them.
- Use made-up but realistic data. Never put real customer or company data in a video.

Invented motion graphics on top of the real UI are good: signals that travel to data sources, nodes, pills, a camera push-in, a card that turns into a notification. These make the video worth watching. Keep the UI under them accurate.

### 4. Write the scene

Start from `templates/scene.html`. Follow these rules:

- **Pure function of time.** `render(t)` reads only `t` and the geometry from `measure()`. No `Date`, no `requestAnimationFrame`, no `setTimeout`, no CSS transitions or animations (the template turns them off), no `Math.random` (use the seeded `rng`).
- **Set every animated property on every frame.** A property that one branch sets and another branch skips keeps its old value when frames render out of order. The renderer renders frames in parallel and out of order.
- **One timeline object.** Put every beat time in `TL`. Derive each motion from `seg(t, a, b)` and an easing function. Change the timing in one place.
- **Measure once.** Lay out the scene with everything expanded, read the positions in `measure()`, then collapse. Do not read layout inside `render(t)` unless the element moves. Fonts must load first (`document.fonts.ready`).
- **Animate transforms and opacity.** Use `translate` and `scale` for motion. Use `setOp`, which also sets `visibility: hidden` at zero, so hidden elements never block or flash.
- **Camera moves.** Transform one root element (`#app`) with `translate(...) scale(...)` around a pivot point. Keep overlays that must stay sharp in a separate layer (`#fx`).
- **Charts.** Draw a line with a `clipPath` rect whose width grows. Grow bars one by one with a short overlap. Draw check marks with `stroke-dasharray` and `stroke-dashoffset`.
- **Text.** Type text by slicing the string by `seg(t, ...)`. Keep a blinking caret only while the user types.
- **Seamless loop.** The outro returns every element to its frame-0 state. The renderer never renders frame `duration * fps`, because that frame equals frame 0.
- **Size.** Set `window.SCENE = { width, height, duration, fps }` and use the same size in the CSS of `html, body, #app, #fx`.
- **Easing.** Use `outCubic` for entrances, `inOutCubic` for moves and camera, and `outBack` for a small overshoot (pins, badges). Avoid linear motion except for typing and spinners.

### 5. Check every beat by eye

Never deliver a video that you did not look at.

1. Render stills at the key frames: `node render.mjs scene.html --out out/intro --css <css> --still 1.2,3.4,6.0`. Open each PNG and look at it.
2. Render the whole clip with a contact sheet: add `--sheet 16`. Open `<out>-sheet.png`.
3. Look for: text that overflows or is cut off, overlaps, elements that pop in with no motion, elements that disappear early, a jump between two frames, a layout that differs from the real app, blank frames, a loop seam.
4. For a doubtful transition, render stills 1/60 second apart around it, or render only that range: `--from 6.0 --to 7.5`.
5. Fix the scene and render again. Repeat until every key frame is right.

Watch for scene errors: the renderer prints `Scene error:` for exceptions in the page.

### 6. Encode and deliver

The renderer writes:

- `<out>.mp4`: H.264, yuv420p, CRF 18, faststart. Use `--scale 2` for a sharp MP4 on high-density screens.
- `<out>.gif`: 24 fps, 900 px wide, a 128-color palette from frame differences, Bayer dither. It prints the size.

GIF limits: keep a README GIF under about 10 MB. To make it smaller, lower `--gif-width` (720), lower `--gif-fps` (20), shorten the clip, or reduce large color gradients and blur. GitHub plays MP4 in README files too, so offer the MP4 when the GIF is too large.

Audio: give `--audio voice.mp3` to mux a voice-over or music track into the MP4. Time the beats to the audio, not the other way round. Write the voice-over script with the storyboard.

Keep the scene and the render command in the project, so the video can be made again after the UI changes. Put outputs in a docs folder. Do not leave temporary frames.

## Common faults

- **The UI looks slightly wrong.** The scene uses guessed classes or an old stylesheet. Copy the classes from the component source and rebuild the CSS.
- **Blank frames or default fonts.** `window.ready` resolved before the fonts loaded, or `--css` was not given.
- **An element flickers.** One branch of `render(t)` does not set a property that another branch sets.
- **Blur is slow or the GIF is large.** `filter: blur()` on a large layer costs render time and GIF colors. Use it for short beats only, at 3 px or less.
- **A long label covers a target.** Fade the label out before it reaches the target.
- **The GIF has banding.** Lower the color count of the gradient area, or keep `stats_mode=diff` and Bayer dither.
