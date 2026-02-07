import { visit } from 'unist-util-visit';

/**
 * Remark plugin that converts ```mermaid code blocks into
 * <div class="mermaid-container"> elements for client-side rendering.
 * The raw diagram source is stored in a data-mermaid-src attribute.
 */
export default function remarkMermaid() {
  return (tree) => {
    visit(tree, 'code', (node, index, parent) => {
      if (node.lang !== 'mermaid' || index === undefined || !parent) return;

      const escaped = node.value
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');

      parent.children[index] = {
        type: 'html',
        value: `<div class="mermaid-container" data-mermaid-src="${escaped}"><pre class="mermaid">${node.value}</pre></div>`,
      };
    });
  };
}
