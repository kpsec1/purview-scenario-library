// Sync the Purview scenario library into the Astro content collection.
//
// For each scenario we publish the FULL lifecycle on-site so a visitor can go
// start to end without leaving for GitHub:
//   <cat>/<slug>.md           overview (README)
//   <cat>/<slug>.design.md    design notes
//   <cat>/<slug>.deploy.md    deployment scripts (deploy/** inlined)
//   <cat>/<slug>.validate.md  validation scripts (validate/** inlined)
//   <cat>/<slug>.rollback.md  rollback notes
//
// Cross-references to other scenarios (backticked `scenarios/<cat>/<slug>/`)
// are rewritten as on-site links so the reader stays connected.
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, '..', '..');
const scenariosRoot = path.join(repoRoot, 'scenarios');
const outRoot = path.join(scriptDir, '..', 'src', 'content', 'scenarios');

const PART_ORDER = ['design', 'deploy', 'validate', 'rollback'];

const LANG_BY_EXT = {
  '.ps1': 'powershell',
  '.psm1': 'powershell',
  '.psd1': 'powershell',
  '.json': 'json',
  '.md': 'markdown',
  '.sql': 'sql',
  '.yml': 'yaml',
  '.yaml': 'yaml',
};

async function isDir(p) {
  try {
    return (await fs.stat(p)).isDirectory();
  } catch {
    return false;
  }
}

async function readMaybe(p) {
  try {
    return await fs.readFile(p, 'utf8');
  } catch {
    return null;
  }
}

async function walkFiles(dir) {
  const out = [];
  let entries;
  try {
    entries = await fs.readdir(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const e of entries.sort((a, b) => a.name.localeCompare(b.name))) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...(await walkFiles(full)));
    else out.push(full);
  }
  return out;
}

