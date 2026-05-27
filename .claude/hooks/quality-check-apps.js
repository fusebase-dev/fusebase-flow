#!/usr/bin/env node
// Claude Code Stop hook:
// 1. Ensure no app has a non-"/" `base` in vite config.
// 2. Ensure all app directories are registered in fusebase.json.

const fs = require("fs");
const path = require("path");

const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const featuresDir = path.join(projectDir, "apps");
const HTTP_METHODS = ["get", "post", "put", "patch", "delete", "options", "head"];

if (!fs.existsSync(featuresDir)) {
  process.exit(0);
}

const appNames = fs
  .readdirSync(featuresDir, { withFileTypes: true })
  .filter((d) => d.isDirectory())
  .map((d) => d.name);

if (appNames.length === 0) {
  process.exit(0);
}

const errors = [];
const warnings = [];

function normalizeApiPath(pathname) {
  if (!pathname || typeof pathname !== "string") return null;
  const collapsed = pathname.replace(/\/+/g, "/");
  if (collapsed === "/") return "/";
  return collapsed.endsWith("/") ? collapsed.slice(0, -1) : collapsed;
}

function loadBackendOperationSignatures(appDir) {
  const backendSrcDir = path.join(appDir, "backend", "src");
  if (!fs.existsSync(backendSrcDir)) return [];

  const tsFiles = [];
  const stack = [backendSrcDir];
  while (stack.length > 0) {
    const current = stack.pop();
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        stack.push(fullPath);
      } else if (entry.isFile() && fullPath.endsWith(".ts")) {
        tsFiles.push(fullPath);
      }
    }
  }

  const routerMounts = new Map();
  const routeDefs = [];

  for (const filePath of tsFiles) {
    const content = fs.readFileSync(filePath, "utf-8");

    const routeMountRegex =
      /(\w+)\.route\(\s*(['"`])([^'"`]+)\2\s*,\s*(\w+)\s*\)/g;
    for (const match of content.matchAll(routeMountRegex)) {
      const mountPath = normalizeApiPath(match[3]);
      const routerName = match[4];
      if (!mountPath || !routerName) continue;
      const existing = routerMounts.get(routerName) || [];
      existing.push(mountPath);
      routerMounts.set(routerName, existing);
    }

    const routeDefRegex =
      /(\w+)\.(get|post|put|patch|delete|options|head)\(\s*(['"`])([^'"`]+)\3/g;
    for (const match of content.matchAll(routeDefRegex)) {
      routeDefs.push({
        routerName: match[1],
        method: match[2].toUpperCase(),
        routePath: match[4],
      });
    }
  }

  const signatures = new Set();

  for (const routeDef of routeDefs) {
    const localPath = normalizeApiPath(routeDef.routePath);
    if (!localPath) continue;

    if (routeDef.routerName === "app") {
      if (!localPath.startsWith("/webhooks")) {
        signatures.add(`${routeDef.method} ${localPath}`);
      }
      continue;
    }

    const mounts = routerMounts.get(routeDef.routerName) || [];
    for (const mountPath of mounts) {
      const combined =
        localPath === "/"
          ? mountPath
          : normalizeApiPath(`${mountPath}/${localPath.replace(/^\//, "")}`);
      if (!combined || combined.startsWith("/webhooks")) continue;
      signatures.add(`${routeDef.method} ${combined}`);
    }
  }

  return [...signatures].sort();
}

function loadOpenApiOperationSignatures(appDir) {
  const openApiPath = path.join(appDir, "openapi.json");
  if (!fs.existsSync(openApiPath)) return [];

  try {
    const document = JSON.parse(fs.readFileSync(openApiPath, "utf-8"));
    const paths = document?.paths;
    if (!paths || typeof paths !== "object") return [];

    const signatures = [];
    for (const [rawPath, pathItem] of Object.entries(paths)) {
      const normalizedPath = normalizeApiPath(rawPath);
      if (!normalizedPath || !pathItem || typeof pathItem !== "object") continue;
      for (const method of HTTP_METHODS) {
        if (pathItem[method]) {
          signatures.push(`${method.toUpperCase()} ${normalizedPath}`);
        }
      }
    }

    return signatures.sort();
  } catch {
    return [];
  }
}

// --- Check 1: Vite base config ---
for (const name of appNames) {
  const fullPath = path.join(featuresDir, name);
  let viteConfigPath = null;

  if (fs.existsSync(path.join(fullPath, "vite.config.ts"))) {
    viteConfigPath = path.join(fullPath, "vite.config.ts");
  } else if (fs.existsSync(path.join(fullPath, "vite.config.js"))) {
    viteConfigPath = path.join(fullPath, "vite.config.js");
  } else {
    continue;
  }

  const content = fs.readFileSync(viteConfigPath, "utf-8");

  // Match base: "/value" or base: '/value' (with optional trailing comma)
  const match = content.match(/^\s*base\s*:\s*(['"])([^'"]*)\1/m);

  if (!match) {
    // base is not set — that's fine
    continue;
  }

  const baseValue = match[2];
  if (baseValue !== "/") {
    errors.push(
      `App "${name}": vite config base is set to "${baseValue}" — this is not allowed. base must be "/" or not set at all.`
    );
  }
}

// --- Soft check 3: backend routes should stay in sync with openapi.json ---
for (const name of appNames) {
  const appDir = path.join(featuresDir, name);
  const backendDir = path.join(appDir, "backend");
  const openApiPath = path.join(appDir, "openapi.json");

  if (!fs.existsSync(backendDir) || !fs.existsSync(openApiPath)) {
    continue;
  }

  const backendOps = loadBackendOperationSignatures(appDir);
  const openApiOps = loadOpenApiOperationSignatures(appDir);
  if (backendOps.length === 0 || openApiOps.length === 0) {
    continue;
  }

  const openApiSet = new Set(openApiOps);
  const backendSet = new Set(backendOps);

  const missingInOpenApi = backendOps.filter((op) => !openApiSet.has(op));
  const missingInBackend = openApiOps.filter(
    (op) => !backendSet.has(op) && !op.endsWith(" /health"),
  );

  if (missingInOpenApi.length === 0 && missingInBackend.length === 0) {
    continue;
  }

  const lines = [
    `App "${name}": backend route surface and openapi.json appear to be out of sync.`,
    `This check is heuristic-only, but you should review app-root openapi.json before deploy.`,
  ];

  if (missingInOpenApi.length > 0) {
    lines.push(
      "Routes found in backend but not in openapi.json:\n" +
        missingInOpenApi.map((op) => `  - ${op}`).join("\n"),
    );
  }

  if (missingInBackend.length > 0) {
    lines.push(
      "Operations found in openapi.json but not inferred from backend routes:\n" +
        missingInBackend.map((op) => `  - ${op}`).join("\n"),
    );
  }

  lines.push(
    'Run "fusebase api validate" and check deploy output for "Published OpenAPI registry: N operation(s) from openapi.json".',
  );
  warnings.push(lines.join("\n\n"));
}

// --- Check 2: Apps must be registered in fusebase.json ---
const fusebasePath = path.join(projectDir, "fusebase.json");
if (fs.existsSync(fusebasePath)) {
  try {
    const fusebaseConfig = JSON.parse(fs.readFileSync(fusebasePath, "utf-8"));
    const registeredPaths = (fusebaseConfig.apps || []).map((f) => f.path);

    const unregistered = appNames.filter((name) => {
      const appPath = `apps/${name}`;
      return !registeredPaths.includes(appPath);
    });

    if (unregistered.length > 0) {
      errors.push(
        `The following app directories are not registered in fusebase.json:\n` +
          unregistered.map((n) => `  - apps/${n}`).join("\n") +
          `\n\nEach app must be created using "fusebase app create" so it is properly registered.`
      );
    }
  } catch {
    // fusebase.json is malformed — skip this check
  }
}

if (errors.length > 0) {
  const output = {
    decision: "block",
    reason: errors.join("\n\n"),
  };
  console.log(JSON.stringify(output));
}

if (warnings.length > 0) {
  console.error(
    `[openapi-sync-warning]\n${warnings.join("\n\n---\n\n")}\n`,
  );
}

process.exit(0);
