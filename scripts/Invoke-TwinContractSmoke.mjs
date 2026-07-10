import path from 'node:path';
import { pathToFileURL } from 'node:url';

const [twinRoot, blueprintRoot] = process.argv.slice(2);

if (!twinRoot || !blueprintRoot || !path.isAbsolute(twinRoot) || !path.isAbsolute(blueprintRoot)) {
  console.error('Die Snapshot-Pfade von Twin und Blueprint muessen absolut sein.');
  process.exit(2);
}

const viteEntry = path.join(twinRoot, 'node_modules', 'vite', 'dist', 'node', 'index.js');
const { createServer } = await import(pathToFileURL(viteEntry).href);
const server = await createServer({
  root: twinRoot,
  appType: 'custom',
  logLevel: 'silent',
  server: { middlewareMode: true },
});

try {
  const adapter = await server.ssrLoadModule('/src/server/adapter.ts');
  const state = await adapter.createTwinState(blueprintRoot);
  const summary = {
    source: {
      branch: state.source.branch,
      commit: state.source.commit,
      dirty: state.source.dirty,
      pathLabel: state.source.pathLabel,
    },
    stats: state.stats,
    warningCount: state.warnings.length,
    warnings: state.warnings,
    gapCount: state.gaps.length,
  };

  console.log(JSON.stringify(summary));

  if (state.stats.capabilities < 1 || state.stats.changes < 1 || state.stats.documents < 1) {
    process.exitCode = 3;
  }
} finally {
  await server.close();
}
