// Sync the Purview scenario library into the Astro content collection.
//
// Per scenario we generate:
//   src/content/scenarios/<cat>/<slug>.md            overview (README, cleaned)
//   src/content/scenarios/<cat>/<slug>.design.md     design notes (cleaned)
//   src/content/scenarios/<cat>/<slug>.rollback.md   rollback runbook (cleaned)
//   src/data/scenario-scripts/<cat>/<slug>.json      deploy/validate scripts
//
// "Cleaned" means every em/en dash in prose is removed (never inside code), so
// the whole site is free of long dashes. Overview frontmatter carries the
// At-a-glance facts and a contents list for the redesigned scenario page.
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import GithubSlugger from 'github-slugger';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, '..', '..');
const scenariosRoot = path.join(repoRoot, 'scenarios');
const outRoot = path.join(scriptDir, '..', 'src', 'content', 'scenarios');
const dataRoot = path.join(scriptDir, '..', 'src', 'data', 'scenario-scripts');

const LANG_BY_EXT = {
  '.ps1': 'powershell',
  '.psm1': 'powershell',
  '.psd1': 'powershell',
  '.json': 'json',
  '.md': 'markdown',
  '.sql': 'sql',
  '.yml': 'yaml',
  '.yaml': 'yaml',
  '.bicep': 'bicep',
  '.xml': 'xml',
  '.csv': 'text',
  '.txt': 'text',
};

const FRAMEWORKS = [
  ['GDPR', /\bGDPR\b/],
  ['HIPAA', /\bHIPAA\b/],
  ['PCI DSS', /\bPCI[-\s]?DSS\b/],
  ['SOC 2', /\bSOC[-\s]?2\b/],
  ['ISO 27001', /\bISO(?:\/IEC)?\s?27001\b/],
  ['NIST', /\bNIST\b/],
  ['CCPA', /\bCCPA\b/],
  ['SOX', /\bSOX\b|\bSarbanes[-\s]?Oxley\b/],
  ['FINRA', /\bFINRA\b/],
  ['FedRAMP', /\bFedRAMP\b/],
];

const LICENSES = [
  ['Microsoft 365 E5', /\bM(?:icrosoft )?365 E5\b|\bE5\b/],
  ['E5 Compliance', /\bE5 Compliance\b/],
  ['Microsoft 365 E3', /\bM(?:icrosoft )?365 E3\b|\bE3\b/],
  ['Teams Premium', /\bTeams Premium\b/],
  ['SharePoint Advanced Management', /\bSharePoint Advanced Management\b|\bSAM\b/],
  ['Defender for Endpoint P2', /\bDefender for Endpoint(?: Plan 2| P2)?\b/],
  ['Entra ID P2', /\bEntra ID P2\b|\bAzure AD Premium P2\b/],
  ['Pay-as-you-go', /\bpay[-\s]?as[-\s]?you[-\s]?go\b|\bconsumption[-\s]?based\b/],
];

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
    else if (e.name !== '.DS_Store') out.push(full);
  }
  return out;
}

// Replace long dashes: numeric ranges become hyphens, everything else a comma.
function cleanDashes(text) {
  return text
    .replace(/(\d)\s*[–—]\s*(\d)/g, '$1-$2')
    .replace(/\s*[–—]\s*/g, ', ');
}

