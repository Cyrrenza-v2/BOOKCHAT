import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  base: './',
  plugins: [react()],
  build: {
    outDir: 'dist',
    sourcemap: false,
    rollupOptions: {
      input: {
        root: 'index.html',
        user: 'user/index.html',
        admin: 'admin/index.html'
      }
    }
  }
});
