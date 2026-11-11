import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Relativer Base: läuft lokal, unter http.server und auf GitHub Pages
// (Projektseite /FygoOS-Proxmox/) ohne Anpassung.
export default defineConfig({
  base: './',
  plugins: [react()],
})
