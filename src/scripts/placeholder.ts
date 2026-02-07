import placeholderDefs from '../data/placeholders.json';

const STORAGE_KEY = 'f5xc-placeholders';
const PH_REGEX = /x([A-Z][A-Z0-9_]+)x/g;

const cidrToMask: Record<string, string> = {
  '/24 (256 IPs)': '255.255.255.0',
  '/23 (512 IPs)': '255.255.254.0',
  '/22 (1024 IPs)': '255.255.252.0',
  '/21 (2048 IPs)': '255.255.248.0',
};

const cidrToShort: Record<string, string> = {
  '/24 (256 IPs)': '/24',
  '/23 (512 IPs)': '/23',
  '/22 (1024 IPs)': '/22',
  '/21 (2048 IPs)': '/21',
};

function loadValues(): Record<string, string> {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored) return JSON.parse(stored);
  } catch { /* ignore */ }
  const defaults: Record<string, string> = {};
  for (const [key, def] of Object.entries(placeholderDefs)) {
    defaults[key] = (def as { default: string }).default;
  }
  return defaults;
}

function saveValues(values: Record<string, string>) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(values));
}

function getComputedValues(values: Record<string, string>): Record<string, string> {
  const cidr = values['PROTECTED_CIDR_V4'] || '/24 (256 IPs)';
  const mask = cidrToMask[cidr] || '255.255.255.0';
  const short = cidrToShort[cidr] || '/24';
  const net = values['PROTECTED_NET_V4'] || '192.0.2.0';
  return {
    ...values,
    'PROTECTED_MASK_V4': mask,
    'PROTECTED_PREFIX_V4': `${net}${short}`,
    'PROTECTED_CIDR_V4': cidr,
  };
}

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
  mermaid.initialize({ startOnLoad: false, theme: 'default', securityLevel: 'loose' });

  for (const container of containers) {
    const template = container.getAttribute('data-mermaid-src') || '';
    const substituted = substituteText(template, values);
    container.removeAttribute('data-processed');
    container.innerHTML = '';
    try {
      const { svg } = await mermaid.render(`mermaid-${Math.random().toString(36).slice(2)}`, substituted);
      container.innerHTML = svg;
    } catch (e) {
      container.textContent = `Diagram error: ${e}`;
    }
  }
}

function bindForm(values: Record<string, string>) {
  const form = document.getElementById('placeholder-form');
  if (!form) return;

  form.addEventListener('input', (e) => {
    const target = e.target as HTMLInputElement | HTMLSelectElement;
    const name = target.name;
    if (!name) return;
    values[name] = target.value;
    const computed = getComputedValues(values);
    saveValues(values);
    updateSpans(computed);
    renderMermaidDiagrams(computed);
  });
}

export function init() {
  const values = loadValues();
  const computed = getComputedValues(values);

  // Set form field values from storage
  const form = document.getElementById('placeholder-form');
  if (form) {
    form.querySelectorAll<HTMLInputElement | HTMLSelectElement>('input, select').forEach((el) => {
      if (el.name && values[el.name] !== undefined) {
        el.value = values[el.name];
      }
    });
  }

  // Walk the main content area to wrap placeholder tokens in spans
  const content = document.querySelector('.sl-markdown-content') || document.body;
  walkTextNodes(content, computed);

  // Render Mermaid diagrams with substituted values
  renderMermaidDiagrams(computed);

  // Bind form change events
  bindForm(values);
}

// Auto-initialize when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}

// Re-init on Astro page navigation (View Transitions)
document.addEventListener('astro:page-load', init);
