# Taste Map public website canonical source

Recovered byte-for-byte from the four public HTTPS resources on 2026-09-09 after original local repositories, worktrees, archive paths, histories and Cloudflare deployment metadata did not yield a recoverable source directory. This is a newly adopted source, not a claim to have recovered the historical project.

Source: `web-public/public/`. No compilation or dependency installation is required. `baseline.json` records the original public resource hashes and Cloudflare version. Keep index.html, support.html and styles.css unchanged when applying this privacy patch.

Cloudflare Worker: `fancy-fog-1341`; existing custom domain `tastemap.cn`. API Worker `private-food-map` and its more-specific invitation / AASA routes must remain unchanged. No D1, R2, secret or account credential belongs in this site.

From repository root:

```sh
pnpm exec wrangler dev --config web-public/wrangler.jsonc
pnpm exec wrangler deploy --config web-public/wrangler.jsonc --dry-run
# Only after matching backend retention is active and policy review passes:
pnpm exec wrangler deploy --config web-public/wrangler.jsonc
```

Deploy preserves the existing Worker name; do not create or replace domains/routes. Before deployment confirm its current custom domain and capture its version. Verify `/`, `/index.html`, `/support.html`, `/styles.css`, `/privacy.html` and HTTPS after deployment. Verify the three unaffected file hashes against baseline.json. `html_handling: none` preserves explicit .html URLs.

Rollback before a later deployment removes historical versions:

```sh
pnpm exec wrangler rollback f9d342db-afb5-4153-9085-8385dd725f01 --config web-public/wrangler.jsonc
```

Alternatively build a rollback source tree with `git archive <baseline-commit> web-public` and deploy that config. Do not deploy from a temporary downloaded HTML copy. Rollback is website-only, never a database restore.

Core UI / page template: existing public static-page template and styles preserved. Food/dining visual components: none. No iOS or Hybrid renderer changes.
