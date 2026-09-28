// Sync the Purview scenario library into the Astro content collections.
//
// Each scenario becomes a "field note" (blog post) made of:
//   <cat>/<slug>.md           the story: short version, why it matters, how the
//                             control works, what it takes, proof, limits
//   <cat>/<slug>.runbook.md   the technical runbook: steps, config, operations,
//                             rollback plan, references
//   <cat>/<slug>.design.md    design notes
//   <cat>/<slug>.rollback.md  rollback runbook
//   src/data/scenario-scripts/<cat>/<slug>.json   deploy + validate scripts
//
// The source READMEs were written for engineers browsing a repository, so they
// point at other files ("see design.md section 4", "scenarios/x/y/"). For the
// site those pointers are turned into plain wording. Rules are deterministic and
// never touch code blocks, so technical facts are preserved.
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import GithubSlugger from 'github-slugger';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const siteRoot = path.join(scriptDir, '..');
const repoRoot = path.resolve(siteRoot, '..');
const scenariosRoot = path.join(repoRoot, 'scenarios');
const docsRoot = path.join(repoRoot, 'docs');
const outRoot = path.join(siteRoot, 'src', 'content', 'scenarios');
const refdocsOut = path.join(siteRoot, 'src', 'content', 'refdocs');
const dataRoot = path.join(siteRoot, 'src', 'data', 'scenario-scripts');

const REF_DOCS = {
  'licensing-matrix': 'Licensing matrix',
  'rbac-model': 'RBAC model',
  'automation-surface': 'Automation surface',
  glossary: 'Glossary',
};
const DOC_NAMES = Object.keys(REF_DOCS).join('|');

// Plain wording for references to a scenario's own README sections.
const SECTION_NOUN = {
  1: 'the short version',
  2: 'why this matters',
  3: 'the prerequisites',
  4: 'the architecture',
  5: 'the implementation steps',
  6: 'the configuration reference',
  7: 'the validation steps',
  8: 'operations and tuning',
  9: 'the rollback plan',
  10: 'the cost and licensing notes',
  11: 'the known limitations',
  12: 'the references',
};

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

// ---------------------------------------------------------------- utilities

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

function cleanDashes(text) {
  return text
    .replace(/(\d)\s*[–—]\s*(\d)/g, '$1-$2')
    .replace(/\s*[–—]\s*/g, ', ');
}

const cap = (s) => (s ? s[0].toUpperCase() + s.slice(1) : s);
const humanizeSlug = (slug) => cap(slug.replace(/-/g, ' '));

