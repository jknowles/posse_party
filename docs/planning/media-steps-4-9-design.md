# Native media on LinkedIn, Mastodon and Bluesky — Design Spec (media plan steps 4–9)

**Date:** 2026-10-01
**Status:** Draft — awaiting review
**Author:** Jared Knowles, PhD (with Claude)
**Plan this refines:** `docs/planning/media.md` (this branch), steps 4–9
**Consumers:** civilytics.com's social feed (`Civilytics/homepage_test`, spec
`docs/superpowers/specs/2026-09-30-social-feed-design.md` there) and jaredknowles.com's
shots feed (`jared/jaredknowles.com` #61)

---

## 1. Goal

Post the images, GIFs and video a feed sends in `media` natively on LinkedIn, Mastodon
and Bluesky, the way Instagram already does, without ever failing a crosspost because of
its media.

What each site needs:

| Step | Work | civilytics.com | jaredknowles.com |
|---|---|---|---|
| 8 | LinkedIn images (a GIF is an image there) | GIFs, stills | photos |
| 4 | Mastodon images (Mastodon converts GIFs) | GIFs, stills | photos |
| 5 | Bluesky images | stills | photos |
| 7 | Bluesky video, `presentation: "gif"` | GIFs (sent as the MP4) | loops, clips |
| 6 | Mastodon video | — | loops, clips |
| 9 | LinkedIn native video | — | loops, clips |

## 2. Decisions taken in brainstorming (2026-10-01)

| Decision | Choice |
|---|---|
| Scope | Steps 4 to 9. Pixelfed video stays parked; step 10 (route the shots feed to LinkedIn) stays separate |
| Recording cassettes | Against the real accounts PosseParty uses, each post deleted right after; every session approved first (§10) |
| Deploy | Three waves: (1) step 8; (2) steps 4 and 5; (3) steps 7, 6, 9. Each a `test/deploy-YYYYMMDD` plus one real post checked |
| Waiting on processing | Inline up to about 60 s, then the existing finish-later path (`needs_to_finish?` / `finish!`) with upload IDs in `crosspost.metadata` |
| Media failure | Never fails a crosspost: fall back to today's text or link card, record why |
| Bluesky video | The simple route: `uploadBlob` to the PDS and an `app.bsky.embed.video` embed. The video-service route is a later upgrade |
| LinkedIn loops | Native video; the step 9 recording checks whether LinkedIn repeats a short silent video. If it does not, jaredknowles.com sends LinkedIn a GIF as civilytics.com does (a site issue, not a fork change) |
| Mastodon status post | Carries an `Idempotency-Key` derived from the crosspost ID |

## 3. What exists (fork at `test/deploy-20260928`, `0c1624f`)

- **No adapter reads per-platform media.** Instagram (`instagram.rb:36`,
  `translates_instagram_post.rb:4`), YouTube and Pixelfed read `crosspost.post.media`.
  `MungesConfig` (`publishes_crosspost/munges_config.rb:4-29`) already merges
  `platform_overrides[tag].media` into `crosspost_config.media`, an Array of string-keyed
  hashes; nothing uses it. Item keys pass through unvalidated
  (`fetches_feed/applies_post_overrides.rb:14`).
- **Adapter entry points.** `Mastodon#publish!` drops `crosspost_config`
  (`mastodon.rb:31-33`); LinkedIn passes only the content string (`linkedin.rb:33-35`);
  Bluesky passes the config.
- **LinkedIn** (`linkedin/*.rb`): person URN only; API version `202605`
  (`calls_linkedin_api.rb:8-12`); `UploadsImage` PUTs every file as `image/jpeg`
  (`uploads_image.rb:12`); `PublishesPost#build_post_data` can only build an `article`
  card, and `crosspost_config.summary.truncate` raises when `summary` is nil
  (`publishes_post.rb:42-66`); `LimitsToOneUrl` turns a trailing URL into a card even
  with `attach_link: false` (`limits_to_one_url.rb:15-28`).
- **Mastodon** (`mastodon/syndicates_mastodon_post.rb`): one `POST /api/v1/statuses`
  with `{status}`; no media, no idempotency key.
- **Bluesky** (`bsky/*.rb`): PDS hard-coded to `https://bsky.social`; `bskyrb 0.5.3`
  (2023) has no service auth or video; `AttachesWebCard` uploads a blob itself and
  downloads with `Net::HTTP.get_response`, which does not follow redirects
  (`attaches_web_card.rb:49`); `FitsImageWithinByteLimit` re-encodes to JPEG and is not
  animation-aware.
- **Errors and retries.** Adapters end in a bare `rescue => e`, which turns
  `UnretriableError` and `RecoverableError` into retriable failures. A failed crosspost
  is retried immediately, up to 6 attempts, under a 10-minute job timeout
  (`publish_crosspost_job.rb`). Only Instagram uses `needs_to_finish?` / `finish!`
  (30 s re-checks for 24 h, state in `crosspost.metadata`).
- **No shared downloader**, no size guard, no fixture GIF or MP4, no ffmpeg in the image.
- **Deploy.** Built on maxwell from a `git archive` per the gitignored
  `maxwell-deploy.local.md`. `docker-compose.yml` defaults to
  `ghcr.io/searlsco/posse_party:latest` unless `POSSE_IMAGE` is set inline.

## 4. Platform facts (checked against primary sources 2026-09-30/10-01)

| Platform | Images | GIF | Video | Alt | Source |
|---|---|---|---|---|---|
| LinkedIn | Images API: JPG, GIF, PNG; < 36,152,320 px. One image `content.media`, 2–20 `content.multiImage` | accepted as an image, ≤ 250 frames | Videos API: MP4, 3 s–30 min, 75 KB–500 MB; `initializeUpload` → 4 MB part PUTs (ETags) → optional thumbnail PUT → `finalizeUpload`; poll until `AVAILABLE` before posting | `altText` ≤ 4,086 | learn.microsoft.com images-api, multiimage-post-api, videos-api (li-lms-2026-09) |
| Mastodon | `POST /api/v2/media` (`file`, `description`); 200 = ready, 202 = processing, poll `GET /api/v1/media/:id`; ≤ 4 per status | ≤ 16 MB, converted to `gifv`; one per status | ≤ 99 MB (instance-dependent); a video with no audio track becomes `gifv` (`lib/paperclip/transcoder.rb:118-120`) | `description` | docs.joinmastodon.org; mastodon/mastodon source |
| Bluesky | `app.bsky.embed.images`: ≤ 4, ≤ 2,000,000 bytes each, `alt` required, `aspectRatio` optional | shows static as an image | `app.bsky.embed.video` (`video/mp4`, ≤ 300 MB, `alt`, `aspectRatio`, `presentation: gif`); simple route `uploadBlob` + embed, processed after posting | `alt` | atproto lexicons `embed/images.json`, `embed/video.json`; bsky-docs `tutorials/video.mdx` |

The media plan's 1,000,000-byte Bluesky image limit is out of date; the lexicon now says
2,000,000.

## 5. The contract (piece 1): `docs/feed.md`

Branch `docs/media-contract` off `main`. The media-item table gains:

| Field | Type | Meaning |
|---|---|---|
| `alt` | string | alt text; Mastodon `description`, LinkedIn `altText`, Bluesky `alt` |
| `presentation` | `"gif"` | on a silent loop; Bluesky video embed hint |
| `mime` | string | `image/gif`, `image/png`, `image/jpeg`, `image/webp`, `video/mp4`; preferred over the download's `Content-Type` |
| `width`, `height` | integer px | aspect ratio for Bluesky; optional for images (read from the file when absent) |
| `bytes` | integer | lets a publisher skip a file over a platform limit before downloading |

And a note: `media` can be set inside `platform_overrides.<tag>`, replacing the top-level
list for that platform; LinkedIn, Mastodon, Bluesky and Instagram read the merged list.
The names match jaredknowles.com #61 and what civilytics.com's feed already sends.

## 6. The foundation

Branch `feat/media-foundation` off `main`; every step branches from it.

**Read the merged list.** New code reads `crosspost_config.media`. Instagram switches from
`crosspost.post.media` to `crosspost_config.media` (one call site plus a test): it is how
civilytics.com's per-platform JPEGs reach Instagram, which takes nothing else. YouTube
and Pixelfed are unchanged.

**`MediaItem`** (`app/lib/media_item.rb`): `Struct.new(:type, :url, :poster_url, :alt,
:presentation, :mime, :width, :height, :bytes, keyword_init: true)`, with
`video?`/`image?`. **`ParsesMediaItems#parse(raw)`** returns `[MediaItem]` from the stored
hashes, dropping items without a `type` of image/video or an `http(s)` `url`.

**`DownloadsMedia`** (`app/lib/downloads_media.rb`):
- `download(item, max_bytes:) -> Result` with `Downloaded = Struct.new(:bytes,
  :content_type)`, for images: follows redirects (HTTParty), refuses when `item.bytes`
  or `Content-Length` is over `max_bytes`, stops reading past it otherwise, takes the
  content type from `item.mime`, then the response header (parameters stripped), then
  `Marcel`.
- `download_to_tempfile(item, max_bytes:) -> Result` with `DownloadedFile =
  Struct.new(:path, :size, :content_type)`, for video: streams to a `Tempfile`
  (YouTube's `DownloadsVideo` is the precedent). The caller unlinks it.

**Choosing what to post.** `SelectsMedia#select(items, limits)` returns either one video
item (when any item is video), up to the platform's image count, or nothing. Items beyond
a count are dropped, and the drop is recorded like a fallback.

**Never fail on media.** Uploaders raise `MediaUnavailable` (a `StandardError` subclass
in `app/lib/media_unavailable.rb`) with the reason. Each adapter catches it around its
media step only, records it, and continues on today's path (text, link card or appended
URL). `RecordsMediaFallback#record(crosspost, reason)` merges
`{"media_fallback" => {"reason" => reason, "at" => Now.time.iso8601}}` into
`crosspost.metadata` and logs a warning. The existing bare `rescue` blocks are unchanged.

**Waiting.** `WaitsForProcessing#wait(timeout: 60, interval: 3) { ready? }` polls inline.
When it runs out, the adapter stores what it needs to finish in `crosspost.metadata`
(below), returns `Result.new(success?: true, needs_to_finish?: true)`, and the platform
class turns `finishable?` true; `finish!(crosspost)` re-checks and posts, or asks to
finish again. If processing fails outright, `finish!` posts the fallback. The existing
24 h window and `RequeueAbandonedWipCrosspostsJob` bound it. Retries after a failed post
re-upload images (cheap); video IDs live in metadata and are reused.

## 7. LinkedIn (steps 8, 9)

**Step 8** (`feat/linkedin-images`):
- `Linkedin#publish!` passes `crosspost_config` through.
- Image items (≤ 20) are downloaded (cap 20 MB each) and uploaded through
  `InitiatesImageUpload` and `UploadsImage`, which now takes and sends the real
  `content_type`.
- `PublishesPost#build_post_data` gains `media_urns:`: one becomes
  `content: {media: {id:, altText:}}`, several `content: {multiImage: {images: [{id:,
  altText:}]}}`. With media there is no `article`.
- With media, `LimitsToOneUrl` is skipped: the composed text, appended URL included, is
  the commentary, and LinkedIn links the URL.
- `build_post_data` guards `summary` being nil (adjacent crash).
- A video item falls back to today's card until step 9.

**Step 9** (`feat/linkedin-video`, off `linkedin-images`):
- One video item, `download_to_tempfile` (75 KB–500 MB, checked by `bytes` then size).
- `InitiatesVideoUpload` (`rest/videos?action=initializeUpload`, `owner`,
  `fileSizeBytes`, `uploadThumbnail` when `poster_url`), `UploadsVideoParts` (PUT each
  `firstByte..lastByte` slice, collect `ETag`), thumbnail PUT (`media-type-family:
  STILLIMAGE`), `FinalizesVideoUpload` (`uploadToken`, `uploadedPartIds`).
- Poll `GET rest/videos/{urn}` until `AVAILABLE`; post `content: {media: {id: urn}}`
  (plus `title` if the recording shows it is required).
- Finish later: `metadata["linkedin_video"] = {"urn", "commentary"}`.
  `PROCESSING_FAILED` falls back to the card.
- The recording checks whether LinkedIn repeats a silent loop.

## 8. Mastodon (steps 4, 6)

**Step 4** (`feat/mastodon-images`):
- `Mastodon#publish!` passes `crosspost_config` through.
- Up to 4 stills or one GIF: `UploadsMastodonMedia` posts each to `POST /api/v2/media`
  (multipart `file`, `description` from `alt`; download cap 16 MB). 200 gives a ready
  ID; 202 means poll `GET /api/v1/media/:id` until `url` is present.
- `POST /api/v1/statuses` with `status`, `media_ids`, and `Idempotency-Key:
  posse-party-crosspost-<id>`.
- Finish later: `metadata["mastodon_media"] = {"ids", "status"}`.
- A rejected upload (413/422) falls back to text with the appended URL.

**Step 6** (`feat/mastodon-video`, off `mastodon-images`): the MP4 through the same
endpoint (`download_to_tempfile`, cap 99 MB), always polled. A silent loop becomes `gifv`
on Mastodon's side; `poster_url` is not used.

## 9. Bluesky (steps 5, 7)

**Step 5** (`feat/bsky-images`):
- `UploadsBskyBlob#upload(bytes_or_io, content_type, record_manager) -> blob` is
  extracted from `AttachesWebCard`, which then uses it and downloads `og_image` through
  `DownloadsMedia` (so it follows redirects).
- Up to 4 images, each through `FitsImageWithinByteLimit` at 2,000,000 bytes, uploaded,
  and embedded as `app.bsky.embed.images` with `alt` and `aspectRatio` (from
  `width`/`height`, or read from the image header with libvips).
- With media there is no web card; the link is the appended 🔗.

**Step 7** (`feat/bsky-video`, off `bsky-images`): one video item, `download_to_tempfile`
(cap 100 MB), uploaded as `video/mp4` through `UploadsBskyBlob`, embedded as
`app.bsky.embed.video` with `alt`, `aspectRatio` when known, and `presentation: "gif"`
when set. No polling: Bluesky processes after posting. A failed upload (unverified
email, daily limit, size) falls back. The video-service route (service token for the
account's real PDS, `video.bsky.app` upload, job polling) is a later upgrade.

## 10. Testing and recording

- **Fixtures:** a tiny JPEG, PNG, animated GIF and silent MP4 in `test/fixtures/files/`,
  referenced by their GitHub raw URLs on this fork.
- **Unit tests** for every new PORO with Mocktail collaborators, covering every fallback
  (uploads forced to fail) and every finish-later sequence.
- **Platform tests** through `PublishesCrosspost` with a media feed fixture and one VCR
  cassette per upload path (`perfect_vcr_match`).
- **The full suite** with `CI=true ./script/test`, and `standardrb`.
- **Recording sessions** (real accounts, approved first, posts deleted straight after,
  secrets scrubbed with `vcr_secrets` and grepped for before commit). One-time: cassettes
  replay offline after, and are re-recorded only when a request's shape changes.

| Wave | Session | Posts |
|---|---|---|
| 1 | LinkedIn | 1 image, 1 multi-image, 1 GIF |
| 2 | Mastodon | 1 multi-image, 1 GIF |
| 2 | Bluesky | 1 multi-image |
| 3 | Bluesky | 1 loop video |
| 3 | Mastodon | 1 loop, 1 clip |
| 3 | LinkedIn | 1 loop, 1 clip; Jared checks the loop repeats before deletion |

## 11. Branches, waves, deploy

1. Fast-forward `main` to `upstream/main`.
2. Branches: `docs/media-contract`, `feat/media-foundation` (off `main`); the six step
   branches off the foundation, each video step off its image step.
3. Each wave: a fresh `test/deploy-YYYYMMDD` off `main`, merging every branch in today's
   deploy (`fix/linkedin-one-url`, `fix/bsky-fit-thumbnail`, `docs/platform-defaults`,
   `feat/linkedin-page`, `feat/pixelfed-platform`) plus the wave's branches; built on
   maxwell per `maxwell-deploy.local.md`; `pg_dump` first; `POSSE_IMAGE=<tag> docker
   compose up -d`.
4. Each wave ends with one real crosspost Jared checks. Wave 1's is a civilytics.com
   social post with a GIF to LinkedIn, after homepage_test PR #129 reaches `main`.
5. **maxwell trap:** a bare `docker compose up -d` reverts to upstream's image. Put
   `POSSE_IMAGE` in the sealed `.env` (drafted for Jared to apply in
   `maxwell_docker_compose`).

## 12. Documentation and follow-ups

- `docs/planning/media.md` (this branch): status, the amendments in this spec, a pointer
  here.
- `docs/feed.md`: §5.
- homepage_test `docs/posse-party.md`: the line "PosseParty posts media only to Instagram"
  updated after each wave.
- jaredknowles.com #61: a comment that image `width`/`height` are now optional.
- Upstream PRs to searlsco: Jared's call; tracked in #10.

## 13. Out of scope

Pixelfed video; step 10; the Bluesky video-service route; LinkedIn company pages
(`feat/linkedin-page`); captions; per-account copy; Threads, Facebook and X media.

## 14. Risks

| Risk | Mitigation |
|---|---|
| A cassette records a real post that is not deleted | Deletion is part of each approved session; the session checklist confirms it |
| Secrets in a committed cassette | `vcr_secrets` plus a grep for tokens and passwords before commit |
| LinkedIn does not loop native video | The recording checks; fallback is a site-side GIF |
| Bluesky simple-route video shows "processing" briefly | Accepted; the video-service upgrade is recorded |
| A long video upload hits the 10-minute job timeout | Finish-later path after 60 s; video IDs reused, not re-uploaded |
| Downloading large files into memory | Video streams to a tempfile; images are capped |
| Upstream moves under the step branches | Fast-forward `main` first; branches stay upstream-clean |
| maxwell reverts to upstream's image | `POSSE_IMAGE` in the sealed `.env` |
