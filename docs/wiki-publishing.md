# Publishing the MacBrain GitHub Wiki

Repository Markdown in `docs/wiki/` is the source of truth. Do not author duplicate pages directly in GitHub Wiki.

1. Enable GitHub Wikis and create an initial page once.
2. Clone `https://github.com/sidhxntt/NotchBrain.wiki.git` beside this repository.
3. Run `node scripts/render-github-wiki.mjs ../notchbrain.wiki`.
4. Inspect `git diff` in the Wiki clone, commit the generated pages, and push.

The renderer writes only managed pages and does not delete hand-maintained Wiki files. Never include source data, secrets, paths containing user data, or raw diagnostics in published content.
