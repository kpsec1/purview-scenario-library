import { defineCollection, z } from 'astro:content';
import { glob } from 'astro/loaders';

const scenarios = defineCollection({
  loader: glob({
    pattern: '**/*.md',
    base: './src/content/scenarios',
    // Preserve the "<category>/<slug>" (and "<category>/<slug>.<part>") path as
    // the entry id so routes are /scenarios/<category>/<slug>/ and lifecycle
    // parts can be looked up by id.
    generateId: ({ entry }) => entry.replace(/\.md$/, ''),
  }),
  schema: z.object({
    // Overview entries
    title: z.string().optional(),
    fullTitle: z.string().optional(),
    category: z.string().optional(),
    categorySlug: z.string().optional(),
    slug: z.string().optional(),
    repoPath: z.string().optional(),
    parts: z.array(z.string()).optional(),
    related: z.array(z.string()).optional(),
    deployCount: z.number().optional(),
    validateCount: z.number().optional(),
    // Lifecycle-part entries (design / deploy / validate / rollback)
    part: z.string().optional(),
    parent: z.string().optional(),
  }),
});

export const collections = { scenarios };