// Remove long dashes from all rendered content: prose, Mermaid diagram labels,
// and inline code examples in the README. Mermaid arrows and PowerShell flags
// use plain hyphens, which cleanDashes never touches. The actual deploy/validate
// script files are published separately and verbatim.
function cleanProse(markdown) {
  return markdown.split('\n').map(cleanDashes).join('\n');
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

function extractWhoFor(readme) {
  const m = readme.match(/\*\*Who it'?s for:\*\*\s*(.+)/);
  return m ? cleanDashes(m[1].replace(/\s+/g, ' ').trim()) : undefined;
}

function detectFromList(text, list) {
  const found = [];
  for (const [label, re] of list) if (re.test(text)) found.push(label);
  return found;
}

function sectionText(readme, headingRe) {
  const lines = readme.split('\n');
  const start = lines.findIndex((l) => headingRe.test(l));
  if (start === -1) return '';
  let end = lines.length;
  for (let i = start + 1; i < lines.length; i++) {
    if (/^## /.test(lines[i])) {
      end = i;
      break;
    }
  }
  return lines.slice(start + 1, end).join('\n');
}

// Build the contents list from the README's H2 headings, matching the ids that
// rehype-slug will assign (fresh slugger over all headings in document order).
function buildToc(readme) {
  const slugger = new GithubSlugger();
  const toc = [];
  for (const line of readme.split('\n')) {
    const m = line.match(/^(#{2,6})\s+(.*\S)\s*$/);
    if (!m) continue;
    const text = cleanDashes(m[2].trim());
    const id = slugger.slug(text);
    if (m[1].length === 2) toc.push({ id, text });
  }
  return toc;
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

async function collectScripts(dir) {
  const files = await walkFiles(dir);
  const scripts = [];
  for (const file of files) {
    const rel = path.relative(dir, file).split(path.sep).join('/');
    const ext = path.extname(file).toLowerCase();
    const lang = LANG_BY_EXT[ext] ?? 'text';
    const code = (await readMaybe(file)) ?? '';
    scripts.push({ path: rel, lang, code: code.replace(/\s+$/, '') });
  }
  return scripts;
}

async function main() {
  if (!(await isDir(scenariosRoot))) {
    console.log(
      `sync-scenarios: source ${scenariosRoot} not found, keeping committed content, nothing to sync`
    );
    return;
  }

  await fs.rm(outRoot, { recursive: true, force: true });
  await fs.mkdir(outRoot, { recursive: true });
  await fs.rm(dataRoot, { recursive: true, force: true });
  await fs.mkdir(dataRoot, { recursive: true });

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
      const dir = path.join(catDir, slug);
      const readme = await readMaybe(path.join(dir, 'README.md'));
      if (readme === null) continue;

      const rawTitle = extractTitle(readme, prettyCategory(slug));
      const { category: catLabel, short } = splitCategory(rawTitle, prettyCategory(category));

      const whoFor = extractWhoFor(readme);
      const frameworks = detectFromList(readme, FRAMEWORKS);
      const licensing = detectFromList(
        sectionText(readme, /^##\s+\d+\.\s+Cost/) || readme,
        LICENSES
      );
      const toc = buildToc(readme);

      const deploy = await collectScripts(path.join(dir, 'deploy'));
      const validate = await collectScripts(path.join(dir, 'validate'));
      const designRaw = await readMaybe(path.join(dir, 'design.md'));
      const rollbackRaw = await readMaybe(path.join(dir, 'rollback.md'));

      const outDir = path.join(outRoot, category);
      await fs.mkdir(outDir, { recursive: true });

      if (designRaw) {
        await fs.writeFile(
          path.join(outDir, `${slug}.design.md`),
          frontmatter({ part: 'design', parent: `${category}/${slug}` }) +
            cleanProse(stripFirstH1(designRaw)),
          'utf8'
        );
      }
      if (rollbackRaw) {
        await fs.writeFile(
          path.join(outDir, `${slug}.rollback.md`),
          frontmatter({ part: 'rollback', parent: `${category}/${slug}` }) +
            cleanProse(stripFirstH1(rollbackRaw)),
          'utf8'
        );
      }

      if (deploy.length || validate.length) {
        const dataDir = path.join(dataRoot, category);
        await fs.mkdir(dataDir, { recursive: true });
        await fs.writeFile(
          path.join(dataDir, `${slug}.json`),
          JSON.stringify({ deploy, validate }),
          'utf8'
        );
      }

      await fs.writeFile(
        path.join(outDir, `${slug}.md`),
        frontmatter({
          title: cleanDashes(short),
          category: catLabel,
          categorySlug: category,
          slug,
          whoFor,
          frameworks,
          licensing,
          deployCount: deploy.length,
          validateCount: validate.length,
          hasDesign: Boolean(designRaw),
          hasRollback: Boolean(rollbackRaw),
          toc,
        }) + cleanProse(stripFirstH1(readme)),
        'utf8'
      );
      count += 1;
    }
  }

  console.log(`sync-scenarios: wrote ${count} scenarios from ${categories.length} categories`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
