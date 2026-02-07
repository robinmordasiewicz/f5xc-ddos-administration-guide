import { loadValues, getAllValues } from '../lib/placeholder-store';

const PH_REGEX = /x([A-Z][A-Z0-9_]+)x/g;

function substituteText(text: string, values: Record<string, string>): string {
  return text.replace(PH_REGEX, (match, name) => {
    return values[name] !== undefined ? values[name] : match;
  });
}

function walkTextNodes(root: Node, values: Record<string, string>) {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const nodes: Text[] = [];
  let node: Node | null;
  while ((node = walker.nextNode())) {
    if (node.nodeType === Node.TEXT_NODE && PH_REGEX.test(node.textContent || '')) {
      nodes.push(node as Text);
    }
    PH_REGEX.lastIndex = 0;
  }
  for (const textNode of nodes) {
    const original = textNode.textContent || '';
    const parent = textNode.parentNode;
    if (!parent) continue;

    const fragment = document.createDocumentFragment();
    let lastIndex = 0;
    let m: RegExpExecArray | null;
    PH_REGEX.lastIndex = 0;
    while ((m = PH_REGEX.exec(original)) !== null) {
      if (m.index > lastIndex) {
        fragment.appendChild(document.createTextNode(original.slice(lastIndex, m.index)));
      }
      const span = document.createElement('span');
      span.setAttribute('data-ph', m[1]);
      span.className = 'ph-value';
      span.textContent = values[m[1]] !== undefined ? values[m[1]] : m[0];
      fragment.appendChild(span);
      lastIndex = PH_REGEX.lastIndex;
    }
    if (lastIndex < original.length) {
      fragment.appendChild(document.createTextNode(original.slice(lastIndex)));
    }
    parent.replaceChild(fragment, textNode);
  }
}

function updateSpans(values: Record<string, string>) {
  document.querySelectorAll<HTMLSpanElement>('span[data-ph]').forEach((span) => {
    const name = span.getAttribute('data-ph')!;
    if (values[name] !== undefined) {
      span.textContent = values[name];
    }
  });
}

async function renderMermaidDiagrams(values: Record<string, string>) {
  const containers = document.querySelectorAll<HTMLElement>('.mermaid-container');
  if (containers.length === 0) return;

  const mermaid = (await import('https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs')).default;
  mermaid.initialize({
    startOnLoad: false,
    theme: 'default',
    securityLevel: 'loose',
    themeVariables: {
      primaryColor: '#ffffff',
      primaryBorderColor: '#cccccc',
      background: '#ffffff',
      mainBkg: '#ffffff',
      secondBkg: '#ffffff',
      tertiaryColor: '#ffffff',
    },
  });

  for (const container of containers) {
    const template = container.getAttribute('data-mermaid-src') || '';
    const substituted = substituteText(template, values);
    container.removeAttribute('data-processed');
    container.innerHTML = '';
    try {
      const { svg } = await mermaid.render(`mermaid-${Math.random().toString(36).slice(2)}`, substituted);
      container.innerHTML = svg;

      // Force white background on the rendered SVG
      const svgElement = container.querySelector('svg');
      if (svgElement) {
        svgElement.style.backgroundColor = 'white';
      }
    } catch (e) {
      container.textContent = `Diagram error: ${e}`;
    }
  }
}

function handleChange(e: Event) {
  const values = (e as CustomEvent).detail as Record<string, string>;
  updateSpans(values);
  renderMermaidDiagrams(values);
}

function init() {
  const values = getAllValues(loadValues());
  const content = document.querySelector('.sl-markdown-content') || document.body;
  walkTextNodes(content, values);
  renderMermaidDiagrams(values);
}

document.addEventListener('placeholder-change', handleChange);

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}

document.addEventListener('astro:page-load', init);
