// @ts-check
import { defineConfig } from 'astro/config';
import { visit } from 'unist-util-visit';
import rehypeSlug from 'rehype-slug';

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

// Strip every hyperlink from rendered scenario content EXCEPT links to official
// Microsoft documentation (learn.microsoft.com / docs.microsoft.com). Non-doc
// links (other scenarios, GitHub, regulatory sites, etc.) are unwrapped to plain
// text so the page is script, text, and diagrams only. Code blocks are untouched
// (endpoints in scripts are not anchors).
function rehypeKeepOnlyMsDocLinks() {
  const isMsDoc = (href) =>
    typeof href === 'string' &&
    /^https?:\/\/(learn|docs)\.microsoft\.com\//i.test(href);
  return (/** @type {any} */ tree) => {
    visit(tree, 'element', (node, index, parent) => {
      if (node.tagName !== 'a' || !parent || index === null) return;
      const href = node.properties && node.properties.href;
      if (isMsDoc(href)) {
        node.properties.target = '_blank';
        node.properties.rel = 'noopener noreferrer';
        return;
      }
      // Unwrap: replace the <a> with its text children (drop the link).
      parent.children.splice(index, 1, ...node.children);
      return index;
    });
  };
}

// https://astro.build/config
export default defineConfig({
  site: 'https://kpsec1.github.io',
  markdown: {
    remarkPlugins: [remarkMermaid],
    rehypePlugins: [rehypeSlug, rehypeKeepOnlyMsDocLinks],
    shikiConfig: {
      theme: 'github-light',
      wrap: true,
    },
  },
});