// Run proseFn over the non-code chunks of a markdown document and fenceFn over
// each line inside a fenced code block. Chunks (not single lines) are passed to
// proseFn so references wrapped across lines are still matched.
function mapProse(markdown, proseFn, fenceFn) {
  const lines = markdown.split('\n');
  const out = [];
  let buf = [];
  let inFence = false;
  let fenceChar = '';
  let fenceLang = '';
  const flush = () => {
    if (buf.length) {
      out.push(proseFn(buf.join('\n')));
      buf = [];
    }
  };
  for (const line of lines) {
    const m = line.match(/^\s*(```+|~~~+)\s*([A-Za-z0-9-]*)/);
    if (m) {
      if (!inFence) {
        flush();
        inFence = true;
        fenceChar = m[1][0];
        fenceLang = m[2].toLowerCase();
        out.push(line);
        continue;
      }
      if (line.trim().startsWith(fenceChar)) {
        inFence = false;
        fenceLang = '';
        out.push(line);
        continue;
      }
    }
    if (inFence) out.push(fenceFn(line, fenceLang));
    else buf.push(line);
  }
  flush();
  return out.join('\n');
}

// ------------------------------------------------------ mermaid sanitizing

function quoteMermaidLabels(seg) {
  const needQuote = (i) => i && !i.trim().startsWith('"') && /[(){},@#]/.test(i);
  const q = (i) => '"' + i.replace(/"/g, '&quot;') + '"';
  let s = seg;
  s = s.replace(/\[\[([^\]|]+?)\]\]/g, (m, i) => (needQuote(i) ? `[[${q(i)}]]` : m));
  s = s.replace(/\[\(([^)|]+?)\)\]/g, (m, i) => (needQuote(i) ? `[(${q(i)})]` : m));
  s = s.replace(/\(\[([^\]|]+?)\]\)/g, (m, i) => (needQuote(i) ? `([${q(i)}])` : m));
  s = s.replace(/\{\{([^}|]+?)\}\}/g, (m, i) => (needQuote(i) ? `{{${q(i)}}}` : m));
  s = s.replace(/(?<![[(])\[([^\][|]+?)\](?![)\]])/g, (m, i) => (needQuote(i) ? `[${q(i)}]` : m));
  s = s.replace(/(?<!\{)\{([^{}|]+?)\}(?!\})/g, (m, i) => (needQuote(i) ? `{${q(i)}}` : m));
  return s;
}

function sanitizeMermaid(line) {
  let s = line.replace(/&mdash;|&ndash;/g, '-');
  const ents = [];
  s = s.replace(/&#?[a-zA-Z0-9]+;/g, (m) => {
    ents.push(m);
    return `\u0000${ents.length - 1}\u0000`;
  });
  const parts = s.split(/("(?:[^"\\]|\\.)*")/g);
  s = parts
    .map((seg) => {
      const isQuoted = seg.length >= 2 && seg.startsWith('"') && seg.endsWith('"');
      let t = seg.replace(/\s*[–—]\s*/g, ' - ');
      if (isQuoted) return t;
      t = t.replace(/-\.-\.->/g, '-.->');
      t = t.replace(/-\.-(?=[A-Za-z])/g, '-.');
      t = t.replace(/;/g, ' - ');
      return quoteMermaidLabels(t);
    })
    .join('');
  return s.replace(/\u0000(\d+)\u0000/g, (m, i) => ents[Number(i)]);
}

// ------------------------------------------------ reference normalization

// Filled in by main() before any content is generated.
const ctxData = {
  titleById: {}, // "cat/slug" -> short title
  idBySlug: {}, // "slug" -> "cat/slug" (unique slugs only)
  docSections: {}, // doc name -> { "9": "heading-id" }
  areaLabel: {}, // "dlp" -> "DLP"
};

// A section mark, optionally a list ("§3/§7", "§3, §7") or a range ("§4-6").
const SEC = '§\\s?\\d+(?:\\s*(?:[\\/,]|[-\\u2013\\u2014])\\s*§?\\s?\\d+)*';

// Section numbers in a mark; a hyphen or dash between two numbers is a range.
function nums(str) {
  const out = [];
  for (const m of String(str || '').matchAll(/(\d+)(?:\s*[-–—]\s*(\d+))?/g)) {
    const a = Number(m[1]);
    const b = m[2] ? Number(m[2]) : a;
    if (b > a && b - a <= 8) for (let i = a; i <= b; i++) out.push(String(i));
    else {
      out.push(String(a));
      if (m[2]) out.push(String(b));
    }
  }
  return out;
}

function scenarioRef(id, slug, secs, selfId, followedByParen) {
  if (id === selfId) return 'this page';
  const title = ctxData.titleById[id] ?? humanizeSlug(slug);
  const nouns = nums(secs).map((n) => SECTION_NOUN[n]).filter(Boolean);
  // Skip the section name when a parenthetical already follows: avoids "(a) (b)".
  return nouns.length && !followedByParen ? `*${title}* (${nouns.join(' and ')})` : `*${title}*`;
}

const startsWithParen = (str, end) => /^[ \t]*\(/.test(str.slice(end));

function docLink(name, secs) {
  const n = nums(secs);
  const first = n[0];
  const anchor = first && ctxData.docSections[name]?.[first] ? `#${ctxData.docSections[name][first]}` : '';
  const label =
    REF_DOCS[name] + (n.length ? `, section${n.length > 1 ? 's' : ''} ${n.join(' and ')}` : '');
  return `[${label}](/docs/${name}/${anchor})`;
}

// A parenthetical that holds nothing but file or section pointers is deleted.
function isPureRefs(inner) {
  if (!/(?:§|\.md)/.test(inner)) return false;
  const rest = inner
    .replace(/`?\b(?:README|design|rollback|reviews|PROGRESS|AGENTS|CONTRIBUTING)\.md`?/g, '')
    .replace(new RegExp(SEC, 'g'), '')
    .replace(
      /\b(?:see|per|also|and|in|cf\.?|of|this|the|README|design notes|Red Team|Blue Team|CISO|Microsoft Product Owner|Product Owner|lens|lenses|round|rounds|review|Step|steps?)\b/gi,
      ''
    )
    .replace(/[\s,;:/\-&.\d]+/g, '');
  return rest.length === 0;
}

function normalizeProse(text, mode, selfId) {
  let s = text;

  // A. Inline citation markers such as [[1]](#references).
  s = s.replace(/[ \t]?\[\[[^[\]]{1,15}\]\]\([^)]*\)/g, '').replace(/[ \t]?\[\[[^[\]]{1,15}\]\]/g, '');

  // A2. Words hard-wrapped at a hyphen ("compliance-\ncopy-only") would render
  // with a stray space; rejoin them. Covers file names ("automation-\nsurface.md").
  s = s.replace(/([A-Za-z])-[ \t]*\n[ \t]*([a-z])/g, '$1-$2');
  s = s.replace(/\b(licensing|rbac|automation)-[ \t]*\n?[ \t]*(matrix|model|surface)(?=\.md)/g, '$1-$2');
  s = s.replace(/(scenarios\/[a-z0-9-]+\/)[ \t]*\n[ \t]*(?=[a-z0-9])/g, '$1');

  // B. Shared reference docs: `docs/licensing-matrix.md` §9 -> link.
  s = s.replace(
    new RegExp('`?(?:docs\\/)?\\b(' + DOC_NAMES + ')\\.md`?((?:\\s*' + SEC + ')?)', 'g'),
    (m, name, secs) => docLink(name, secs)
  );

  // C. Other scenarios, by full path, short path or bare slug.
  s = s.replace(
    new RegExp(
      '`?\\bscenarios\\/([a-z0-9-]+)\\/([a-z0-9-]+)\\/?(?:(?:README|design|rollback|reviews)\\.md|(?:deploy|validate)\\/[^\\s`)]*)?`?((?:\\s*' +
        SEC +
        ')?)',
      'g'
    ),
    (m, cat, slug, secs, offset, str) =>
      scenarioRef(`${cat}/${slug}`, slug, secs, selfId, startsWithParen(str, offset + m.length))
  );
  // Area folders: `scenarios/dlp/` or `scenarios/dlp/*` -> the area's name.
  s = s.replace(/`?\bscenarios\/([a-z0-9-]+)\/(?:\*+)?`?(?![a-z0-9])/g, (m, cat) => `*${ctxData.areaLabel[cat] ?? humanizeSlug(cat)}*`);
  s = s.replace(
    new RegExp('`([a-z0-9][a-z0-9-]*)\\/(?:README|design|rollback|reviews)\\.md`((?:\\s*' + SEC + ')?)', 'g'),
    (m, slug, secs, offset, str) =>
      ctxData.idBySlug[slug]
        ? scenarioRef(ctxData.idBySlug[slug], slug, secs, selfId, startsWithParen(str, offset + m.length))
        : m
  );
  s = s.replace(/`([a-z0-9]+(?:-[a-z0-9]+)+)`/g, (m, slug) =>
    ctxData.idBySlug[slug] ? scenarioRef(ctxData.idBySlug[slug], slug, '', selfId) : m
  );

  // D. Parentheticals that are only pointers to other files or sections. After
  // a possessive ("the parent scenario's (README.md section 10)") keep the
  // section name instead, so the sentence stays grammatical.
  s = s.replace(new RegExp('[ \\t]*\\(([^()]*)\\)', 'g'), (m, inner, offset, str) => {
    if (!isPureRefs(inner)) return m;
    if (str.slice(Math.max(0, offset - 2), offset) === "'s") {
      const n = nums((inner.match(new RegExp(SEC)) || [''])[0]);
      const noun = n.map((x) => SECTION_NOUN[x]).filter(Boolean).join(' and ').replace(/^the /, '');
      if (noun) return ` ${noun}`;
    }
    return '';
  });

  // E. Remaining pointers to this scenario's own files and the contributor guides.
  s = s.replace(
    new RegExp('[ \\t]*\\((?:see |per )?`?(?:AGENTS|CONTRIBUTING)\\.md`?(?:\\s*' + SEC + ')?\\)', 'g'),
    ''
  );
  s = s.replace(
    new RegExp(',?\\s*\\b(?:see|per)\\s+`?(?:AGENTS|CONTRIBUTING)\\.md`?(?:\\s*' + SEC + ')?', 'g'),
    ''
  );
  s = s.replace(
    new RegExp('`?(?:AGENTS|CONTRIBUTING)\\.md`?(?:\\s*' + SEC + ')?', 'g'),
    "this library's standards"
  );
  s = s.replace(/,?\s*\b(?:see|per)\s+`?PROGRESS\.md`?/gi, '');
  s = s.replace(/`?PROGRESS\.md`?\s+follow-ups?/g, 'project follow-up');
  s = s.replace(/`?PROGRESS\.md`?/g, 'the project backlog');
  // The four-lens review notes are not published, but the finding is still worth
  // stating: "reviews.md (Red Team finding 1)" -> "the Red Team review (finding 1)".
  const LENS = '(Red Team|Blue Team|CISO|Microsoft Product Owner|Product Owner)';
  s = s.replace(
    new RegExp('`?reviews\\.md`?\\s*\\(' + LENS + '(?:\\s+(finding \\d+|round \\d+))?\\)', 'g'),
    (m, lens, extra) => `the ${lens} review` + (extra ? ` (${extra})` : '')
  );
  s = s.replace(
    new RegExp('`?reviews\\.md`?,?\\s*' + LENS + '(?:\\s+lens)?(?:,?\\s+(finding \\d+))?', 'g'),
    (m, lens, f) => `the ${lens} review` + (f ? `, ${f}` : '')
  );
  s = s.replace(/`?reviews\.md`?'s\b/g, "the review notes'");
  s = s.replace(/`?reviews\.md`?/g, 'the review notes');
  s = s.replace(
    new RegExp('\\b(sibling|parent)(?:\\s+scenario)?(?:\'s)?\\s+`?README\\.md`?\\s*(' + SEC + ')', 'g'),
    (m, who, secs) => {
      const noun = nums(secs).map((n) => SECTION_NOUN[n]).filter(Boolean).join(' and ').replace(/^the /, '');
      return noun ? `the ${who} scenario's ${noun}` : m;
    }
  );
  s = s.replace(
    new RegExp('\\b(the|this|its)\\s+`?design\\.md`?(?:\\s*' + SEC + ')?', 'gi'),
    (m, w) => (w.toLowerCase() === 'the' ? 'the design notes' : `${w} design notes`)
  );
  s = s.replace(new RegExp('`?design\\.md`?(?:\\s*' + SEC + ')?', 'g'), 'the design notes');
  s = s.replace(/\b(the|this)\s+`?rollback\.md`?/gi, 'the rollback runbook');
  s = s.replace(/`?rollback\.md`?/g, 'the rollback runbook');
  s = s.replace(new RegExp('(' + SEC + ')\\s+of\\s+this\\s+README', 'g'), (m, secs) => {
    const nouns = nums(secs).map((n) => SECTION_NOUN[n]).filter(Boolean);
    return nouns.length ? nouns.join(' and ') : 'this page';
  });
  s = s.replace(new RegExp('`?README\\.md`?\\s*(' + SEC + ')', 'g'), (m, secs) => {
    const nouns = nums(secs).map((n) => SECTION_NOUN[n]).filter(Boolean);
    return nouns.length ? nouns.join(' and ') : 'this page';
  });
  s = s.replace(/\bthis README\b|\bthe README\b|`?README\.md`?/g, 'this page');
  s = s.replace(/\bREADME\b/g, 'page');

  // F. Bare section marks. Docs keep numbered headings, so "section N" is
  // accurate there. In scenarios, a mark maps to its section's plain name only
  // when nothing nearby points at another document; otherwise it becomes a
  // neutral "section N", which is never wrong.
  s = s.replace(/§\s?5\s+Step\s+(\d+)/g, mode === 'scenario' ? 'step $1 of the implementation steps' : 'section 5, step $1');
  s = s.replace(new RegExp(SEC, 'g'), (m, ...rest) => {
    const str = rest[rest.length - 1];
    const offset = rest[rest.length - 2];
    const n = nums(m);
    const neutral = `section${n.length > 1 ? 's' : ''} ${n.join(' and ')}`;
    if (mode === 'doc') return neutral;
    const before = str.slice(Math.max(0, offset - 70), offset);
    const stop = Math.max(before.lastIndexOf('. '), before.lastIndexOf('\n\n'));
    const nearby = stop >= 0 ? before.slice(stop) : before;
    if (/\]\(\/docs\/|\*[^*\n]+\*|the design notes|the rollback runbook/.test(nearby)) return neutral;
    const nouns = n.map((x) => SECTION_NOUN[x]).filter(Boolean);
    if (nouns.length) return nouns.join(' and ');
    // Not a README section (13 to 99): neutral wording. Legal citations such as
    // "45 CFR §164.312" have three digits and are left exactly as written.
    return n.every((x) => Number(x) < 100) ? neutral : m;
  });

  // G. Wording and tidy-up.
  s = s.replace(
    /\b(own|its|their)\s+the (design notes|rollback runbook|review notes|(?:Red Team|Blue Team|CISO|Microsoft Product Owner|Product Owner) review)\b/g,
    '$1 $2'
  );
  s = s.replace(/\bthis repo(?:sitory)?\b/g, 'this library');
  s = s.replace(/\bthe (the|this) /gi, (m, w) => `${w.toLowerCase()} `);
  s = s.replace(/\bthe the\b/gi, 'the');
  s = s.replace(/(\S)[ \t]{2,}(?=\S)/g, '$1 ');
  s = s.replace(/[ \t]*\n[ \t]*([.,;])(?=\s|$)/g, '$1'); // a removed citation left punctuation on its own line
  s = s.replace(/[ \t]+([.,;])(?=\s|$)/g, '$1');
  s = s.replace(/([^\s(])[ \t]+\)/g, '$1)');
  s = s.replace(/\(\s*\)/g, '');
  return s;
}

// Set DEBUG_SAMPLES=1 to print before/after windows for a random sample of edits.
const debugPairs = [];

function cleanContent(markdown, mode, selfId) {
  return mapProse(
    markdown,
    (chunk) => {
      const after = cleanDashes(normalizeProse(chunk, mode, selfId));
      if (process.env.DEBUG_SAMPLES && after !== chunk) {
        let i = 0;
        while (i < chunk.length && chunk[i] === after[i]) i++;
        debugPairs.push({
          id: selfId,
          before: chunk.slice(Math.max(0, i - 70), i + 110).replace(/\s+/g, ' '),
          after: after.slice(Math.max(0, i - 70), i + 110).replace(/\s+/g, ' '),
        });
      }
      return after;
    },
    (line, lang) => (lang === 'mermaid' ? sanitizeMermaid(line) : cleanDashes(line))
  );
}

// -------------------------------------------------------- README structure

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
  // "DLP - Endpoint DLP: Block USB ..." (hyphen) or "DLP \u2014 Endpoint DLP ..." (em dash):
  // the first separator splits area from title, if the area part is short like a name.
  const m = title.match(/^(.{2,60}?)\s+(?:\u2014|\u2013|-)\s+(.+)$/);
  if (m && m[1].trim().split(/\s+/).length <= 5) {
    return { category: m[1].trim(), short: m[2].trim() };
  }
  return { category: fallbackCategory, short: title };
}

function prettyCategory(slug) {
  return slug
    .split('-')
    .map((w) => (w.length <= 3 ? w.toUpperCase() : w[0].toUpperCase() + w.slice(1)))
    .join(' ');
}

// Split a README (without its H1) into a preamble and H2 sections, ignoring
// anything inside code fences.
function splitSections(body) {
  const lines = body.split('\n');
  const sections = [];
  let preamble = [];
  let current = null;
  let inFence = false;
  let fenceChar = '';
  for (const line of lines) {
    const f = line.match(/^\s*(```+|~~~+)/);
    if (f) {
      if (!inFence) {
        inFence = true;
        fenceChar = f[1][0];
      } else if (line.trim().startsWith(fenceChar)) {
        inFence = false;
      }
    }
    const h = !inFence && line.match(/^##\s+(?:(\d+)\.\s*)?(.+?)\s*$/);
    if (h) {
      current = { num: h[1] ? Number(h[1]) : null, title: h[2], lines: [] };
      sections.push(current);
      continue;
    }
    (current ? current.lines : preamble).push(line);
  }
  return {
    preamble: preamble.join('\n').trim(),
    sections: sections.map((s) => ({ ...s, body: s.lines.join('\n').trim() })),
  };
}

function demoteHeadings(body) {
  return mapProse(
    body,
    (chunk) => chunk.replace(/^(#{3,5})(\s)/gm, '#$1$2'),
    (line) => line
  );
}

function extractWhoFor(body) {
  // No "m" flag: "$" must mean end of the whole text so a wrapped paragraph is
  // captured in full, up to the next blank line.
  const re = /(?:^|\n)\*\*Who it['’]?s for:\*\*\s*([\s\S]*?)(?=\n[ \t]*\n|$)/;
  const m = body.match(re);
  if (!m) return { whoFor: undefined, rest: body };
  return {
    whoFor: m[1].replace(/\s+/g, ' ').trim(),
    rest: body.replace(re, '').replace(/\n{3,}/g, '\n\n').trim(),
  };
}

function stripMd(text) {
  return text
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/[*_`]+/g, '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/^\s*[>#|-]+\s*/gm, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function firstSentence(text, max = 210) {
  let t = stripMd(text);
  const re = /([.!?])\s+(?=[A-Z"'(])/g;
  let m;
  while ((m = re.exec(t))) {
    const before = t.slice(0, m.index + 1);
    if (/(?:\bU\.S|\be\.g|\bi\.e|\bvs|\betc|\bInc|\bNo|\bSt)\.$/i.test(before)) continue;
    t = before;
    break;
  }
  if (t.length > max) {
    t = t.slice(0, max);
    t = t.slice(0, t.lastIndexOf(' ')).replace(/[,;:(\-\s]+$/, '') + '…';
  }
  return t;
}

// Table of contents for the story, matching the ids rehype-slug will assign.
function buildToc(markdown) {
  const slugger = new GithubSlugger();
  const toc = [];
  let inFence = false;
  let fenceChar = '';
  for (const line of markdown.split('\n')) {
    const f = line.match(/^\s*(```+|~~~+)/);
    if (f) {
      if (!inFence) {
        inFence = true;
        fenceChar = f[1][0];
      } else if (line.trim().startsWith(fenceChar)) {
        inFence = false;
      }
      continue;
    }
    if (inFence) continue;
    const m = line.match(/^(#{2,6})\s+(.*\S)\s*$/);
    if (!m) continue;
    const text = m[2].trim();
    const id = slugger.slug(text);
    if (m[1].length === 2) toc.push({ id, text });
  }
  return toc;
}

function detectFromList(text, list) {
  return list.filter(([, re]) => re.test(text)).map(([label]) => label);
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
    const lang = LANG_BY_EXT[path.extname(file).toLowerCase()] ?? 'text';
    const code = (await readMaybe(file)) ?? '';
    scripts.push({ path: rel, lang, code: code.replace(/\s+$/, '') });
  }
  return scripts;
}

// ------------------------------------------------------------- story layout

function buildStory(byNum, preamble) {
  const parts = [];
  let whoFor;

  if (byNum[1]) {
    const r = extractWhoFor(byNum[1].body);
    whoFor = r.whoFor;
    parts.push(`## The short version\n\n${preamble ? preamble + '\n\n' : ''}${r.rest}`);
  }
  if (byNum[2]) parts.push(`## Why this matters\n\n${byNum[2].body}`);
  if (byNum[4]) parts.push(`## How the control works\n\n${byNum[4].body}`);
  if (byNum[3] || byNum[10]) {
    const inner = [];
    if (byNum[3]) inner.push(`### Prerequisites\n\n${demoteHeadings(byNum[3].body)}`);
    if (byNum[10]) inner.push(`### Cost and licensing\n\n${demoteHeadings(byNum[10].body)}`);
    parts.push(`## What it takes\n\n${inner.join('\n\n')}`);
  }
  if (byNum[7]) parts.push(`## Proof it works\n\n${byNum[7].body}`);
  if (byNum[11]) parts.push(`## Where it stops\n\n${byNum[11].body}`);
  return { markdown: parts.join('\n\n'), whoFor };
}

const RUNBOOK_TITLES = {
  5: 'Implementation steps',
  6: 'Configuration reference',
  8: 'Operations and tuning',
  9: 'Rollback and decommission',
  12: 'References',
};

function buildRunbook(byNum, extras) {
  const parts = [];
  for (const n of [5, 6, 8, 9, 12]) {
    if (byNum[n]) parts.push(`## ${RUNBOOK_TITLES[n]}\n\n${byNum[n].body}`);
  }
  for (const e of extras) parts.push(`## ${e.title}\n\n${e.body}`);
  return parts.join('\n\n');
}

const STORY_NUMS = new Set([1, 2, 3, 4, 7, 10, 11]);
const RUNBOOK_NUMS = new Set([5, 6, 8, 9, 12]);

// ---------------------------------------------------------------- reference docs

function dropSections(markdown, titleRe) {
  const lines = markdown.split('\n');
  const out = [];
  let skipping = false;
  for (const line of lines) {
    const h = line.match(/^##\s+(.*?)\s*$/);
    if (h) skipping = titleRe.test(h[1]);
    if (!skipping) out.push(line);
  }
  return out.join('\n');
}

async function buildRefDocs() {
  await fs.rm(refdocsOut, { recursive: true, force: true });
  await fs.mkdir(refdocsOut, { recursive: true });

  const prepared = {};
  for (const name of Object.keys(REF_DOCS)) {
    const raw = await readMaybe(path.join(docsRoot, `${name}.md`));
    if (raw === null) continue;
    // Contributor instructions ("how scenarios should cite ...") are not reader content.
    const body = dropSections(stripFirstH1(raw), /^(?:\d+\.\s*)?How scenarios should cite/i);
    prepared[name] = { raw, body };
    const slugger = new GithubSlugger();
    const map = {};
    for (const line of body.split('\n')) {
      const m = line.match(/^(#{2,6})\s+(.*\S)\s*$/);
      if (!m) continue;
      const text = cleanDashes(m[2].trim());
      const id = slugger.slug(text);
      const num = text.match(/^(\d+)\./);
      if (m[1].length === 2 && num) map[num[1]] = id;
    }
    ctxData.docSections[name] = map;
  }

  const written = [];
  for (const [name, friendly] of Object.entries(REF_DOCS)) {
    if (!prepared[name]) continue;
    const title = cleanDashes(extractTitle(prepared[name].raw, friendly));
    await fs.writeFile(
      path.join(refdocsOut, `${name}.md`),
      frontmatter({ title, name: friendly }) + cleanContent(prepared[name].body, 'doc', `doc:${name}`),
      'utf8'
    );
    written.push(name);
  }
  return written;
}

// ------------------------------------------------------------------- main

async function main() {
  if (!(await isDir(scenariosRoot))) {
    console.log(
      `sync-scenarios: source ${scenariosRoot} not found, keeping committed content, nothing to sync`
    );
    return;
  }

  const themes = JSON.parse(await fs.readFile(path.join(siteRoot, 'src', 'data', 'themes.json'), 'utf8'));
  const themeByArea = {};
  for (const t of themes) for (const a of t.areas) themeByArea[a] = t.slug;

  const categories = (await fs.readdir(scenariosRoot, { withFileTypes: true }))
    .filter((d) => d.isDirectory())
    .map((d) => d.name)
    .sort();

  // Pass 1: titles and slugs for cross-references.
  const slugCount = {};
  for (const category of categories) {
    const catDir = path.join(scenariosRoot, category);
    const slugs = (await fs.readdir(catDir, { withFileTypes: true })).filter((d) => d.isDirectory()).map((d) => d.name);
    for (const slug of slugs) {
      const readme = await readMaybe(path.join(catDir, slug, 'README.md'));
      if (readme === null) continue;
      const { short } = splitCategory(extractTitle(readme, humanizeSlug(slug)), prettyCategory(category));
      ctxData.titleById[`${category}/${slug}`] = cleanDashes(short);
      ctxData.areaLabel[category] = ctxData.areaLabel[category] ?? splitCategory(extractTitle(readme, ''), prettyCategory(category)).category;
      slugCount[slug] = (slugCount[slug] || 0) + 1;
      ctxData.idBySlug[slug] = `${category}/${slug}`;
    }
  }
  for (const [slug, n] of Object.entries(slugCount)) if (n > 1) delete ctxData.idBySlug[slug];

  const refDocsWritten = await buildRefDocs();

  await fs.rm(outRoot, { recursive: true, force: true });
  await fs.mkdir(outRoot, { recursive: true });
  await fs.rm(dataRoot, { recursive: true, force: true });
  await fs.mkdir(dataRoot, { recursive: true });

  let count = 0;
  const problems = [];
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

      const rawTitle = extractTitle(readme, humanizeSlug(slug));
      const { category: catLabel, short } = splitCategory(rawTitle, prettyCategory(category));

      const { preamble, sections } = splitSections(stripFirstH1(readme));
      const byNum = {};
      const extras = [];
      for (const s of sections) {
        if (s.num && !byNum[s.num]) byNum[s.num] = s;
        else extras.push(s);
      }
      // Every section must land in exactly one place; nothing may be dropped.
      const known = sections.filter((s) => s.num && (STORY_NUMS.has(s.num) || RUNBOOK_NUMS.has(s.num)));
      const unknownNumbered = sections.filter((s) => s.num && !STORY_NUMS.has(s.num) && !RUNBOOK_NUMS.has(s.num));
      const runbookExtras = [...extras, ...unknownNumbered];
      if (known.length + runbookExtras.length !== sections.length) problems.push(`${id}: section accounting mismatch`);

      const story = buildStory(byNum, preamble);
      const runbook = buildRunbook(byNum, runbookExtras);

      const storyMd = cleanContent(story.markdown, 'scenario', id);
      const runbookMd = cleanContent(runbook, 'scenario', id);
      const whoFor = story.whoFor ? cap(cleanDashes(normalizeProse(story.whoFor, 'scenario', id))) : undefined;
      const teaser = firstSentence(cleanDashes(normalizeProse(stripFirstParagraph(byNum[1]?.body ?? ''), 'scenario', id)));
      const words = storyMd.split(/\s+/).length;

      const frameworks = detectFromList(readme, FRAMEWORKS);
      const licensing = detectFromList(byNum[10]?.body || readme, LICENSES);

      const deploy = await collectScripts(path.join(dir, 'deploy'));
      const validate = await collectScripts(path.join(dir, 'validate'));
      const designRaw = await readMaybe(path.join(dir, 'design.md'));
      const rollbackRaw = await readMaybe(path.join(dir, 'rollback.md'));

      const outDir = path.join(outRoot, category);
      await fs.mkdir(outDir, { recursive: true });

      if (designRaw) {
        await fs.writeFile(
          path.join(outDir, `${slug}.design.md`),
          frontmatter({ part: 'design', parent: id }) + cleanContent(stripFirstH1(designRaw), 'scenario', id),
          'utf8'
        );
      }
      if (rollbackRaw) {
        await fs.writeFile(
          path.join(outDir, `${slug}.rollback.md`),
          frontmatter({ part: 'rollback', parent: id }) + cleanContent(stripFirstH1(rollbackRaw), 'scenario', id),
          'utf8'
        );
      }
      if (runbookMd.trim()) {
        await fs.writeFile(
          path.join(outDir, `${slug}.runbook.md`),
          frontmatter({ part: 'runbook', parent: id }) + runbookMd,
          'utf8'
        );
      }
      if (deploy.length || validate.length) {
        const dataDir = path.join(dataRoot, category);
        await fs.mkdir(dataDir, { recursive: true });
        await fs.writeFile(path.join(dataDir, `${slug}.json`), JSON.stringify({ deploy, validate }), 'utf8');
      }

      await fs.writeFile(
        path.join(outDir, `${slug}.md`),
        frontmatter({
          title: cleanDashes(short),
          category: catLabel,
          categorySlug: category,
          theme: themeByArea[category] ?? 'more',
          slug,
          teaser,
          readingMinutes: Math.max(1, Math.round(words / 210)),
          whoFor,
          frameworks,
          licensing,
          deployCount: deploy.length,
          validateCount: validate.length,
          hasDesign: Boolean(designRaw),
          hasRollback: Boolean(rollbackRaw),
          hasRunbook: Boolean(runbookMd.trim()),
          toc: buildToc(storyMd),
        }) + storyMd,
        'utf8'
      );
      count += 1;
    }
  }

  console.log(`sync-scenarios: wrote ${count} field notes and ${refDocsWritten.length} reference docs`);
  if (process.env.DEBUG_SAMPLES) {
    let seed = 7;
    const rnd = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff);
    const picks = [...debugPairs].sort(() => rnd() - 0.5).slice(0, Number(process.env.DEBUG_SAMPLES));
    for (const p of picks) console.log(`\n[${p.id}]\n  BEFORE: ${p.before}\n  AFTER : ${p.after}`);
  }
  if (problems.length) {
    console.error('sync-scenarios: PROBLEMS\n' + problems.join('\n'));
    process.exit(2);
  }
}

// The teaser comes from the first paragraph of the summary, before "Who it's for".
function stripFirstParagraph(body) {
  const first = body.split(/\n[ \t]*\n/)[0] || '';
  return first;
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
