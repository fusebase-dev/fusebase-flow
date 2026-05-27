---
name: app-routing
description: "Guide for implementing client-side routing in Fusebase Apps apps. Use when: 1. Adding routing (React Router) to an app, 2. Fixing broken routes or 404s after deployment, 3. Configuring the router."
---

# App Routing

Fusebase Apps apps are each served from their own **subdomain root**:

```
https://{app-subdomain}.{FUSEBASE_APP_HOST}/
```

Read `FUSEBASE_APP_HOST` from the project `.env` when constructing app URLs. The app always owns the full path space from `/`.

> **IMPORTANT: Always use path-based routing (`BrowserRouter`). Hash-based routing (`HashRouter`) is forbidden** — hash fragments are stripped during redirects (e.g. OAuth, SSO), causing users to lose their navigation state.

## Path-Based Routing

Routes work as normal from root:

```
https://my-app.{FUSEBASE_APP_HOST}/settings
https://my-app.{FUSEBASE_APP_HOST}/users/42
```

### Configure the router

```tsx
import { BrowserRouter, Routes, Route } from 'react-router-dom'

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Home />} />
        <Route path="/settings" element={<Settings />} />
      </Routes>
    </BrowserRouter>
  )
}
```

## Common Pitfalls

1. **Using `HashRouter`** — Forbidden. Hash fragments are dropped on redirects, breaking navigation after OAuth or SSO flows.
2. **Hardcoded absolute paths** — Use React Router's `<Link>` component, not raw `<a href="/settings">`.
3. **Defining routes under `/api`** — The `/api` prefix is reserved for the backend when an app has one. Never create SPA routes under `/api/*`. See skill **app-backend**.