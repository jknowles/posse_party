# Plan and build media wave 2: Mastodon and Bluesky images (posse_party fork)

*Handoff written 2026-10-01. It is a snapshot of that date and is never updated. The spec
and the wave-1 plan linked below are the authoritative documents.*

## Your task

Write the implementation plan for **wave 2** of the fork's media work, and hand it to Jared
Knowles for review:

- step 4, Mastodon images;
- step 5, Bluesky images.

Use `superpowers:writing-plans`. The design is already approved: the spec covers both
steps, and `superpowers:brainstorming` is not needed. Ask Jared only about what the spec
leaves open.

Write the plan the way wave 1's was written. Build and verify every code block in a scratch
worktree with the Docker test environment first, then generate the plan from the verified
code. The plan should end with the same three stages wave 1 ended with:

- a recording session that waits for Jared's approval;
- a deploy to maxwell that waits for Jared's approval;
- one real post that Jared checks.

You're done when the plan is committed on `docs/media-plan` as
`docs/planning/media-wave-2-plan.md`, and Jared has reviewed it and chosen how to execute
it. Executing the plan is not part of this handoff unless Jared asks.

## Read first

All of these are on branch `docs/media-plan`. Read them with
`git show docs/media-plan:<path>`, or with a worktree on that branch.

- **The spec:** `docs/planning/media-steps-4-9-design.md`. The sections that bind wave 2:
  - §5, the contract;
  - §6, the foundation;
  - §8 step 4, Mastodon;
  - §9 step 5, Bluesky;
  - §10, recording: Mastodon gets one multi-image post and one GIF, Bluesky gets one
    multi-image post;
  - §11, waves and deploy.
- **The wave-1 plan:** `docs/planning/media-wave-1-plan.md`. Copy its shape:
  - the header, Global Constraints, Review Focus and rulings sections;
  - Task 0, which sets up the environment;
  - tasks written test-first;
  - the recording task's STOP points;
  - the deploy task.
- **The wave-1 ledger:** `docs/planning/media-wave-1-ledger.md`. Every ruling made while
  wave 1 was implemented and reviewed, plus the deferred minors M5–M13. Several touch
  shared code wave 2 builds on:
  - M7: an error other than `MediaUnavailable` in the media step still fails the post;
  - M9: `media_fallback` goes stale across retries;
  - M10: downloads have no overall deadline.

  Decide whether the shared fix belongs in the foundation now.

## Where things stand

- **Wave 1 is live.** maxwell runs `posse_party:media-20261001`, built from
  `test/deploy-20261001` at `5a094dc`. It's pinned in maxwell's sealed `.env`, so a bare
  `docker compose up -d` stays on it. LinkedIn posts images and GIFs natively; Instagram
  reads `platform_overrides.instagram.media`.
- **The wave-1 branches, all pushed to `origin` (github.com/jknowles/posse_party):**
  - `docs/media-contract` (`d86712f`);
  - `feat/media-foundation` (`914ff83`), which branches from the contract;
  - `feat/linkedin-images` (`19eeb4a`), which branches from the foundation and merges
    `fix/linkedin-one-url`;
  - `test/deploy-20261001` (`5a094dc`).
- **The foundation already provides:**
  - `MediaItem` and `ParsesMediaItems#parse`;
  - `SelectsMedia#select(items, max_images:)`, which returns `images`, `video`, `dropped`
    and `empty?`;
  - `DownloadsMedia#download(item, max_bytes:)`, which returns a `Result` holding
    `Downloaded(bytes, content_type)`;
  - `RecordsMediaFallback#record(crosspost, reason)`;
  - `MediaUnavailable`;
  - the fixtures `test/fixtures/files/media/{still.jpg,still.png,loop.gif}`. Recorded tests
    fetch them from commit `914ff8332cb956c77ac45a0dd182dc8a47f862a7` on GitHub, not from a
    branch name.
- **The foundation does not have** `WaitsForProcessing` (spec §6) or
  `download_to_tempfile`. Mastodon's `POST /api/v2/media` can answer 202 and needs polling,
  so `WaitsForProcessing`, and the finish-later path it implies, arrives with wave 2.
  - Add it to `feat/media-foundation`, then branch `feat/mastodon-images` and
    `feat/bsky-images` from the updated foundation.
  - `feat/linkedin-images` doesn't need it until wave 3's video step.
- **The LinkedIn pattern to follow is
  `Platforms::Linkedin::UploadsMedia#upload(crosspost, crosspost_config, access_token:, person_urn:)`.**
  It selects the media and uploads each item. On any `MediaUnavailable` it records the
  reason, then returns `[]` so the post goes out as before.
  - The adapter then composes the post with or without media. See
    `syndicates_linkedin_post.rb` and `LimitsToOneUrl#limit_with_media` on
    `feat/linkedin-images`.
  - `RedactsBearerToken` keeps tokens out of error messages, including Net::HTTP's error
    for a header that contains a line break. Reuse the idea wherever a Mastodon or Bluesky
    credential reaches a message.
- **What civilytics.com sends** (`layouts/partials/social-media.html` in homepage_test):
  - Mastodon gets a GIF as itself, through its `mastodon` override, or up to 4 stills.
  - Bluesky gets a GIF's loop MP4 and poster, as a `video` item with
    `presentation: "gif"`, or up to 4 stills. In wave 2 a Bluesky GIF post should fall
    back, as LinkedIn video does, until wave 3.
  - The site never mixes a GIF with stills, and the site's linter enforces Mastodon's 16 MB
    and 1-megapixel limits for a GIF.
