// Copies the legal pages from ../../store into public/ before
// `firebase deploy`, and refuses to publish while placeholders remain.
import {copyFileSync, readFileSync} from "node:fs";
import {dirname, join} from "node:path";
import {fileURLToPath} from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const store = join(here, "..", "..", "store");
const pages = ["privacy-policy.md", "terms.md", "delete-account.md"];
const placeholder = /\[(DATE|COMPANY LEGAL NAME|SUPPORT EMAIL|POSTAL ADDRESS|REGION[^\]]*|MAP PROVIDER[^\]]*|DELETION PAGE URL|JURISDICTION)\]/g;

let missing = 0;
for (const page of pages) {
  const text = readFileSync(join(store, page), "utf8");
  const found = [...new Set(text.match(placeholder) ?? [])];
  if (found.length) {
    console.error(`store/${page} still has: ${found.join(", ")}`);
    missing += found.length;
  }
  copyFileSync(join(store, page), join(here, "public", page));
}
if (missing && !process.argv.includes("--allow-placeholders")) {
  console.error("Fill these in before deploying (see STORE_SUBMISSION.md, step 4).");
  process.exit(1);
}
console.log(`Copied ${pages.length} legal pages into firebase/hosting/public`);
