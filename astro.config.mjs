import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import remarkMermaid from './src/plugins/remark-mermaid.mjs';

export default defineConfig({
  site: 'https://robinmordasiewicz.github.io',
  base: '/f5xc-ddos-administration-guide',
  markdown: {
    remarkPlugins: [remarkMermaid],
  },
  integrations: [
    starlight({
      title: 'F5 XC DDoS Administration Guide',
      logo: {
        src: './src/assets/f5-logo.svg',
      },
      social: [
        {
          label: 'GitHub',
          icon: 'github',
          href: 'https://github.com/robinmordasiewicz/f5xc-ddos-administration-guide',
        },
      ],
      sidebar: [
        {
          label: 'BIG-IP GRE/BGP Guide',
          autogenerate: { directory: 'guide' },
        },
      ],
    }),
  ],
});
