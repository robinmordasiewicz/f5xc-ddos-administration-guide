import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://robinmordasiewicz.github.io',
  base: '/f5xc-ddos-administration-guide',
  integrations: [
    starlight({
      title: 'F5 XC DDoS Administration Guide',
      social: {
        github: 'https://github.com/robinmordasiewicz/f5xc-ddos-administration-guide',
      },
      sidebar: [
        {
          label: 'Guide',
          autogenerate: { directory: 'guide' },
        },
      ],
    }),
  ],
});
