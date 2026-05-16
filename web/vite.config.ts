import path from 'node:path';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

const dbFirstDocsRoot = path.resolve(__dirname, '../docs/database-first');

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@db-first-docs': dbFirstDocsRoot,
    },
  },
  server: {
    host: '0.0.0.0',
    port: 5173,
    allowedHosts: ['chatterboxtalk.com'],
    fs: {
      allow: [path.resolve(__dirname, '..'), dbFirstDocsRoot],
    },
    proxy: {
      '/api': {
        target: 'http://gateway:8080',
        changeOrigin: true,
      },
    },
  },
});
