import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['favicon.ico', 'apple-touch-icon.png', 'mask-icon.svg'],
      manifest: {
        name: 'Chatterbox - Your Voice Companion',
        short_name: 'Chatterbox',
        description: 'Practice speaking any language with confidence',
        theme_color: '#F5E6D3',
        background_color: '#F5E6D3',
        display: 'standalone',
        orientation: 'portrait',
        scope: '/',
        start_url: '/',
        icons: [
          {
            src: 'https://storage.googleapis.com/chatterbox-public-assets/public-chatterbox-logo-color-bg.png',
            sizes: '192x192',
            type: 'image/png',
            purpose: 'any maskable'
          },
          {
            src: 'https://storage.googleapis.com/chatterbox-public-assets/public-chatterbox-logo-color-bg.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'any maskable'
          }
        ]
      },
      workbox: {
        // Cache static assets
        globPatterns: ['**/*.{js,css,html,ico,png,svg,woff2}'],
        // Don't cache API calls - we want fresh data
        navigateFallback: null,
        runtimeCaching: [
          {
            urlPattern: /^https:\/\/storage\.googleapis\.com\/.*/i,
            handler: 'CacheFirst',
            options: {
              cacheName: 'external-images',
              expiration: {
                maxEntries: 50,
                maxAgeSeconds: 60 * 60 * 24 * 30, // 30 days
              },
            },
          },
        ],
      },
    }),
  ],
  server: {
    host: '0.0.0.0',
    port: 5173,
    allowedHosts: ['chatterboxtalk.com'],
    proxy: {
      '/api': {
        target: 'http://gateway:8080',
        changeOrigin: true,
      },
    },
  },
})

