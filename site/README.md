# kpsec1.github.io

Personal site for **Krunal** — Cyber Security Consultant (Regina, Saskatchewan).
Built with [Astro](https://astro.build/) and deployed to GitHub Pages.

The only content published here is the **Purview Scenario Library**: 108 end-to-end
Microsoft Purview scenarios, sourced from
[`kpsec1/purview-scenario-library`](https://github.com/kpsec1/purview-scenario-library).

## Structure

- `src/pages/index.astro` — bio landing page (name, role, location, focus areas).
- `src/pages/scenarios/` — library index and per-scenario pages.
- `src/content/scenarios/` — generated scenario content (one Markdown file per
  scenario, committed so the site builds without the source repo present).
- `scripts/sync-scenarios.mjs` — regenerates `src/content/scenarios/` from a local
  checkout of `purview-scenario-library` sitting next to this repo.

## Develop

```sh
npm install
npm run dev      # http://localhost:4321
npm run build    # runs the content sync (if source is available) then astro build
```

## Updating scenario content

Regenerate the committed content from the source repo, then commit the result:

```sh
# with purview-scenario-library checked out as a sibling of this repo
npm run sync-content
git add src/content/scenarios && git commit -m "Refresh scenario content"
```

If the source repo is not present, the sync step is skipped and the committed
content is used as-is.

## Deploy

Pushing to `main` triggers `.github/workflows/deploy.yml`, which builds with
`withastro/action` and publishes via `actions/deploy-pages`. Pages must be
configured with the **GitHub Actions** source (Settings → Pages).
