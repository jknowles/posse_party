# Build LinkedIn Company Page posting (posse_party fork), now that API access is approved

*Handoff written 2026-10-30. A snapshot, not living documentation:
`docs/planning/linkedin-page.md` on this branch is the authoritative plan, and where the
two disagree, the plan wins once you have updated it.*

## Your task

Add a new syndication target, **LinkedIn Page**, that posts to the Civilytics Consulting
LLC Company Page, alongside the existing LinkedIn target that posts to Jared's personal
profile. Both must work on the same instance. The design is already decided and a full
checklist exists in `docs/planning/linkedin-page.md`. Your job is to work that plan's
"TODO when resuming" list from step 2 on. Done means: tests green, one real post with an
image lands on the Company Page (not the personal feed) and Jared has confirmed it, and
the plan doc's status line is updated.

## Environment

- **Repo:** `/home/jared/code/jknowles/posse_party`, Jared's fork of
  `searlsco/posse_party` (Rails app). Remotes: `origin` = github.com/jknowles/posse_party,
  `upstream` = github.com/searlsco/posse_party.
- **Branch:** `feat/linkedin-page`. A local branch tracking `origin/feat/linkedin-page`
  exists as of 2026-10-30; the main checkout was left on `main`, so run
  `git checkout feat/linkedin-page` first.
- **Machine:** this checkout is on `efron` (Jared's Linux workstation). Production runs on
  `maxwell` (reach it with `ssh maxwell`). The shell for the Bash tool and for ssh is
  **zsh**: unquoted `$var` does not word-split.
- **Ruby, unverified:** `.ruby-version` says 3.4.8; `ruby -v` on efron's PATH printed
  3.3.8 on 2026-10-30. Check for a version manager (`mise`, `rbenv`, `asdf`) before
  running anything, and do not "fix" this by editing `.ruby-version`.
- **Tests** (from `AGENTS.md`): `CI=true ./script/test` for the full suite,
  `bin/rails test <path>[:line]` for one file. Neither was run for this handoff.
- **`AGENTS.md` is upstream's file, written for upstream's maintainer.** Its coding
  conventions bind you: POROs in `app/lib/**`, no `initialize` args, Mocktail, VCR for
  third-party HTTP, `def test_…` names, no loops or branches in tests. Its "Multi-machine
  sync" section (Macs, iCloud dotfiles, "commit everything and push") does **not**
  describe Jared's setup. Follow Jared's rule instead: commit on the feature branch and
  ask before pushing.

## Current state — verified 2026-10-30

- `feat/linkedin-page` = `c5b7efe` plus this handoff's commit. Relative to `main`
  (`de502b2`), it is 3 commits ahead and 4 behind:
  - `fe60c83` the plan doc; `90da109` a fix making OAuth renewal state survive between
    link and callback (touches the LinkedIn and YouTube token exchange);
    `c5b7efe` the API request status.
  - Behind by `ec8cb9b`, `cd5e714`, `50214cd` (CLAUDE.md → AGENTS.md), `de502b2`.
  - Check: `git rev-list --left-right --count main...feat/linkedin-page`.
- **No Page code exists yet.** `grep -rn 'w_organization_social\|organization_urn' app test`
  returns nothing.
- The existing personal target lives in `app/lib/platforms/linkedin.rb` and
  `app/lib/platforms/linkedin/` (9 files). Its OAuth scope is
  `"openid profile w_member_social"` (`linkedin.rb:46`). Its renewal route is
  `config/routes.rb:65`. The LinkedIn API version sent is `202605`.
- **Production on maxwell** runs `posse_party:media-20261004-wave3` (`posse-web-1`,
  `posse-worker-1`, both healthy) as of 2026-10-30
  (`ssh maxwell "docker ps --format '{{.Names}} {{.Image}}' | grep posse"`). That image
  is a local build from `test/deploy-20261004-wave3`, which already merges
  `feat/linkedin-page` (so the OAuth fix is live; no Page code, because none exists).
- **LinkedIn side:** Jared reports, on 2026-10-30, that the Community Management API
  was approved on the **new** developer app (the one tied to the Civilytics Company Page
  and created 2026-09-16), not on the original personal-profile app. He has the
  credentials. That is the plan's TODO step 1, done. Steps 2–7 are open.

## What to do next

1. **Rebase or merge `main` into the branch** so it builds on current code (4 commits
   behind). No conflicts are expected in LinkedIn code, but `AGENTS.md` replaced
   `CLAUDE.md` on `main`.
2. **Plan TODO step 2: confirm the scope, with Jared doing the clicking.** Ask Jared to
   check the new app's Auth tab and tell you whether `w_organization_social` is listed
   (and whether `r_organization_social` is too). You need only the yes or no, never the
   values. The client ID and secret go into the instance through the web UI or maxwell's
   sealed `.env`, never into the repo, a test fixture, or this transcript.
3. **Plan TODO step 3: the Organization URN** comes from the Page's admin URL
   (`linkedin.com/company/<id>/admin/` → `urn:li:organization:<id>`). It is an identifier,
   not a secret, but still keep the real one out of committed cassettes (use a
   placeholder, as the existing LinkedIn cassettes do for the person URN).
4. **Plan TODO step 4:** the plan recommends that the Page target use the new app's
   credentials rather than transferring access to the old app. Confirm with Jared and go.
5. **Plan TODO step 5: build it, TDD,** on the plan's "Implementation checklist". The
   plan names `4d897fe` ("feat: add Pixelfed as a syndication platform") as the model of
   a full platform addition. That commit is **not on `main`**; it lives on
   `origin/feat/pixelfed-platform`, so read it with `git show 4d897fe`.
6. **Plan TODO step 6: one real post**, recorded and verified with Jared (see Traps for
   the recording rules). Deploying to maxwell follows the fork's wave pattern below and
   needs Jared's go-ahead.
7. **Plan TODO step 7:** a CHANGELOG entry, `docs/account_setup/linkedin_page.md`, and
   flip the plan's status line. Upstream PR or fork-only is Jared's call.

## Traps and hard-won facts

- **Credentials never enter the transcript.** From the fork's wave-1 lessons
  (`docs/planning/2026-10-01-media-wave-2-handoff.md` on `origin/docs/media-plan`): a
  LinkedIn token was lost to a transcript once. Jared runs any command that prints or
  uses a real token in his own terminal. Don't ask him to paste values, and when you
  ask him to run something, say "do not paste the output back."
  - `bin/rails runner` on maxwell prints an Active Storage warning on stdout first, so any
    capture needs `| tail -n 1` plus a shape check
    (`[[ $X =~ ^[A-Za-z0-9._~-]+$ ]] && echo ok`).
- **Never run a recorded test yourself while VCR `record: true` is set.** It makes real
  calls with placeholder credentials; LinkedIn refused one in wave 1.
- **Recording sessions are approved by Jared first.** Delete the test post straight after
  recording, scrub with `vcr_secrets`, grep the cassettes for `Bearer` and for real
  identifiers, have Jared grep for his real secret, and confirm with him before
  committing cassettes. The same rules are in `docs/planning/media-steps-4-9-design.md`
  §10 on `origin/docs/media-plan`.
- **Two LinkedIn apps exist.** The personal target uses the original app; the Page target
  uses the new one. LinkedIn would not add Community Management to an app that already
  had other products, which is why the new one exists.
- **Development Tier is 500 requests per app** (per the plan). That is enough for one
  Page. Don't apply for Standard Tier unless the quota actually binds.
- **Deploy pattern for this fork** (design §11 on `origin/docs/media-plan`): a fresh
  `test/deploy-YYYYMMDD` off `main` that merges every branch currently deployed (see
  `git log --merges origin/test/deploy-20261004-wave3`) plus this one; build on maxwell;
  `pg_dump` first; `POSSE_IMAGE=<tag> docker compose up -d`. **A bare
  `docker compose up -d` on maxwell reverts to upstream's `ghcr.io/searlsco` image**
  unless `POSSE_IMAGE` is pinned in maxwell's sealed `.env` (in the repo
  `/home/jared/code/jared/maxwell_docker_compose`, `posse/`). The design references a
  `maxwell-deploy.local.md` with the build steps. It was **not found** on efron or in
  maxwell's home on 2026-10-30, so ask Jared where it is.
