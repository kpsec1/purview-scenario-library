import { defineCollection, z } from 'astro:content';
import { glob } from 'astro/loaders';

const scenarios = defineCollection({
  loader: glob({
    pattern: '**/*.md',
    base: './src/content/scenarios',
    generateId: ({ entry }) => entry.replace(/\.md$/, ''),
  }),
  schema: z.object({
    // Overview entries
    title: z.string().optional(),
    category: z.string().optional(),
    categorySlug: z.string().optional(),
    slug: z.string().optional(),
    whoFor: z.string().optional(),
    frameworks: z.array(z.string()).optional(),
    licensing: z.array(z.string()).optional(),
    deployCount: z.number().optional(),
    validateCount: z.number().optional(),
    hasDesign: z.boolean().optional(),
    hasRollback: z.boolean().optional(),
    toc: z.array(z.object({ id: z.string(), text: z.string() })).optional(),
    // Lifecycle-part entries (design / rollback)
    part: z.string().optional(),
    parent: z.string().optional(),
  }),
});

export const collections = { scenarios };
