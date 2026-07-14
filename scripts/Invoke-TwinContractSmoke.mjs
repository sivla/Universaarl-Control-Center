import path from 'node:path';
import { pathToFileURL } from 'node:url';

const [twinRoot, blueprintRoot, expectedTwinCommit, expectedBlueprintCommit, expectedBlueprintTree, expectedBranch] = process.argv.slice(2);

if (!twinRoot || !blueprintRoot || !path.isAbsolute(twinRoot) || !path.isAbsolute(blueprintRoot)
  || !/^[a-f0-9]{40}$/.test(expectedTwinCommit || '') || !/^[a-f0-9]{40}$/.test(expectedBlueprintCommit || '')
  || !/^[a-f0-9]{40}$/.test(expectedBlueprintTree || '') || expectedBranch !== 'codex/universaarl-projekt') {
  console.error('Projektpfade, Eingabe-SHAs, Tree und commitgebundener Producerbranch sind erforderlich.');
  process.exit(2);
}

const viteEntry = path.join(twinRoot, 'node_modules', 'vite', 'dist', 'node', 'index.js');
const { createServer } = await import(pathToFileURL(viteEntry).href);
const server = await createServer({ root: twinRoot, configFile: false, appType: 'custom', logLevel: 'silent', server: { middlewareMode: true } });

try {
  const registryModule = await server.ssrLoadModule('/src/projects/registry.ts');
  const adapterModule = await server.ssrLoadModule('/src/server/adapter.ts');
  const previousMode = process.env.UABC_BRANCH_COMMIT_CONTRACT;
  process.env.UABC_BRANCH_COMMIT_CONTRACT = '1';
  let state;
  try {
    const registry = registryModule.productionRegistry(blueprintRoot, expectedBlueprintCommit, expectedBlueprintTree, expectedBranch, true);
    const project = registry.find((entry) => entry.id === 'bc-basic');
    if (!project?.sourceBinding || !project.sourceContract) throw new Error('Der commitgebundene Twin-Registryvertrag fehlt.');
    state = await adapterModule.createTwinState('bc-basic', blueprintRoot, { sourceBinding: project.sourceBinding, projectDataContract: project.sourceContract });
  } finally {
    if (previousMode === undefined) delete process.env.UABC_BRANCH_COMMIT_CONTRACT;
    else process.env.UABC_BRANCH_COMMIT_CONTRACT = previousMode;
  }
  const story = state.story;
  const summary = {
    source: {
      projectId: state.source.projectId,
      commit: state.source.commit,
      branch: state.source.branch,
      dirty: state.source.dirty,
    },
    spectra: state.source.snapshot?.spectraReleaseBinding ?? null,
    stats: {
      tickets: story?.tickets.length ?? 0,
      pages: story?.pages.length ?? 0,
      relations: story?.relations.length ?? 0,
      documents: state.documents.length,
      resources: state.resources.length,
      evidence: state.evidenceItems.length,
    },
    warnings: state.warnings,
  };
  console.log(JSON.stringify(summary));

  if (state.source.projectId !== 'bc-basic'
    || state.source.commit !== expectedBlueprintCommit
    || state.source.branch !== expectedBranch || state.source.dirty
    || state.source.snapshot?.spectraReleaseBinding?.releaseTag !== 'spectra-v1.0.0'
    || state.source.snapshot?.spectraReleaseBinding?.tagCommit !== 'c05649bd10ed29a082bbe2338d7d326d3d755687'
    || !story || story.tickets.length !== 50 || state.documents.length !== 46) {
    process.exitCode = 3;
  }
} finally {
  await server.close();
}
