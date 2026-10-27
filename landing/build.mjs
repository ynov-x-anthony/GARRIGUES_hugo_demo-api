// Script de build sans dépendance : génère build/ prêt à être servi par nginx.
import { readFile, writeFile, mkdir, cp } from "node:fs/promises";

const version = process.env.BUILD_VERSION ?? "dev";

// Minification volontairement simple : on retire les commentaires et
// l'indentation. Un bundler serait hors périmètre pour ce mini-projet.
const html = await readFile("site/index.html", "utf8");
const minified = html
  .replace(/<!--[\s\S]*?-->/g, "")
  .split("\n")
  .map((line) => line.trim())
  .filter(Boolean)
  .join("\n")
  .replaceAll("__BUILD_VERSION__", version);

await mkdir("build", { recursive: true });
await writeFile("build/index.html", minified);
await cp("site/style.css", "build/style.css");
// L'asset lourd (vidéo de fond) ne transite que par le stage de build :
// le runtime ne reçoit que le contenu final de build/.
await cp("assets", "build/assets", { recursive: true });

console.log(`build/index.html prêt (version ${version})`);
