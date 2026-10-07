#!/usr/bin/env node
/**
 * Renders a procedural scene to MP4 and GIF.
 *
 * A scene is one HTML file that defines:
 *   window.SCENE = { width, height, duration, fps? }   // seconds; fps defaults to 60
 *   window.ready  = Promise                            // resolves when fonts and layout are ready
 *   window.render = (t) => void                         // sets every style from t (seconds) and nothing else
 *
 * The scene may hold the markers <!--css--> (replaced by the --css files, inlined)
 * and <!--var:NAME--> (replaced by --var NAME=value).
 *
 * Usage:
 *   node render.mjs scene.html --out docs/media/intro [options]
 *
 * Options:
 *   --out PATH        Output path without extension. Default: ./out/<scene name>
 *   --css FILE        Stylesheet to inline at <!--css-->. Repeatable. A glob-free directory
 *                     path picks the newest *.css in it (for hashed build output).
 *   --var NAME=VALUE  Text to put at <!--var:NAME-->. Repeatable.
 *   --still T[,T...]  Write PNG stills at these times (seconds) and stop. For quick checks.
 *   --sheet [N]       Also write a contact sheet of N frames (default 16) as <out>-sheet.png.
 *   --from S --to S   Render only this time range (MP4 only). For checking one beat.
 *   --scale K         Device scale factor. Default 1. Use 2 for crisp MP4 on retina.
 *   --jobs N          Parallel browser pages. Default 4.
 *   --gif-width W     GIF width in px. Default 900. 0 skips the GIF.
 *   --gif-fps F       GIF frame rate. Default 24.
 *   --audio FILE      Mux this audio track into the MP4 (cut to the video length).
 *   --keep            Keep the frame PNGs in <out>-frames/.
 *
 * Needs: Node 18+, the playwright package (npm i -D playwright), Google Chrome or
 * `npx playwright install chromium`, and ffmpeg on PATH (or FFMPEG=/path/to/ffmpeg).
 */

import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, extname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

// Bare imports resolve next to this file, so playwright is looked up in the project that runs the script first.
let chromium;
try {
  const fromProject = createRequire(join(process.cwd(), "noop.js")).resolve("playwright");
  const m = await import(pathToFileURL(fromProject).href);
  chromium = m.chromium ?? m.default?.chromium;
} catch {
  try { chromium = (await import("playwright")).chromium; } catch { /* reported below */ }
}
if (!chromium) {
  console.error("The playwright package is missing. Run: npm i -D playwright (in the project) and retry.");
  process.exit(1);
}

const FFMPEG = process.env.FFMPEG || "ffmpeg";

function parseArgs(argv) {
  const o = { css: [], vars: {}, jobs: 4, scale: 1, gifWidth: 900, gifFps: 24, sheet: 0 };
  const rest = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = () => argv[++i];
    if (a === "--out") o.out = next();
    else if (a === "--css") o.css.push(next());
    else if (a === "--var") { const [k, ...v] = next().split("="); o.vars[k] = v.join("="); }
    else if (a === "--still") o.still = next().split(",").map(Number);
    else if (a === "--sheet") o.sheet = /^\d+$/.test(argv[i + 1] ?? "") ? Number(next()) : 16;
    else if (a === "--from") o.from = Number(next());
    else if (a === "--to") o.to = Number(next());
    else if (a === "--scale") o.scale = Number(next());
    else if (a === "--jobs") o.jobs = Math.max(1, Number(next()));
    else if (a === "--gif-width") o.gifWidth = Number(next());
    else if (a === "--gif-fps") o.gifFps = Number(next());
    else if (a === "--audio") o.audio = next();
    else if (a === "--keep") o.keep = true;
    else rest.push(a);
  }
  o.scene = rest[0];
  if (!o.scene) throw new Error("Give the scene HTML file as the first argument.");
  return o;
}

function resolveCss(p) {
  if (existsSync(p) && statSync(p).isDirectory()) {
    const css = readdirSync(p).filter((f) => f.endsWith(".css")).map((f) => join(p, f)).sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs)[0];
    if (!css) throw new Error(`No .css file in ${p}. Build the app first.`);
    return css;
  }
  if (!existsSync(p)) throw new Error(`Stylesheet not found: ${p}`);
  return p;
}

// file:// pages cannot load sibling build output reliably, so styles are inlined into a copy of the scene.
function prepareScene(o, workDir) {
  let html = readFileSync(o.scene, "utf8");
  const css = o.css.map((p) => `<style>${readFileSync(resolveCss(p), "utf8")}</style>`).join("\n");
  html = html.replace("<!--css-->", css);
  for (const [k, v] of Object.entries(o.vars)) html = html.replaceAll(`<!--var:${k}-->`, v);
  const file = join(workDir, "scene.html");
  writeFileSync(file, html);
  return pathToFileURL(file).href;
}

function ffmpeg(args) {
  const r = spawnSync(FFMPEG, ["-y", "-v", "error", ...args], { stdio: ["ignore", "ignore", "inherit"] });
  if (r.error) throw new Error(`ffmpeg not found (${r.error.message}). Install it or set FFMPEG.`);
  if (r.status !== 0) throw new Error("ffmpeg failed");
}

