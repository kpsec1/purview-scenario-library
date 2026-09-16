// @ts-check
import { defineConfig } from 'astro/config';
import { visit } from 'unist-util-visit';

// Convert ```mermaid fenced code blocks into <pre class="mermaid"> elements so
// Mermaid can render them as diagrams in the browser (instead of Astro's syntax
// highlighter turning the flowchart source into a plain code block).
function remarkMermaid() {
  return (/** @type {any} */ tree) => {
    visit(tree, 'code', (node, index, parent) => {
      if (!parent || index === null || node.lang !== 'mermaid') return;
      const escaped = node.value
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
      parent.children[index] = {
        type: 'html',
        value: `<pre class="mermaid" role="img" aria-label="Flowchart diagram">${escaped}</pre>`,
      };
    });
  };
}

// https://astro.build/config
export default defineConfig({
  site: 'https://kpsec1.github.io',
  markdown: {
    remarkPlugins: [remarkMermaid],
    shikiConfig: {
      theme: 'github-light',
      wrap: true,
    },
  },
});
