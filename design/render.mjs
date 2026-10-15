// SPDX-License-Identifier: Apache-2.0
//
// Renders the design mockups (design/mockup/*.dc.html) to PNG screenshots using headless Chrome.
//   node design/render.mjs
// Output: docs/assets/screenshots/*.png and docs/assets/icon.png
// The screenshots show demo data from the mockups. They are design renderings, not the shipping app.

import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const chrome = process.env.CHROME ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const scale = 2;

const boards = {
  "Main.dc.html": "menu-bar-popover",
  "Sites.dc.html": "sites",
  "NewGithub.dc.html": "add-site-github",
  "Storage.dc.html": "storage",
  "Share.dc.html": "share",
  "Agents.dc.html": "agents",
};

const canvas = JSON.parse(readFileSync(join(root, "design/mockup/canvas.json"), "utf8"));

// --- minimal expander for the mockup template syntax: {{holes}}, <sc-for>, <sc-if> ---

function lookup(path, scope) {
  const p = path.trim();
  if (p === "true") return true;
  if (p === "false") return false;
  return p.split(".").reduce((v, k) => (v == null ? undefined : v[k]), scope);
}

function attr(tag, name) {
  const m = tag.match(new RegExp(`${name}="([^"]*)"`));
  return m ? m[1] : undefined;
}

function findClose(html, from, name) {
  const open = `<${name} `;
  const close = `</${name}>`;
  let depth = 1;
  let i = from;
  while (depth > 0) {
    const o = html.indexOf(open, i);
    const c = html.indexOf(close, i);
    if (c === -1) throw new Error(`unclosed <${name}>`);
    if (o !== -1 && o < c) {
      depth++;
      i = o + open.length;
    } else {
      depth--;
      i = c + close.length;
    }
  }
  return i;
}

function expand(html, scope) {
  let out = "";
  let i = 0;
  const re = /<(sc-for|sc-if) /g;
  while (true) {
    re.lastIndex = i;
    const m = re.exec(html);
    if (!m) {
      out += html.slice(i);
      break;
    }
    out += html.slice(i, m.index);
    const name = m[1];
    const tagEnd = html.indexOf(">", m.index);
    const tag = html.slice(m.index, tagEnd + 1);
    const end = findClose(html, tagEnd + 1, name);
    const inner = html.slice(tagEnd + 1, end - `</${name}>`.length);
    if (name === "sc-for") {
      const list = lookup(attr(tag, "list").replace(/[{}]/g, ""), scope) ?? [];
      const as = attr(tag, "as");
      list.forEach((item, index) => {
        out += expand(inner, { ...scope, [as]: item, $index: index });
      });
    } else if (lookup(attr(tag, "value").replace(/[{}]/g, ""), scope)) {
      out += expand(inner, scope);
    }
    i = end;
  }
  return out.replace(/\{\{\s*([^}]+?)\s*\}\}/g, (_, path) => String(lookup(path, scope) ?? ""));
}

function renderBoard(file) {
  const src = readFileSync(join(root, "design/mockup", file), "utf8");
  const body = src.match(/<x-dc>([\s\S]*?)<\/x-dc>/)[1];
  const css = (body.match(/<helmet>([\s\S]*?)<\/helmet>/) ?? [, ""])[1];
  const markup = body.replace(/<helmet>[\s\S]*?<\/helmet>/, "");
  const code = src.match(/<script type="text\/x-dc"[^>]*>([\s\S]*?)<\/script>/)[1];
  const Component = new Function("DCLogic", `${code}\nreturn Component;`)(
    class DCLogic {
      props = {};
      state = {};
    },
  );
  const vals = new Component().renderVals();
  return `<!doctype html><html lang="en"><head><meta charset="utf-8">${css}</head><body style="margin:0">${expand(markup, vals)}</body></html>`;
}

function shoot(htmlPath, pngPath, width, height, transparent = false) {
  const args = [
    "--headless=new",
    "--disable-gpu",
    "--hide-scrollbars",
    `--force-device-scale-factor=${scale}`,
    `--window-size=${width},${height}`,
    `--screenshot=${pngPath}`,
    ...(transparent ? ["--default-background-color=00000000"] : []),
    `file://${htmlPath}`,
  ];
  execFileSync(chrome, args, { stdio: "ignore" });
}

const work = join(tmpdir(), "warren-render");
mkdirSync(work, { recursive: true });
mkdirSync(join(root, "docs/assets/screenshots"), { recursive: true });

for (const [file, name] of Object.entries(boards)) {
  const { w, h } = canvas.boards[file];
  const htmlPath = join(work, `${name}.html`);
  writeFileSync(htmlPath, renderBoard(file));
  shoot(htmlPath, join(root, "docs/assets/screenshots", `${name}.png`), w, h);
  console.log(`rendered ${name} (${w}x${h})`);
}

const iconHtml = join(work, "icon.html");
const svg = readFileSync(join(root, "docs/assets/icon.svg"), "utf8");
writeFileSync(iconHtml, `<!doctype html><body style="margin:0;background:transparent">${svg.replace("<svg ", '<svg width="512" height="512" ')}</body>`);
shoot(iconHtml, join(root, "docs/assets/icon.png"), 512, 512, true);
console.log("rendered icon");