- **Still open from wave 1** (its plan's Task 10). These wait on Jared and are not yours
  unless he asks:
  - homepage_test `dev` is not merged to `main` yet;
  - the first real civilytics.com GIF crosspost to LinkedIn, and its check;
  - closing fork issue #9;
  - a comment on jaredknowles.com #61;
  - a fork issue for showing `media_fallback` on the crosspost page;
  - the `docs/planning/media.md` status line.

  Plan wave 2's deploy to come after that real-post check, so a problem can be traced to
  one wave.
- **Fork issues on GitHub:** #1 is the Mastodon/Bluesky/Pixelfed media issue (wave 2
  commits say `Refs #1`), #9 is LinkedIn images, #7 is LinkedIn video.

## Environment

- **The fork's checkout** is `/home/jared/Nextcloud/Civilytics/Code/jknowles/posse_party`,
  on `test/deploy-20260928`. It lives in Nextcloud, which adds file-mode noise. Do all
  branch work in a worktree under `/tmp` (wave 1 used `/tmp/posse-wave1`, which still
  exists; use `/tmp/posse-wave2`). The scratch worktree for verifying code is separate,
  for example `/tmp/posse-wave2-scratch`.
- **Remotes:** `origin` is github.com/jknowles/posse_party; `upstream` is
  searlsco/posse_party. Check first that `main` equals `upstream/main`. If upstream has
  moved, stop and ask.
- **The fork's `AGENTS.md` conventions bind:**
  - POROs in `app/lib`, built with no `initialize` arguments;
  - `Result` and `Outcome` return values;
  - no loops or branching in tests;
  - VCR for third-party servers (WebMock only for error branches you cannot record);
  - Mocktail.

  Mocktail checks a stubbed call against the real method's signature, so a test that
  stubs a keyword the method doesn't have yet errors with `unknown keyword`.
- **The test environment is Docker, because the host has no Ruby 3.4.8:**
  - The image `posse-test-ruby` comes from `~/.cache/posse-test/Dockerfile`: Ruby 3.4.8,
    libvips, libidn, Node 22, Yarn and Playwright Chromium.
  - The `posse-test-db` container (postgres:17-alpine) runs on network `posse-test`, with
    gems in volume `posse-test-gems`.
  - `~/.cache/posse-test/rt.sh "<command>"` runs one command against the worktree in
    `$POSSE_TREE`. It defaults to `/tmp/posse-wave1`, so pass `POSSE_TREE=/tmp/posse-wave2`
    explicitly. It hands files back to the host user and passes through `$?`.
  - A fresh worktree needs, once:
    `rt.sh "bundle install --quiet && yarn install --frozen-lockfile --silent && bin/rails db:prepare"`.
  - Full suite: `rt.sh "CI=true ./script/test"`. This is `rake`. It runs `standard:fix`
    first, which can rewrite files, and it stops after unit-test failures without running
    the system tests.
- **The deploy runbook** is `maxwell-deploy.local.md` in the fork checkout (gitignored;
  never commit it); use section 1a.
  - The deploy branch is a fresh `test/deploy-YYYYMMDD` off `main` that merges
    `test/deploy-20261001`, then the wave's branches. Re-merging the old deploy's five
    branches conflicts in `docs/feed.md`; the previous deploy branch already holds the
    resolution.
  - Rollback: `POSSE_IMAGE=posse_party:media-20261001 docker compose up -d`.
  - After a deploy, Jared re-pins the image: edit `~/docker-compose/posse/.env` on maxwell,
    run `bin/secrets-seal`, then commit `posse/.env.age`. Never `git add -f` the plaintext
    `.env`.

## Lessons from wave 1. Put them in the plan, not just your head

1. **Credentials never enter the transcript.** During a recording, Jared runs the
   recording command in his own terminal. You can't see his environment, and you don't
   ask him to paste values.
   - `bin/rails runner` on maxwell prints an Active Storage warning on stdout first, so
     every capture needs `| tail -n 1` and a check that the value looks like a token. A
     length check is not enough:
     `[[ $X =~ ^[A-Za-z0-9._~-]+$ ]] && echo ok`.
   - Wave 1 lost a LinkedIn token to the transcript this way.
2. **Never run the recorded tests yourself while `record: true` is set.** VCR then makes
   real calls with the placeholder credentials. Wave 1 did this once, and LinkedIn
   refused it.
3. **Before recording:**
   - pin fixture URLs to a commit;
   - make the recorded tests assert the request bodies positively, not just
     `media_fallback` being nil;
   - after recording, grep the cassettes for `Bearer` and the account identifiers not
     being placeholders, and have Jared grep for his real secret.
4. **Delete the test posts straight after recording**, and confirm with Jared before you
   commit the cassettes.
5. **Each wave ends with a whole-branch review on the most capable model.** It found the
   token leak and the one-URL regression in wave 1.

## Spec points to settle in the plan

- **Mastodon:**
  - the `Idempotency-Key: posse-party-crosspost-<id>` header on the status post (Jared
    approved this in the spec);
  - polling for a 202 upload, inline for about 60 s, then the finish-later path with
    `metadata["mastodon_media"]`;
  - 413 and 422 fall back to text.
- **Bluesky:**
  - extract `UploadsBskyBlob` from `AttachesWebCard`, and have it download through
    `DownloadsMedia`, which follows redirects;
  - `FitsImageWithinByteLimit` at 2,000,000 bytes (the old plan said 1,000,000; the lexicon
    says 2,000,000);
  - `aspectRatio` comes from `width`/`height`, or is read with libvips when absent;
  - with media there is no web card.
- **`docs/feed.md`:** update the `media` row's platform list. That line will conflict
  between the Mastodon and Bluesky branches, so plan which branch edits it, or edit it
  once in the deploy merge.
