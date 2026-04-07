import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

let httpsPlugin = null
try {
  const { default: basicSsl } = await import('@vitejs/plugin-basic-ssl')
  httpsPlugin = basicSsl()
} catch {
  // package not yet installed — run: npm install -D @vitejs/plugin-basic-ssl
}

export default defineConfig({
  plugins: [react(), httpsPlugin].filter(Boolean),
  server: {
    https: !!httpsPlugin,
    host: true,
  },
})
