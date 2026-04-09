import { copyFile, access, mkdir } from "node:fs/promises";
import { constants as fsConstants } from "node:fs";
import path from "node:path";

const nextDir = path.join(process.cwd(), ".next");
const routesManifestPath = path.join(nextDir, "routes-manifest.json");
const deterministicManifestPath = path.join(
  nextDir,
  "routes-manifest-deterministic.json",
);
const repoRootNextDir = path.resolve(process.cwd(), "..", ".next");
const repoRootDeterministicManifestPath = path.join(
  repoRootNextDir,
  "routes-manifest-deterministic.json",
);

const fileExists = async (filePath) => {
  try {
    await access(filePath, fsConstants.F_OK);
    return true;
  } catch {
    return false;
  }
};

const ensureManifest = async () => {
  if (await fileExists(deterministicManifestPath)) {
    console.log("[postbuild] routes-manifest-deterministic.json already present");
  } else {
    if (!(await fileExists(routesManifestPath))) {
      console.warn("[postbuild] routes-manifest.json not found; skipping deterministic manifest fallback");
      return;
    }

    await copyFile(routesManifestPath, deterministicManifestPath);
    console.log("[postbuild] created routes-manifest-deterministic.json from routes-manifest.json");
  }

  if (path.normalize(repoRootNextDir) === path.normalize(nextDir)) {
    return;
  }

  await mkdir(repoRootNextDir, { recursive: true });
  await copyFile(deterministicManifestPath, repoRootDeterministicManifestPath);
  console.log("[postbuild] mirrored routes-manifest-deterministic.json to repo root .next");
};

await ensureManifest();
