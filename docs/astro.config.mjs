import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://wm.garcez.dev",
  redirects: { "/docs": "/docs/overview" },
  markdown: {
    shikiConfig: {
      themes: { light: "vitesse-light", dark: "vitesse-dark" },
      defaultColor: false,
    },
  },
});