async function openPage(browser, url, scene, scale) {
  const page = await browser.newPage({ viewport: { width: scene.width, height: scene.height }, deviceScaleFactor: scale });
  page.on("pageerror", (e) => console.error("Scene error:", e.message));
  await page.goto(url);
  await page.evaluate(() => window.ready);
  return page;
}

async function launch() {
  try {
    return await chromium.launch({ channel: "chrome" });
  } catch {
    return await chromium.launch();
  }
}

const o = parseArgs(process.argv.slice(2));
const name = basename(o.scene, extname(o.scene));
const out = resolve(o.out ?? join("out", name));
mkdirSync(dirname(out), { recursive: true });
const work = `${out}-work`;
const frames = `${out}-frames`;
rmSync(work, { recursive: true, force: true });
rmSync(frames, { recursive: true, force: true });
mkdirSync(work, { recursive: true });

const browser = await launch();
try {
  const url = prepareScene(o, work);
  const probe = await browser.newPage();
  await probe.goto(url);
  const scene = await probe.evaluate(() => window.SCENE);
  await probe.close();
  if (!scene?.width || !scene?.height || !scene?.duration) throw new Error("The scene must set window.SCENE = { width, height, duration }.");
  const fps = scene.fps ?? 60;

  if (o.still) {
    const page = await openPage(browser, url, scene, o.scale);
    for (const t of o.still) {
      await page.evaluate((x) => window.render(x), t);
      const file = `${out}-t${t.toFixed(2)}.png`;
      await page.screenshot({ path: file });
      console.log(`Wrote ${file}`);
    }
  } else {
    const first = Math.round((o.from ?? 0) * fps);
    // Frame `total` equals frame 0 for a looping scene, so it is never rendered.
    const last = o.to != null ? Math.round(o.to * fps) : Math.round(scene.duration * fps);
    const count = last - first;
    mkdirSync(frames, { recursive: true });
    const framePath = (i) => join(frames, `${String(i).padStart(5, "0")}.png`);
    const pages = await Promise.all(Array.from({ length: Math.min(o.jobs, count) }, () => openPage(browser, url, scene, o.scale)));
    let next = 0;
    let done = 0;
    await Promise.all(pages.map(async (page) => {
      while (next < count) {
        const i = next++;
        await page.evaluate((x) => window.render(x), (first + i) / fps);
        await page.screenshot({ path: framePath(i) });
        if (++done % fps === 0) process.stdout.write(`\r${done}/${count} frames`);
      }
    }));
    process.stdout.write(`\r${count}/${count} frames\n`);

    if (o.sheet) {
      const picks = Array.from({ length: o.sheet }, (_, k) => Math.round((k * count) / o.sheet));
      const cols = Math.ceil(Math.sqrt(o.sheet));
      const tw = 480;
      const tiles = picks.map((i) => `<figure><img src="${pathToFileURL(framePath(i)).href}"><figcaption>${((first + i) / fps).toFixed(2)} s</figcaption></figure>`);
      const sheetHtml = join(work, "sheet.html");
      writeFileSync(sheetHtml, `<style>body{margin:0;display:grid;grid-template-columns:repeat(${cols},${tw}px);gap:6px;background:#222;font:14px sans-serif;color:#fff}figure{margin:0}img{width:${tw}px;display:block}figcaption{padding:2px 6px}</style>${tiles.join("")}`);
      const sp = await browser.newPage({ viewport: { width: cols * (tw + 6), height: 600 } });
      await sp.goto(pathToFileURL(sheetHtml).href);
      await sp.screenshot({ path: `${out}-sheet.png`, fullPage: true });
      console.log(`Wrote ${out}-sheet.png`);
    }

    const input = ["-framerate", String(fps), "-i", join(frames, "%05d.png")];
    const audio = o.audio ? ["-i", o.audio, "-c:a", "aac", "-b:a", "192k", "-shortest"] : ["-an"];
    // Odd sizes break yuv420p, so the MP4 is padded to even dimensions.
    ffmpeg([...input, ...audio, "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-preset", "slow", "-movflags", "+faststart", `${out}.mp4`]);
    console.log(`Wrote ${out}.mp4`);

    if (o.gifWidth > 0 && o.from == null && o.to == null) {
      const filters = `fps=${o.gifFps},scale=${o.gifWidth}:-1:flags=lanczos`;
      const palette = join(work, "palette.png");
      ffmpeg([...input, "-vf", `${filters},palettegen=max_colors=128:stats_mode=diff`, palette]);
      ffmpeg([...input, "-i", palette, "-lavfi", `${filters}[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle`, "-loop", "0", `${out}.gif`]);
      const mb = (statSync(`${out}.gif`).size / 1048576).toFixed(1);
      console.log(`Wrote ${out}.gif (${mb} MB)`);
    }
  }
} finally {
  await browser.close();
  rmSync(work, { recursive: true, force: true });
  if (!o.keep) rmSync(frames, { recursive: true, force: true });
}
