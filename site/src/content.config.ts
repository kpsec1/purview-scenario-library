import { defineCollection, z } from 'astro:content';
import { glob } from 'astro/loaders';

const scenarios = defineCollection({
  loader: glob({
    pattern: '**/*.md',
    base: './src/content/scenarios',
    // Preserve the "<category>/<slug>" path as the entry id so routes are
    // /scenarios/<category>/<slug>/ and slugs can never collide across areas.
    generateId: ({ entry }) => entry.replace(/\.md$/, ''),
  }),
  schema: z.object({
    title: z.string(),
    fullTitle: z.string(),
    category: z.string(),
    categorySlug: z.string(),
    slug: z.string(),
    repoPath: z.string(),
  }),
});

export const collections = { scenarios };
