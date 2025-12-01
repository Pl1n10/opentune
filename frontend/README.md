# OpenTune Web UI

Modern web interface for the OpenTune (dsc-cp) GitOps control plane.

## Tech Stack

- **React 18** - UI framework
- **Vite** - Build tool
- **Tailwind CSS** - Styling
- **React Router** - Client-side routing
- **Recharts** - Charts
- **Lucide React** - Icons

## Development

```bash
# Install dependencies
npm install

# Start dev server (with API proxy to localhost:8000)
npm run dev

# Build for production
npm run build

# Preview production build
npm run preview
```

## Project Structure

```
frontend/
├── public/              # Static assets
├── src/
│   ├── api/             # API client
│   ├── components/      # Reusable UI components
│   ├── context/         # React contexts (auth)
│   ├── hooks/           # Custom hooks
│   ├── pages/           # Page components
│   ├── App.jsx          # Main app with routing
│   ├── main.jsx         # Entry point
│   └── index.css        # Global styles (Tailwind)
├── index.html           # HTML template
├── package.json
├── vite.config.js
├── tailwind.config.js
└── postcss.config.js
```

## Features

### Dashboard
- Node status overview (success/failed/unknown)
- Pie chart visualization
- Recent runs list
- Quick links to resources

### Nodes
- List all registered nodes
- Create new nodes (with one-time token display)
- View node details and run history
- Assign/unassign policies
- Regenerate tokens
- Delete nodes

### Policies
- List all policies
- Create/edit policies
- Link to Git repositories
- Specify branch and config path
- Delete policies

### Repositories
- List Git repositories
- Add/edit repositories
- Configure URL and default branch
- Delete repositories (if no policies reference them)

## Authentication

The UI uses the same `X-Admin-API-Key` header as the API. The key is:

1. Entered on the login page
2. Stored in `localStorage`
3. Sent with every API request
4. Can be cleared by clicking "Disconnect" in the sidebar

## Deployment

The production build (`npm run build`) creates a `dist/` folder that can be:

1. **Served by FastAPI** (recommended) - The backend automatically serves files from `frontend/dist/`
2. **Served by nginx/caddy** - Point to the `dist/` folder
3. **Deployed to CDN** - Upload to Cloudflare Pages, Vercel, etc.

For option 1, just run `npm run build` and restart the backend.
