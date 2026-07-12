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
  const bcBasicState = await adapter.createTwinState('bc-basic', blueprintRoot, {
    projectDataContract: {
      manifestPath: 'exports/project-data/v1/snapshot-manifest.json',
      schemaPath: 'governance/schemas/project-snapshot-manifest.schema.json',
      indexPath: 'exports/project-data/v1/index.yaml',
      expectedProjectId: 'UABC-BC-BASIC-001',
      expectedProducerId: 'blueprint',
    },
  });
  const story = bcBasicState.story;
  const summary = {
    sources: {
      bcBasic: { commit: bcBasicState.source.commit, dirty: bcBasicState.source.dirty },
    },
    stats: { bcBasic: bcBasicState.stats },
    story: story ? {
      offers: story.offer?.versions.length ?? 0,
      pages: story.pages.length,
      tickets: story.tickets.length,
      timeline: story.timeline.length,
      hypercare: story.hypercare.length,
      relations: story.relations.length,
    } : null,
    warningCount: bcBasicState.warnings.length,
    warnings: bcBasicState.warnings,
    gapCount: bcBasicState.gaps.length,
  };

  console.log(JSON.stringify(summary));

  if (bcBasicState.source.commit !== expectedBlueprintCommit || bcBasicState.source.dirty
    || bcBasicState.source.projectId !== 'bc-basic' || !story
    || story.offer?.versions.length !== 3 || story.pages.length !== 19 || story.tickets.length !== 17
    || story.timeline.length !== 15 || story.hypercare.length !== 3 || story.relations.length !== 252
    || bcBasicState.evidenceItems.length !== 0) {
    process.exitCode = 3;
  }
} finally {
  await server.close();
}
