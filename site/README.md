# kpsec1.github.io

Field notes on Microsoft Purview and security by **Krunal**, Cyber Security Consultant
(Regina, Saskatchewan). Built with [Astro](https://astro.build/) and deployed to GitHub Pages.

Each scenario in the source library is published as a **field note**: a short story
(what the risk is, why it matters, how the control works, what it takes, proof it works,
where it stops) followed by a collapsed **Runbook** for engineers (steps, configuration,
scripts, design notes, rollback).

## Structure

- `src/pages/index.astro`: the home page (hero, featured stories, reading paths, themes, bio).
- `src/pages/scenarios/`: the Field Notes library and the field note page.
- `src/pages/docs/`: the Field Guide (licensing, roles, automation, glossary).
- `src/content/`: generated Markdown (committed, so the site builds without the source repo).
- `src/data/`: `themes.json` (story groupings), `areas.json` (area names), `tracks.json`
  (reading paths), `flagship.json` (hand-written openings), and generated `scenario-scripts/`.
- `scripts/sync-scenarios.mjs`: regenerates `src/content` and `src/data/scenario-scripts`
  from a local checkout of `purview-scenario-library` placed next to this repo.

## Develop

```sh
npm install
npm run dev      # http://localhost:4321
npm run build    # syncs content when the source repo is present, then builds
```

## Refreshing content

```sh
# with purview-scenario-library checked out as a sibling of this repo
npm run sync-content
git add src && git commit -m "Refresh field notes"
```

The sync turns repository-style pointers in the source ("see design.md section 4",
`scenarios/x/y/`) into plain wording, removes long dashes, repairs Mermaid diagram syntax,
and splits each README into the story and the runbook. `DEBUG_SAMPLES=20 npm run sync-content`
prints a random sample of before and after edits for review.

## Flagship openings

`src/data/flagship.json` holds hand-written openings for six featured notes. They are drafts:
nothing shows on the live site until `published` is set to `true` (globally, or per post).
`SHOW_FLAGSHIP_DRAFTS=1 npm run build` previews them locally.

## Deploy

Pushing to `main` runs `.github/workflows/deploy.yml`, which builds with `withastro/action`
and publishes with `actions/deploy-pages`. Pages must use the **GitHub Actions** source.
