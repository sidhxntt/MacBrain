#!/usr/bin/env node

import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, posix, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const output = process.argv[2] ? resolve(process.argv[2]) : undefined;
const repositoryURL = "https://github.com/sidhxntt/MacBrain";
const pages = [
  ["wiki/index.md", "Home.md"],
  ["wiki/overview.md", "Overview.md"],
  ["wiki/features.md", "Features.md"],
  ["wiki/architecture.md", "Architecture.md"],
  ["wiki/technology-stack.md", "Technology-Stack.md"],
  ["wiki/implementation-guide.md", "Engineering-Implementation-Guide.md"],
  ["wiki/connectors-and-indexing.md", "Connectors-and-Indexing.md"],
  ["wiki/retrieval-citations-memory.md", "Retrieval-Citations-and-Memory.md"],
  ["wiki/engineering-challenges.md", "Engineering-Challenges.md"],
  ["wiki/roadmap.md", "Roadmap-and-Delivery-Status.md"],
  ["wiki/privacy-and-permissions.md", "Privacy-and-Permissions.md"],
  ["wiki/conclusion.md", "Conclusion.md"],
  ["wiki/development.md", "Development-and-Verification.md"],
  ["wiki/phases/phase-1-app-shell.md", "Phase-1-App-Shell.md"],
  ["wiki/phases/phase-2-activation-permissions.md", "Phase-2-Activation-and-Permissions.md"],
  ["wiki/phases/phase-3-storage.md", "Phase-3-Storage.md"],
  ["wiki/phases/phase-4-local-inference.md", "Phase-4-Local-Inference.md"],
  ["wiki/phases/phase-5-indexing.md", "Phase-5-Indexing.md"],
  ["wiki/phases/phase-6-9-knowledge-workflow.md", "Phase-6-9-Knowledge-Workflow.md"],
  ["wiki/phases/phase-10-hardening-release.md", "Phase-10-Hardening-and-Release.md"],
  ["wiki-publishing.md", "Wiki-Publishing.md"],
  ["wiki/_Sidebar.md", "_Sidebar.md"],
  ["wiki/_Footer.md", "_Footer.md"],
];

if (!output) {
  console.error("Usage: node scripts/render-github-wiki.mjs <wiki-directory>");
  process.exit(2);
}

const names = new Map(pages.map(([source, destination]) => [source, destination.replace(/\.md$/, "")]));
function rewriteLinks(markdown, source) {
  return markdown.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (full, text, href) => {
    if (/^(?:https?:|mailto:|#)/i.test(href)) return full;
    const [path, anchor = ""] = href.split("#", 2);
    const target = posix.normalize(posix.join(posix.dirname(source), path));
    const page = names.get(target);
    if (page) return `[${text}](${page}${anchor ? `#${anchor}` : ""})`;
    const repoPath = posix.normalize(posix.join("docs", posix.dirname(source), path));
    return repoPath.startsWith("../") ? full : `[${text}](${repositoryURL}/blob/main/${repoPath}${anchor ? `#${anchor}` : ""})`;
  });
}

await mkdir(output, { recursive: true });
for (const [source, destination] of pages) {
  const markdown = await readFile(resolve(root, "docs", source), "utf8");
  await writeFile(resolve(output, destination), rewriteLinks(markdown, source));
}
console.log(`Rendered ${pages.length} MacBrain Wiki pages into ${output}`);
