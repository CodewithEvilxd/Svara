import { copyFile, access } from "node:fs/promises";
import { constants as fsConstants } from "node:fs";
import path from "node:path";

const nextDir = path.join(process.cwd(), ".next");
const routesManifestPath = path.join(nextDir, "routes-manifest.json");
const deterministicManifestPath = path.join(
  nextDir,
  "routes-manifest-deterministic.json",
);

const ensureManifest = async () => {
  try {
    await access(deterministicManifestPath, fsConstants.F_OK);
    console.log("[postbuild] routes-manifest-deterministic.json already present");
    return;
  } catch {}

  try {
    await access(routesManifestPath, fsConstants.F_OK);
  } catch {
    console.warn("[postbuild] routes-manifest.json not found; skipping deterministic manifest fallback");
    return;
  }

  await copyFile(routesManifestPath, deterministicManifestPath);
  console.log("[postbuild] created routes-manifest-deterministic.json from routes-manifest.json");
};

await ensureManifest();
