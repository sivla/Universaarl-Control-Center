import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { execFileSync } from 'node:child_process';

const [twinRoot, blueprintRoot, expectedTwinCommit, expectedBlueprintCommit] = process.argv.slice(2);

if (!twinRoot || !blueprintRoot || !path.isAbsolute(twinRoot) || !path.isAbsolute(blueprintRoot)
  || !/^[a-f0-9]{40}$/.test(expectedTwinCommit || '') || !/^[a-f0-9]{40}$/.test(expectedBlueprintCommit || '')) {
  console.error('Snapshot-Pfade und vollstaendige Eingabe-SHAs von Twin und Blueprint sind erforderlich.');
  process.exit(2);
}

const readGit = (root, args) => execFileSync('git', ['-C', root, ...args], {
  encoding: 'utf8',
  env: {
    ...process.env,
    GIT_OPTIONAL_LOCKS: '0',
    GIT_TERMINAL_PROMPT: '0',
    GIT_PAGER: 'cat',
  },
  stdio: ['ignore', 'pipe', 'pipe'],
  windowsHide: true,
}).trim();

let twinHead;
let blueprintHead;
let twinStatus;
let blueprintStatus;
try {
  twinHead = readGit(twinRoot, ['rev-parse', '--verify', 'HEAD^{commit}']);
  blueprintHead = readGit(blueprintRoot, ['rev-parse', '--verify', 'HEAD^{commit}']);
  twinStatus = readGit(twinRoot, ['-c', 'core.fsmonitor=false', '-c', 'core.untrackedCache=false', 'status', '--porcelain=v1', '--untracked-files=all']);
  blueprintStatus = readGit(blueprintRoot, ['-c', 'core.fsmonitor=false', '-c', 'core.untrackedCache=false', 'status', '--porcelain=v1', '--untracked-files=all']);
} catch {
  console.error('Commitzustand der Vertragskopien kann nicht sicher gelesen werden.');
  process.exit(3);
}
if (twinHead !== expectedTwinCommit || blueprintHead !== expectedBlueprintCommit || twinStatus || blueprintStatus) {
  console.error('Vertragskopien stimmen nicht exakt mit beiden erwarteten sauberen Commits ueberein.');
  process.exit(3);
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

  if (state.source.commit !== expectedBlueprintCommit || state.source.dirty
    || state.stats.capabilities < 1 || state.stats.changes < 1 || state.stats.documents < 1) {
    process.exitCode = 3;
  }
} finally {
  await server.close();
}
