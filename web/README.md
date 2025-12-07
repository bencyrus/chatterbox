# Chatterbox Marketing Website

Barebones React + Vite + Tailwind website.

## Stack

- React 19.0
- Vite 6.0
- Tailwind CSS 3.4
- React Router

## Pages

- `/` - Hello World
- `/privacy` - Privacy Policy

## Development

### Local

```bash
cd web
npm install
npm run dev
```

Site runs at `http://localhost:5173`

### Docker

```bash
docker-compose up web
```

Access at:
- Direct: `http://localhost:5173`
- Through Caddy: `https://chatterboxtalk.com`

## Structure

```
web/
├── src/
│   ├── pages/
│   │   ├── HomePage.jsx
│   │   └── PrivacyPage.jsx
│   ├── App.jsx
│   ├── main.jsx
│   └── index.css
├── public/
├── index.html
├── vite.config.js
├── tailwind.config.js
├── postcss.config.js
├── package.json
└── Dockerfile
```

## Routing

Caddy at `chatterboxtalk.com` routes to this site, preserving:
- `/.well-known/apple-app-site-association`
- `/apple-app-site-association`
- `/.well-known/assetlinks.json`
