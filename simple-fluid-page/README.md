# BulletinBoard frontend

This directory contains the React/Vite frontend for the BulletinBoard demo. It renders the message board and calls the API through the `/api` path.

## Development

```sh
npm ci
npm run dev
```

The Vite development server proxies `/api` to `http://localhost:8080`. For a production-style local run, use the repository-level Docker Compose stack instead.

## Build and lint

```sh
npm run lint
npm run build
```
