// Sync the Purview scenario library READMEs into the Astro content collection.
// Reads ../../scenarios/<category>/<slug>/README.md, extracts the H1 as the
// title, and writes a content-collection entry with frontmatter so the site
// can render one page per scenario. This is the only content published to the
// site: the Purview scenario library.
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, '..', '..');
const scenariosRoot = path.join(repoRoot, 'scenarios');
const outRoot = path.join(scriptDir, '..', 'src', 'content', 'scenarios');

async function isDir(p) {
  try {
    return (await fs.stat(p)).isDirectory();
  } catch {
    return false;
  }
}

function extractTitle(markdown, fallback) {
  for (const line of markdown.split('\n')) {
    const m = line.match(/^#\s+(.*\S)\s*$/);
    if (m) return m[1].trim();
  }
  return fallback;
}

// Drop the first H1 line from the body; the page template renders the title.
function stripFirstH1(markdown) {
  const lines = markdown.split('\n');
  const idx = lines.findIndex((l) => /^#\s+\S/.test(l));
  if (idx === -1) return markdown;
  lines.splice(idx, 1);
  // also drop a single leading blank line left behind
  if (lines[idx] !== undefined && lines[idx].trim() === '') lines.splice(idx, 1);
  return lines.join('\n');
}

function splitCategory(title, fallbackCategory) {
  // Titles look like "DLP — Endpoint DLP: Block USB ..." — split on the em dash.
  const parts = title.split(' — ');
  if (parts.length >= 2) {
    return { category: parts[0].trim(), short: parts.slice(1).join(' — ').trim() };
  }
  return { category: fallbackCategory, short: title };
}

function prettyCategory(slug) {
  return slug
    .split('-')
    .map((w) => (w.length <= 3 ? w.toUpperCase() : w[0].toUpperCase() + w.slice(1)))
    .join(' ');
}

async function main() {
  // The scenario source lives in the purview-scenario-library repo. When this
  // site is deployed from its own repo (kpsec1.github.io) that source is not
  // present, so we keep the committed content as-is instead of wiping it.
  if (!(await isDir(scenariosRoot))) {
    console.log(
      `sync-scenarios: source ${scenariosRoot} not found — keeping committed content, nothing to sync`
    );
    return;
  }

  await fs.rm(outRoot, { recursive: true, force: true });
  await fs.mkdir(outRoot, { recursive: true });

  const categories = (await fs.readdir(scenariosRoot, { withFileTypes: true }))
    .filter((d) => d.isDirectory())
    .map((d) => d.name)
    .sort();

  let count = 0;
  for (const category of categories) {
    const catDir = path.join(scenariosRoot, category);
    const slugs = (await fs.readdir(catDir, { withFileTypes: true }))
      .filter((d) => d.isDirectory())
      .map((d) => d.name)
      .sort();

    for (const slug of slugs) {
      const readme = path.join(catDir, slug, 'README.md');
      if (!(await isDir(path.join(catDir, slug)))) continue;
      let raw;
      try {
        raw = await fs.readFile(readme, 'utf8');
      } catch {
        continue; // no README in this dir
      }

      const rawTitle = extractTitle(raw, prettyCategory(slug));
      const { category: catLabel, short } = splitCategory(rawTitle, prettyCategory(category));
      const body = stripFirstH1(raw);

      const frontmatter = [
        '---',
        `title: ${JSON.stringify(short)}`,
        `fullTitle: ${JSON.stringify(rawTitle)}`,
        `category: ${JSON.stringify(catLabel)}`,
        `categorySlug: ${JSON.stringify(category)}`,
        `slug: ${JSON.stringify(slug)}`,
        `repoPath: ${JSON.stringify(`scenarios/${category}/${slug}`)}`,
        '---',
        '',
      ].join('\n');

      const outDir = path.join(outRoot, category);
      await fs.mkdir(outDir, { recursive: true });
      await fs.writeFile(path.join(outDir, `${slug}.md`), frontmatter + body, 'utf8');
      count += 1;
    }
  }

  console.log(`sync-scenarios: wrote ${count} scenario pages from ${categories.length} categories`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