function extractTitle(markdown, fallback) {
  for (const line of markdown.split('\n')) {
    const m = line.match(/^#\s+(.*\S)\s*$/);
    if (m) return m[1].trim();
  }
  return fallback;
}

function stripFirstH1(markdown) {
  const lines = markdown.split('\n');
  const idx = lines.findIndex((l) => /^#\s+\S/.test(l));
  if (idx === -1) return markdown;
  lines.splice(idx, 1);
  if (lines[idx] !== undefined && lines[idx].trim() === '') lines.splice(idx, 1);
  return lines.join('\n');
}

function splitCategory(title, fallbackCategory) {
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

// Rewrite backticked `scenarios/<cat>/<slug>/` refs into on-site links, and
// collect the related scenario ids. Only rewrites refs to scenarios we publish.
function internalizeRefs(markdown, validSet, selfId, relatedOut) {
  return markdown.replace(
    /`scenarios\/([a-z0-9-]+)\/([a-z0-9-]+)\/?`/g,
    (match, cat, slug) => {
      const id = `${cat}/${slug}`;
      if (!validSet.has(id)) return match;
      if (id !== selfId && relatedOut && !relatedOut.includes(id)) relatedOut.push(id);
      return `[\`${cat}/${slug}\`](/scenarios/${cat}/${slug}/)`;
    }
  );
}

function fenceFor(content) {
  // Use a fence longer than any run of backticks inside the content.
  let max = 0;
  for (const m of content.matchAll(/`+/g)) max = Math.max(max, m[0].length);
  return '`'.repeat(Math.max(3, max + 1));
}

async function buildScriptDoc(dir, kind) {
  const files = (await walkFiles(dir)).filter((f) => !f.endsWith('.DS_Store'));
  if (files.length === 0) return { md: null, count: 0 };
  const intro =
    kind === 'deploy'
      ? 'The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.\n'
      : 'Run these checks after deployment to confirm the control is working as designed.\n';
  const parts = [intro];
  for (const file of files) {
    const rel = path.relative(dir, file).split(path.sep).join('/');
    const ext = path.extname(file).toLowerCase();
    const lang = LANG_BY_EXT[ext] ?? '';
    const content = (await readMaybe(file)) ?? '';
    const fence = fenceFor(content);
    parts.push(`#### \`${rel}\`\n\n${fence}${lang}\n${content.replace(/\s+$/, '')}\n${fence}`);
  }
  return { md: parts.join('\n\n'), count: files.length };
}

function frontmatter(obj) {
  const lines = ['---'];
  for (const [k, v] of Object.entries(obj)) {
    if (v === undefined) continue;
    lines.push(`${k}: ${JSON.stringify(v)}`);
  }
  lines.push('---', '');
  return lines.join('\n');
}

async function main() {
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

  // First pass: the set of valid scenario ids, for cross-ref linking.
  const validSet = new Set();
  for (const category of categories) {
    const catDir = path.join(scenariosRoot, category);
    const slugs = (await fs.readdir(catDir, { withFileTypes: true }))
      .filter((d) => d.isDirectory())
      .map((d) => d.name);
    for (const slug of slugs) {
      if (await readMaybe(path.join(catDir, slug, 'README.md'))) {
        validSet.add(`${category}/${slug}`);
      }
    }
  }

  let count = 0;
  for (const category of categories) {
    const catDir = path.join(scenariosRoot, category);
    const slugs = (await fs.readdir(catDir, { withFileTypes: true }))
      .filter((d) => d.isDirectory())
      .map((d) => d.name)
      .sort();

    for (const slug of slugs) {
      const dir = path.join(catDir, slug);
      const readme = await readMaybe(path.join(dir, 'README.md'));
      if (readme === null) continue;

      const id = `${category}/${slug}`;
      const rawTitle = extractTitle(readme, prettyCategory(slug));
      const { category: catLabel, short } = splitCategory(rawTitle, prettyCategory(category));
      const related = [];
      const overviewBody = internalizeRefs(stripFirstH1(readme), validSet, id, related);

      const outDir = path.join(outRoot, category);
      await fs.mkdir(outDir, { recursive: true });

      const parts = [];

      // Design
      const designRaw = await readMaybe(path.join(dir, 'design.md'));
      if (designRaw) {
        const body = internalizeRefs(stripFirstH1(designRaw), validSet, id, related);
        await fs.writeFile(
          path.join(outDir, `${slug}.design.md`),
          frontmatter({ part: 'design', parent: id }) + body,
          'utf8'
        );
        parts.push('design');
      }

      // Deploy scripts
      const deploy = await buildScriptDoc(path.join(dir, 'deploy'), 'deploy');
      if (deploy.md) {
        await fs.writeFile(
          path.join(outDir, `${slug}.deploy.md`),
          frontmatter({ part: 'deploy', parent: id }) + deploy.md,
          'utf8'
        );
        parts.push('deploy');
      }

      // Validate scripts
      const validate = await buildScriptDoc(path.join(dir, 'validate'), 'validate');
      if (validate.md) {
        await fs.writeFile(
          path.join(outDir, `${slug}.validate.md`),
          frontmatter({ part: 'validate', parent: id }) + validate.md,
          'utf8'
        );
        parts.push('validate');
      }

      // Rollback
      const rollbackRaw = await readMaybe(path.join(dir, 'rollback.md'));
      if (rollbackRaw) {
        const body = internalizeRefs(stripFirstH1(rollbackRaw), validSet, id, related);
        await fs.writeFile(
          path.join(outDir, `${slug}.rollback.md`),
          frontmatter({ part: 'rollback', parent: id }) + body,
          'utf8'
        );
        parts.push('rollback');
      }

      // Overview (must be written last so `related` is complete)
      const overviewFm = frontmatter({
        title: short,
        fullTitle: rawTitle,
        category: catLabel,
        categorySlug: category,
        slug,
        repoPath: `scenarios/${category}/${slug}`,
        parts: parts.sort((a, b) => PART_ORDER.indexOf(a) - PART_ORDER.indexOf(b)),
        related,
        deployCount: deploy.count,
        validateCount: validate.count,
      });
      await fs.writeFile(path.join(outDir, `${slug}.md`), overviewFm + overviewBody, 'utf8');
      count += 1;
    }
  }

  console.log(
    `sync-scenarios: wrote ${count} scenarios (overview + lifecycle parts) from ${categories.length} categories`
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
