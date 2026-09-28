# Plan: native media and link handling across publishers

**Status:** Step 1 done 2026-09-28 (#5 closed). Docs and a regression test are on
`docs/platform-defaults`, not yet merged anywhere. civilytics.com #128 is open but not blocking.
Steps 2 and 3 built 2026-09-28 (`fix/linkedin-one-url`, `fix/bsky-fit-thumbnail`) and deployed
to maxwell the same day in `posse_party:media-20260928` (`test/deploy-20260928`, `0c1624f`). #4 and
#6 close once a live post shows each working. Steps 4 to 10 not started. Upstream PR candidates are
tracked in #10.
**Branch:** this plan lives on `docs/media-plan`; update its status there. Code goes on one branch
per step, off `main` (see "Branches").

## Branches

- `main` mirrors `upstream/main` (searlsco). Fast-forward only; fork-only work never lands on it,
  so any step branch can go upstream as a PR without carrying fork commits.
- One branch per step, off `main`: `docs/platform-defaults` (step 1), then for example
  `fix/linkedin-one-url`, `fix/bsky-fit-thumbnail`, `feat/mastodon-images`.
- Deploy by merging the step branches into a fresh `test/deploy-YYYYMMDD` off `main`, as
  `test/deploy-20260914` did with `feat/pixelfed-platform` and `fix/bsky-external-embed-description`.
- Upstream's `de502b2` (on `main` since 2026-09-28) fixes the same blank-description Bluesky card
  failure as the fork's `fix/bsky-external-embed-description`, differently. Check whether
  upstream's fix is enough before merging the fork branch into the next deploy; both edit
  `attaches_web_card.rb`, which step 3 also changes.

## Inputs

Two feeds on Gitea feed this instance. Any change that needs a feed to send something different
gets an issue in that feed's repo, not only here.

| Site | Repo | Feed template |
| --- | --- | --- |
| civilytics.com | [Civilytics/homepage_test](https://gitea.civilytics.org/Civilytics/homepage_test) | `layouts/partials/posse-post.html` (newsletter posts) |
| jaredknowles.com | [jared/jaredknowles.com](https://gitea.civilytics.org/jared/jaredknowles.com) | `layouts/partials/posse-post.html` (shots, takes, posts, links, galleries, datasets) |

## Issues covered

| Issue | Title | Resolution |
| --- | --- | --- |
| [#5](https://github.com/jknowles/posse_party/issues/5) | Permalink appended to posts that were not truncated | Feed config, not a bug. See step 1 |
| [#6](https://github.com/jknowles/posse_party/issues/6) | LinkedIn: at most one URL per post | Publisher change. See step 2 |
| [#4](https://github.com/jknowles/posse_party/issues/4) | Bluesky: downscale embed thumbnail to fit 1 MB | Step 3 |
| [#1](https://github.com/jknowles/posse_party/issues/1) | Mastodon, Bluesky, Pixelfed: publish media | Steps 4 to 7; Pixelfed parked |
| [#9](https://github.com/jknowles/posse_party/issues/9) | LinkedIn: post images from post.media natively | Step 8 |
| [#7](https://github.com/jknowles/posse_party/issues/7) | LinkedIn: post loops as looping video | Step 9 |
| [#8](https://github.com/jknowles/posse_party/issues/8) | LinkedIn: route the jaredknowles.com shots feed | Step 10 |

Feed-side issues: jaredknowles.com [#65](https://gitea.civilytics.org/jared/jaredknowles.com/issues/65)
(append settings) and [#61](https://gitea.civilytics.org/jared/jaredknowles.com/issues/61) (media
fields); civilytics.com [#128](https://gitea.civilytics.org/Civilytics/homepage_test/issues/128).

## Order

| Step | Work | Size | Depends on |
| --- | --- | --- | --- |
| 1 | #5: feed fix in both sites, platform-defaults table in `docs/feed.md` | Feed edits, docs | none |
| 2 | #6: one URL per LinkedIn post | Small | none |
| 3 | #4: shared image-fitting PORO; Bluesky card thumbnail uses it | Small | none |
| 4 | #1 Mastodon images | Small | field names agreed in site #61 |
| 5 | #1 Bluesky images | Medium | 3 |
| 6 | #1 Mastodon video | Medium | 4 |
| 7 | #1 Bluesky video | Largest in #1 | 5 |
| 8 | #9 LinkedIn images | Small to medium | none |
| 9 | #7 LinkedIn loops | Research, then medium | 8 (shares the media-vs-card branch) |
| 10 | #8 route shots feed to LinkedIn | Config | 2, 8, 9, jaredknowles.com #65 |
| — | #1 Pixelfed | Parked | #3, and `feat/pixelfed-platform` merging |

Steps 2, 3, 4 and 8 are independent and can run in parallel.

## Step 1: append settings (#5)

**Cause.** Mastodon, X and Instagram default `append_url: true` (`app/lib/platforms/mastodon.rb`,
`x.rb`, `instagram.rb`). `MungesConfig` merges platform defaults, then account settings, then the
entry, then `platform_overrides`. A feed that sends `append_url_if_truncated` without `append_url`
gets the platform's `true`, and `ComposesCrosspostContent` appends on every post. The composer is
correct; the defaults were undocumented.

**Done here:** `docs/feed.md` has a "Platform defaults" section and a pointer from the
`append_url_if_truncated` row.

**Feed work:**
- jaredknowles.com #65: `"append_url": false` on shots and takes; explicit Mastodon override on
  posts.
- civilytics.com #128: top-level `"append_url": false`, and the Mastodon override on every
  newsletter entry, not only those with a `mastodon.md` sidecar.

**Done 2026-09-28.** jaredknowles.com `211c17e` sends `append_url: false` on takes, shots and posts,
and keeps the permalink on Mastodon for shots and posts through
`platform_overrides.mastodon.append_url: true`. Mastodon shots are text only until step 4, so the
permalink is their only link to the photo. `composes_crosspost_content_test.rb` pins the behavior.

**Carry into steps 4 and 6:** once Mastodon posts shot media, remove the Mastodon override from
the shot profiles in jaredknowles.com, and update its `tests/verify-posse-config.sh` to match.

## Step 2: one URL per LinkedIn post (#6)

**Decided 2026-09-28.** A LinkedIn post carries at most one URL. If the composed text contains a
URL anywhere, not only at the end, PosseParty appends nothing and the article card uses that URL.
The URL stays in the text where it sits. Otherwise the card uses the entry's `url`, as today.

**Today:** `SplitsContentFromOrganicUrl` uses `crosspost_config.url` whenever `attach_link` is on,
and finds a text URL only when it is the last thing in the text. `SyndicatesLinkedinPost` already
scrapes `og:image` when the card URL differs from the entry URL.

**Build:** a LinkedIn-specific splitter (the shared one also serves Facebook, so leave its
behavior alone), plus suppressing `append_url` on LinkedIn when the text already
contains a URL.
- Test: shot summary ending in a URL → no appended permalink, card for that URL.
- Test: URL mid-text → text unchanged, card for that URL.
- Test: no URL in text → card for the entry `url`.
- Test: text URL plus `append_url: true` → nothing appended.

**Built 2026-09-28** (`fix/linkedin-one-url`, `20b1c72`) as `Platforms::Linkedin::LimitsToOneUrl`.
The URL stays in the text as written, including at the end. Only `http(s)://` links count. Known
limit: the card's title and description still come from the entry, not the linked page.

**Consequence for civilytics.com:** a URL in a newsletter's LinkedIn text would move the card off
the post. #128 adds a feed check that keeps that text URL-free.

## Step 3: fit images under a byte limit (#4)

New PORO in `app/lib/` (e.g. `FitsImageWithinByteLimit`) on `ruby-vips`, which is already in the
Gemfile. libvips is already in the Docker image; `LetterboxesImageWithVips` is the precedent. It
downscales to about 1200 px wide, re-encodes JPEG, steps quality down until under the limit, and
returns `Result` with failure when it cannot. `AttachesWebCard#upload_thumbnail!` uses it and omits
`thumb` on failure rather than failing the post. Step 5 reuses it for Bluesky image embeds.

**Built 2026-09-28** (`fix/bsky-fit-thumbnail`, `4c2c81f` and `0cac4a7`) as `FitsImageWithinByteLimit`.
It decodes with `Vips::Image.thumbnail_buffer`, which shrinks while decoding, so a huge image is
never held at full size. It tries JPEG at quality 85, 75, 65 and 50. A failed decode or a missing
libvips leaves the card without a thumbnail. Known gaps: an image narrower than 1200 px that is
still over the limit at quality 50 loses its thumbnail rather than being shrunk further; and no
test exercises `AttachesWebCard`'s fallback, because that would need a recorded Bluesky session
(VCR). The recorded `bsky_shot` cassette confirms that thumbnails under the limit upload
byte-for-byte unchanged.

## Steps 4 to 7: Mastodon and Bluesky media (#1)

Follow the checklist in #1. Agree the `mime`, `width`/`height` and `bytes` field names with
jaredknowles.com #61 before step 4. In brief:
- **Mastodon images:** `/api/v2/media` with `description` from `alt`, up to four `media_ids`.
- **Bluesky images:** `uploadBlob` through step 3's PORO, `app.bsky.embed.images`; no web card
  when media is attached.
- **Mastodon video:** upload, then poll the attachment until processed before posting.
- **Bluesky video:** the video service, `app.bsky.embed.video` with `alt`, `aspectRatio`, and
  `presentation: "gif"` for loops.
- Over a platform's size limit, or on a failed upload: fall back to today's text or card, and log
  why.

## Step 8: LinkedIn images (#9)

Reuse `InitiatesImageUpload` and `UploadsImage`. One image → `content.media`, several →
`content.multiImage`; no article card when media is attached. Check the limits against LinkedIn's
docs first.

## Step 9: LinkedIn loops (#7)

Research against LinkedIn's primary docs before code: does the feed loop native video, and does
the Images API take GIFs? The Docker image has no ffmpeg, so the GIF route adds a system
dependency. Native video is the default unless it fails to loop.

## Step 10: shots feed to LinkedIn (#8)

Configuration once 2, 8 and 9 land and jaredknowles.com #65 ships. Open decision (yours):
auto-publish, or queue for approval like blog posts.

## Testing

VCR cassettes for every third-party call (`AGENTS.md`), secrets scrubbed; Mocktail for internal
collaborators. Offline fixture images and one short MP4 under `test/fixtures/files/`.

## Upstream

Steps 3 to 7 are generic enough for `searlsco/posse_party`. Keep each on its own branch, free of
fork-only changes, so it can go upstream as a PR.