- **LinkedIn API versions:** Marketing version 202511 is sunset on 2026-11-16. The fork
  sends `202605`, so it's unaffected. Use the same header for the Page target.

## Do NOT

- Do not read maxwell's `posse/.env`, or any `.env`, and do not `docker inspect` or
  `env`-dump the posse containers. Those hold secrets.
- Do not push, open a PR upstream, or deploy to maxwell without Jared's explicit go-ahead.
- Do not post to the live Company Page, except in the one approved recording or
  verification session, and delete recording posts afterward.
- Do not add organization auto-discovery via `organizationAcls`. The plan rejected it to
  keep the surface small; the user pastes the Organization URN.
- Do not request `rw_organization_admin` for this target. Posting needs only
  `w_organization_social`. Page **statistics** (`organizationalEntityShareStatistics`)
  need `rw_organization_admin` and are a separate, undecided piece of work for the
  Paperclip CMO agents in `maxwell_docker_compose`. They are out of scope here.
- Do not "fix" the Ruby version mismatch by editing `.ruby-version` or the Gemfile.

## Open questions (Jared decides)

- Is `w_organization_social` present on the new app's Auth tab? (TODO step 2)
- Does the Page target use the new app's credentials (the plan recommends this) or does
  access get transferred to the old app? (step 4)
- Where is `maxwell-deploy.local.md`, and is a new `test/deploy-*` wave wanted for this
  alone or bundled with other branches?
- Is this fork-only, or does it become an upstream PR to searlsco?
