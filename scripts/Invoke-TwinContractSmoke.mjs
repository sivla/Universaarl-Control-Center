import path from 'node:path';
import { pathToFileURL } from 'node:url';

const [twinRoot, blueprintRoot, expectedTwinCommit, expectedBlueprintCommit] = process.argv.slice(2);

if (!twinRoot || !blueprintRoot || !path.isAbsolute(twinRoot) || !path.isAbsolute(blueprintRoot)
  || !/^[a-f0-9]{40}$/.test(expectedTwinCommit || '') || !/^[a-f0-9]{40}$/.test(expectedBlueprintCommit || '')) {
  console.error('Snapshot-Pfade und vollstaendige Eingabe-SHAs von Twin und Blueprint sind erforderlich.');
  process.exit(2);
}

const viteEntry = path.join(twinRoot, 'node_modules', 'vite', 'dist', 'node', 'index.js');
const { createServer } = await import(pathToFileURL(viteEntry).href);
const server = await createServer({ root: twinRoot, configFile: false, appType: 'custom', logLevel: 'silent', server: { middlewareMode: true } });

try {
  const catalogModule = await server.ssrLoadModule('/src/server/snapshot-catalog.ts');
  const previousPath = process.env.PATH;
  process.env.PATH = '';
  let loaded;
  try {
    loaded = await catalogModule.loadSnapshotCatalog({
      id: 'bc-basic',
      type: 'filesystem',
      address: blueprintRoot,
      expectedCustomerId: 'UABC-CUSTOMER-001',
      expectedProjectId: 'UABC-BC-BASIC-001',
      displayName: 'Universaarl BC Basic',
    });
  } finally {
    process.env.PATH = previousPath;
  }

  const state = loaded.state;
  const story = state.story;
  const summary = {
    releaseId: loaded.releaseId,
    source: {
      projectId: state.source.projectId,
      commit: state.source.commit,
      branch: state.source.branch,
      dirty: state.source.dirty,
      catalog: state.source.catalog,
    },
    spectra: state.source.snapshot?.spectraReleaseBinding ?? null,
    stats: {
      tickets: story?.tickets.length ?? 0,
      pages: story?.pages.length ?? 0,
      relations: story?.relations.length ?? 0,
      documents: state.documents.length,
      resources: state.resources.length,
      evidence: state.evidenceItems.length,
      payloads: loaded.payloads.size,
    },
    warnings: state.warnings,
  };
  console.log(JSON.stringify(summary));

  if (loaded.releaseId !== 'UABC-PORTABLE-PILOT-0003'
    || state.source.projectId !== 'bc-basic'
    || state.source.commit !== '8132f2ce692dfcb8e12a3a4db4a287c643a6376f'
    || state.source.branch !== null || state.source.dirty
    || state.source.catalog?.customerId !== 'UABC-CUSTOMER-001'
    || state.source.catalog?.projectId !== 'UABC-BC-BASIC-001'
    || state.source.catalog?.manifestDigest !== 'sha256:5710f0c5315ede59f8af1bbe6a154725a180ef9c87c6502a83f1008892eaf863'
    || state.source.snapshot?.spectraReleaseBinding?.releaseTag !== 'spectra-v1.2.0-alpha.12'
    || state.source.snapshot?.spectraReleaseBinding?.tagCommit !== '6b3d9a1bfaf6cd806218a802fdde8f1a4cfa55a1'
    || !story || story.tickets.length !== 50 || story.pages.length !== 28 || story.relations.length !== 1044
    || state.documents.length < 28) {
    process.exitCode = 3;
  }
} finally {
  await server.close();
}
