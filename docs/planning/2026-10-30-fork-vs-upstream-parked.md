# Parked decision: keep the fork's media series, or converge on upstream

**Status:** Parked 2026-10-30 by Jared. Decide later; nothing below is scheduled.
**Scope:** the whole fork (`jknowles/posse_party`), not only LinkedIn Page.

## The decision

Upstream (`searlsco/posse_party`) shipped its own media support on 2026-10-22 (`7b64f33`,
"Attach media to Bluesky, X, Mastodon, Threads, and LinkedIn crossposts", by Justin Searls). It
covers the same ground as the fork's media series (`feat/media-foundation`, `feat/*-images`,
`feat/*-video`, deployed in waves 1–3) with a different code design. Decide whether the fork:

- **A. Keeps its own media series** and goes on merging upstream around it, or
- **B. Drops its media series and converges on upstream's**, porting what only the fork has.

## Facts as of 2026-10-30

- Upstream `main` is `0b71a8d` (2026-10-23). The fork last synced at `de502b2`; upstream is 13
  commits past that, including Ruby 4.0.7 then 4.0.9 (`.ruby-version`, `Dockerfile`) and a
  migration (`20261022120000_add_media_fallback_to_accounts_and_posts`).
- The deployed tree, `origin/test/deploy-20261030` (`8650cb3`, image `posse_party:media-20261030`),
  is 90 commits ahead of upstream and 13 behind. Most of the 90 are the media series.
- Jared has no PRs on `searlsco/posse_party`, open or closed.
- **Feed contract.** Both accept `media` items with `type`, `url`, `alt`, `poster_url`.
  Upstream adds `media_fallback` (`"link"` default, `"best_effort"`, `"fail"`). The fork adds
  `presentation: "gif"`, `mime`, `width`, `height`, and documents per-platform
  `platform_overrides.<tag>.media`; upstream's code guards that field but its docs do not
  describe it. Not checked: whether Jared's site feed relies on a fork-only field.
- **Only in the fork:** LinkedIn Company Page posting (`feat/linkedin-page`, live since
  2026-10-30, stacked on `feat/linkedin-video`); Pixelfed (`feat/pixelfed-platform`, June, no
  screenshots); fixes `fix/linkedin-one-url`, `fix/bsky-fit-thumbnail`,
  `fix/bsky-external-embed-description`, not yet checked against upstream's changes.
- `app/lib/downloads_media.rb` (fork) fetches feed-supplied URLs without blocking private
  addresses; flagged by an automated review on 2026-10-30. Low risk while every feed is Jared's.
  Upstream has its own `downloads_media.rb`; not compared.

## What each option costs

**A. Keep the fork's media.** Nothing now. Every later upstream sync conflicts in the media and
platform code, and grows as upstream builds on its own media classes. Upstream's Ruby 4 move has
to be taken eventually for security updates. Nothing media-related can go upstream as a PR.

**B. Converge on upstream.** One planned wave:
- check Jared's site feed against upstream's fields, and decide what to do about `presentation`,
  `mime` and per-platform media overrides;
- run upstream's migration and Ruby 4.0.9 on maxwell (pg_dump first, as in the runbook);
- port LinkedIn Page onto upstream's LinkedIn code (`syndicates_linkedin_post.rb`,
  `finishes_linkedin_post.rb`, `uploads_images.rb`, `uploads_video.rb`) and re-record its
  cassettes against the real Page (up to six posts, deleted after);
- rebase Pixelfed and re-check the three fixes.

After B the fork is a few branches on top of upstream, and LinkedIn Page and Pixelfed become
natural upstream PRs.

## What does not wait on this

- A short Civilytics post that the Company Page now posts from the site through self-hosted
  software.
- Screenshots for `docs/account_setup/linkedin_page.md`.

## Revisit when

- the next upstream feature or fix is wanted on maxwell;
- a Ruby or dependency security update forces a sync;
- Jared wants to open the LinkedIn Page or Pixelfed PR upstream;
- before planning another deploy wave.
