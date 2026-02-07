import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import react from '@astrojs/react';
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
      customCss: [
        './src/fonts/font-face.css',
        './src/styles/custom.css',
      ],
      logo: {
        src: './src/assets/f5-logo.svg',
      },
      components: {
        Footer: './src/components/Footer.astro',
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
    react(),
  ],
});
