# Media wave 1 (contract, foundation, LinkedIn images) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** LinkedIn posts the images and GIFs a feed sends in `media`, in place of the link card, and
Instagram reads the per-platform `media` list, without a media problem ever failing a crosspost.

**Architecture:** Three stacked branches. `docs/media-contract` documents the new media-item fields.
`feat/media-foundation` adds the shared pieces every platform step uses: parse items, choose what to
post, download with a size cap, record a fallback. `feat/linkedin-images` adds `UploadsMedia`, which
turns items into LinkedIn image URNs or records why it could not, and teaches `PublishesPost` to send
`content.media` or `content.multiImage`. Then one recording session, one deploy to maxwell, and one
real post that Jared checks.

**Tech Stack:** Ruby 3.4.8, Rails, Minitest, Mocktail, VCR and WebMock, HTTParty, Marcel. Tests run in
Docker (`postgres:17-alpine`, plus a `ruby:3.4.8` image with Node 22 and Playwright Chromium).

**Spec:** `docs/planning/media-steps-4-9-design.md` (branch `docs/media-plan`). Its sections 5, 6, 7
(step 8), 10 and 11 are the ones this wave implements. The executor reads both documents.

**Verified before writing:** every code block below was run in a scratch worktree off `main`
(`de502b2`). The three branches together pass `CI=true ./script/test` (371 tests, 24 system tests).
Merged into today's deploy tree they pass it too (401 tests, 24 system tests). The recorded tests in
Task 8 fail until their cassettes exist, as expected.

## Global Constraints

- Fork conventions (`AGENTS.md`):
  - POROs live in `app/lib`, take no `initialize` arguments, and build their collaborators as ivars.
  - Return `Result`, `Outcome` or a Struct.
  - Tests are named as methods and contain no loops, branching or metaprogramming.
  - No `attr_reader`, no empty initializers, no dead code.
- Media never fails a crosspost. A media problem posts today's text or link card and records
  `{"media_fallback" => {"reason", "at"}}` in `crosspost.metadata` (spec §6).
- LinkedIn image limits: JPEG, PNG or GIF; at most 20 per post; a 20 MB cap per file in this fork;
  `altText` at most 4,086 characters (spec §4, §7).
- `LinkedIn-Version` stays `202605`.
- The foundation holds only what wave 1 uses. `WaitsForProcessing` and `download_to_tempfile` come
  with waves 2 and 3.
- Step branches stay upstream-clean, with no fork-only files. `maxwell-deploy.local.md` is never
  committed.
- Recording sessions:
  - real account, approved by Jared first;
  - every post deleted straight after;
  - secrets only in environment variables, never in a file or the transcript;
  - cassettes grepped before commit.
- Jared's standing rule: commit as each task says, but every push, deploy, comment or issue change
  stops for his approval first.
- Commit messages follow the fork: conventional prefix, a body that says what changed and why, and
  the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

These five inputs are the ones most likely to reach the code from a real feed without the spec
naming them. Each now has a test in the owning task.

1. **A platform override whose `media` is not a list** (a string, say) should read as no media, not
   crash Instagram. Pinned by `test_empties_override_media_that_is_not_a_list` (Task 4).
2. **A media file served as `application/octet-stream` with no `mime`**, the default on S3 and R2,
   should be identified from its bytes. Pinned by
   `test_sniffs_the_bytes_behind_a_generic_content_type` (Task 3).
3. **A WebP image, or any video, sent to LinkedIn** should post the link card and record why. Pinned
   by `test_a_type_linkedin_does_not_take_falls_back` and
   `test_a_video_falls_back_until_linkedin_video_ships` (Task 6).
4. **More than 20 images** should post the first 20 and record the drop. Pinned by
   `test_images_past_twenty_are_dropped_and_recorded` (Task 6).
5. **Alt text longer than LinkedIn's 4,086 characters** should be truncated, not rejected. Pinned by
   `test_truncates_alt_text_to_linkedins_limit` (Task 7).

## Rulings made while verifying (carry these; do not re-decide)

- `PublishesPost` takes `media:` (a list of `UploadsMedia::Uploaded`, each an `urn` and its `alt`),
  where the spec said `media_urns:`. Alt text travels with the URN.
- `SelectsMedia#select(items, max_images:)` takes a keyword where the spec wrote `limits`. Video
  limits arrive with the video steps.
- `feat/media-foundation` branches from `docs/media-contract`, not from `main`. Both edit
  `docs/feed.md`, and stacking them keeps every deploy merge free of conflicts. Upstream would take
  the contract PR first.
- `AppliesPostOverrides` gains a guard that a platform override's `media` must be a list. The guard
  that exists at that boundary covers only the top-level `media`, and the spec makes override
  `media` part of the contract.
- `DownloadsMedia` and `UploadsImage#upload_bytes` test their error branches with WebMock, not VCR.
  Oversize bodies, timeouts and 404s cannot be recorded on demand, and `instagram_test.rb:82`
  already stubs a media host this way. The LinkedIn happy paths are recorded with VCR in Task 8.
- `UploadsImage#upload_bytes` rescues network errors into an `Outcome.failure`, so a timeout on an
  upload falls back instead of failing the post. The og-image thumbnail path, which now delegates
  to it, gains the same behavior: a card without a thumbnail rather than a failed post.
- The silent MP4 fixture the spec lists in §10 comes with the first wave that posts video. Wave 1
  adds the JPEG, PNG and GIF it records with.
- The wave-1 deploy branch merges `test/deploy-20260928` rather than re-merging its five branches.
  An octopus merge of those five conflicts in `docs/feed.md` (`fix/linkedin-one-url` against
  `fix/bsky-fit-thumbnail`, adjacent lines), and `0c1624f` already holds the resolution.

## Not in this plan

- Mastodon and Bluesky, all video, `WaitsForProcessing`, `download_to_tempfile`: waves 2 and 3.
- **A post LinkedIn rejects after its uploads succeed fails as it does today.** It does not retry
  without media; spec §6 scopes the fallback to the media step. The Task 8 recording shows whether
  LinkedIn accepts an image the moment it is uploaded.
- **The fallback reason is not shown in the UI.** `crosspost.metadata` appears on no page, so it is
  read from the Rails log or a console. Parked; raise it with Jared as a follow-up issue.

---

### Task 0: Prepare the worktree and the test environment

No commits. Everything here is local.

**Files:**
- Create (outside the repo): `~/.cache/posse-test/Dockerfile`, `~/.cache/posse-test/rt.sh`
- Create: worktree `/tmp/posse-wave1`

**Interfaces:**
- Produces: `~/.cache/posse-test/rt.sh`, which runs one command in the test container against
  `/tmp/posse-wave1`. Every later `rt "<command>"` means `~/.cache/posse-test/rt.sh "<command>"`.
  Each Bash call starts a fresh shell, so write the full path, not an alias.

- [ ] **Step 1: Check that upstream has not moved**

```bash
cd /home/jared/Nextcloud/Civilytics/Code/jknowles/posse_party
git fetch upstream && git fetch origin
git rev-list --count main..upstream/main
git rev-parse --short main origin/main
```

Expected: `0`, and both SHAs `de502b2`. If the count is not 0, **stop and ask Jared**. Moving `main`
means pushing it to `origin`, and `fix/linkedin-one-url` would need re-checking against the new
base.

- [ ] **Step 2: Create the worktree on the first branch**

The checkout lives in Nextcloud, whose file-mode noise should stay out of the work, so the branches
are built in `/tmp`.

```bash
git worktree add -b docs/media-contract /tmp/posse-wave1 main
```

Expected: `Preparing worktree (new branch 'docs/media-contract')`.

- [ ] **Step 3: Build the test image**

The host has no Ruby 3.4.8. This image adds what the fork's CI installs: libvips, libidn, Node 22,
Yarn 1 and Playwright's Chromium, which the system tests need.

```bash
mkdir -p ~/.cache/posse-test
cat > ~/.cache/posse-test/Dockerfile <<'EOF'
FROM node:22-bookworm-slim AS node

FROM ruby:3.4.8
RUN apt-get update -qq && apt-get install -y --no-install-recommends libpq-dev libvips42 postgresql-client libyaml-dev libidn-dev libidn12 && rm -rf /var/lib/apt/lists/*
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=node /opt /opt
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
 && ln -s /opt/yarn-v*/bin/yarn /usr/local/bin/yarn \
 && npx -y playwright@1.57.0 install --with-deps chromium
ENV BUNDLE_PATH=/gems BUNDLE_WITHOUT=""
WORKDIR /app
EOF
docker build -q -t posse-test-ruby ~/.cache/posse-test
```

Expected: a `sha256:` image ID. If `posse-test-ruby` already exists from the planning session, the
build reuses its layers.

- [ ] **Step 4: Start Postgres and write the runner**

```bash
docker network inspect posse-test >/dev/null 2>&1 || docker network create posse-test
docker volume inspect posse-test-gems >/dev/null 2>&1 || docker volume create posse-test-gems
docker inspect posse-test-db >/dev/null 2>&1 || docker run -d --name posse-test-db --network posse-test -e POSTGRES_PASSWORD=postgres postgres:17-alpine
docker start posse-test-db
cat > ~/.cache/posse-test/rt.sh <<'EOF'
#!/bin/sh
# Runs one command in the fork's test environment against the worktree at $POSSE_TREE
# (default /tmp/posse-wave1), then hands every file the container wrote back to you.
exec docker run --rm --network posse-test -v "${POSSE_TREE:-/tmp/posse-wave1}:/app" -v posse-test-gems:/gems \
  -e DATABASE_URL=postgres://postgres:postgres@posse-test-db/posse_party_test \
  -e RAILS_ENV=test -e CI=true -e LINKEDIN_ACCESS_TOKEN -e LINKEDIN_PERSON_URN \
  posse-test-ruby sh -c "$*; s=\$?; chown -R $(id -u):$(id -g) /app; exit \$s"
EOF
chmod +x ~/.cache/posse-test/rt.sh
```

The container runs as root, and the `chown` returns the files it writes to you. Without it, a
fixture written by the container blocks a later `git merge`. `-e LINKEDIN_ACCESS_TOKEN` passes the
variable through only if your shell has it set; nothing is written to disk.

- [ ] **Step 5: Install dependencies and prepare the database**

```bash
rt "bundle install --quiet && yarn install --frozen-lockfile --silent && bin/rails db:prepare"
rt "bin/rails test test/lib"
```

Expected: the last line reads `253 runs, ... 0 failures, 0 errors, 0 skips`.

---

### Task 1: The media contract in `docs/feed.md`

Branch `docs/media-contract` (created in Task 0). Documentation only: the check is the diff, not a
test run.

**Files:**
- Modify: `docs/feed.md` (the `### media Item` table, around line 157)

**Interfaces:**
- Produces: the documented item fields `alt`, `presentation`, `mime`, `width`, `height`, `bytes`,
  which `ParsesMediaItems` (Task 2) reads.

- [ ] **Step 1: Add the fields and the override note**

In `docs/feed.md`, replace:

```markdown
| `poster_url` | string (URL) | Optional cover/thumbnail image used by platforms that support custom posters (for example Instagram Reels covers and YouTube thumbnails). |
```

with:

```markdown
| `poster_url` | string (URL) | Optional cover/thumbnail image used by platforms that support custom posters (for example Instagram Reels covers and YouTube thumbnails). |
| `alt` | string | Alt text describing the image or video. |
| `presentation` | string | `"gif"` marks a short silent video meant to loop like a GIF. |
| `mime` | string | The file's media type, such as `image/gif` or `video/mp4`. Used in place of the `Content-Type` the file's server sends. |
| `width`, `height` | integer | Pixel dimensions, for platforms that need an aspect ratio. Optional. |
| `bytes` | integer | File size, so a platform can skip a file over its limit without downloading it. |

`media` can also be set inside `platform_overrides.<tag>`. The override replaces the top-level list on that platform, so one entry can send Instagram a JPEG still and LinkedIn the animated GIF. YouTube reads only the top-level list.
```

- [ ] **Step 2: Check the diff**

Run: `git -C /tmp/posse-wave1 diff --stat`
Expected: `docs/feed.md | 7 +++++++`. Read the rendered table once in a Markdown preview: six rows
under `poster_url`, then the paragraph, then `## Precedence`.

- [ ] **Step 3: Commit**

```bash
cd /tmp/posse-wave1
git add docs/feed.md
git commit -F - <<'EOF'
docs: document alt, presentation, mime, size and override media

The media item gains the fields a platform needs to post an image or video
natively: alt text, a GIF-like presentation hint for silent loops, the
file's media type, its pixel dimensions and its size. A platform override
can carry its own media list, so one entry can send each platform the file
it takes.

The names match what jaredknowles.com and civilytics.com already send.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 2: Media items, selection and fallback records

Branch `feat/media-foundation`, created from `docs/media-contract`.

**Files:**
- Create: `app/lib/media_item.rb`, `app/lib/parses_media_items.rb`, `app/lib/selects_media.rb`,
  `app/lib/media_unavailable.rb`, `app/lib/records_media_fallback.rb`
- Test: `test/lib/parses_media_items_test.rb`, `test/lib/selects_media_test.rb`,
  `test/lib/records_media_fallback_test.rb`

**Interfaces:**
- Produces:
  - `MediaItem` (Struct, keyword_init): `type, url, poster_url, alt, presentation, mime, width,
    height, bytes`, with `#image?` and `#video?`.
  - `ParsesMediaItems#parse(raw) -> [MediaItem]`:
    - drops anything that is not a Hash with `type` `image` or `video` and an `http(s)` `url`;
    - `alt` defaults to `""`;
    - `width`, `height` and `bytes` are kept only when they are positive Integers.
  - `SelectsMedia#select(items, max_images:) -> SelectsMedia::Selection` (`images`, `video`,
    `dropped`, `#empty?`). Any video wins and takes the selection alone. Otherwise up to
    `max_images` images. `dropped` counts the rest.
  - `MediaUnavailable < StandardError`.
  - `RecordsMediaFallback#record(crosspost, reason)` merges
    `"media_fallback" => {"reason" => reason, "at" => Now.time.iso8601}` into `crosspost.metadata`
    and logs a warning.

- [ ] **Step 1: Create the branch**

```bash
cd /tmp/posse-wave1 && git switch -c feat/media-foundation docs/media-contract
```

- [ ] **Step 2: Write the failing tests**

`test/lib/parses_media_items_test.rb`:

```ruby
require "test_helper"

class ParsesMediaItemsTest < ActiveSupport::TestCase
  def setup
    @subject = ParsesMediaItems.new
  end

  def test_reads_every_contract_field
    items = @subject.parse([{
      "type" => "video", "url" => "https://example.com/loop.mp4",
      "poster_url" => "https://example.com/loop.jpg", "alt" => "A map",
      "presentation" => "gif", "mime" => "video/mp4",
      "width" => 800, "height" => 600, "bytes" => 612_345
    }])

    assert_equal [MediaItem.new(
      type: "video", url: "https://example.com/loop.mp4",
      poster_url: "https://example.com/loop.jpg", alt: "A map", presentation: "gif",
      mime: "video/mp4", width: 800, height: 600, bytes: 612_345
    )], items
    assert items.first.video?
  end

  def test_keeps_only_image_and_video_items_with_http_urls
    items = @subject.parse([
      {"type" => "image", "url" => "https://example.com/a.png"},
      {"type" => "audio", "url" => "https://example.com/a.mp3"},
      {"type" => "image", "url" => "ftp://example.com/a.png"},
      {"type" => "image"},
      "https://example.com/bare.png"
    ])

    assert_equal ["https://example.com/a.png"], items.map(&:url)
  end

  def test_drops_numbers_that_are_not_positive_integers
    item = @subject.parse([{
      "type" => "image", "url" => "https://example.com/a.png",
      "width" => "800", "height" => 0, "bytes" => -1
    }]).first

    assert_nil item.width
    assert_nil item.height
    assert_nil item.bytes
  end

  def test_missing_alt_is_an_empty_string
    assert_equal "", @subject.parse([{"type" => "image", "url" => "https://example.com/a.png"}]).first.alt
  end

  def test_nil_parses_to_nothing
    assert_equal [], @subject.parse(nil)
  end
end
```

`test/lib/selects_media_test.rb`:

```ruby
require "test_helper"

class SelectsMediaTest < ActiveSupport::TestCase
  def setup
    @subject = SelectsMedia.new
  end

  def test_takes_images_up_to_the_limit_and_counts_the_rest
    first = MediaItem.new(type: "image", url: "https://example.com/1.png")
    second = MediaItem.new(type: "image", url: "https://example.com/2.png")
    third = MediaItem.new(type: "image", url: "https://example.com/3.png")

    selection = @subject.select([first, second, third], max_images: 2)

    assert_equal [first, second], selection.images
    assert_nil selection.video
    assert_equal 1, selection.dropped
  end

  def test_a_video_wins_over_images
    image = MediaItem.new(type: "image", url: "https://example.com/a.png")
    video = MediaItem.new(type: "video", url: "https://example.com/a.mp4")

    selection = @subject.select([image, video], max_images: 4)

    assert_equal [], selection.images
    assert_equal video, selection.video
    assert_equal 1, selection.dropped
  end

  def test_nothing_selects_nothing
    selection = @subject.select([], max_images: 4)

    assert selection.empty?
  end
end
```

`test/lib/records_media_fallback_test.rb` (the test helper's teardown already calls `Now.reset!`):

```ruby
require "test_helper"

class RecordsMediaFallbackTest < ActiveSupport::TestCase
  def test_records_the_reason_in_the_crosspost_metadata
    crosspost = crossposts(:admin_bsky_crosspost)
    crosspost.update!(metadata: {"post" => "kept"})
    Now.override!(Time.zone.parse("2026-10-06 10:00:00 UTC"), freeze: true)

    RecordsMediaFallback.new.record(crosspost, "LinkedIn takes JPEG, PNG and GIF, not image/webp")

    assert_equal({
      "post" => "kept",
      "media_fallback" => {"reason" => "LinkedIn takes JPEG, PNG and GIF, not image/webp", "at" => "2026-10-06T10:00:00Z"}
    }, crosspost.reload.metadata)
  end
end
```

- [ ] **Step 3: Run them to see them fail**

Run: `rt "bin/rails test test/lib/parses_media_items_test.rb test/lib/selects_media_test.rb test/lib/records_media_fallback_test.rb"`
Expected: `9 runs, 0 assertions, 0 failures, 9 errors`, each a `NameError: uninitialized constant`
for `ParsesMediaItems`, `SelectsMedia` or `RecordsMediaFallback`.

- [ ] **Step 4: Write the implementation**

`app/lib/media_item.rb`:

```ruby
MediaItem = Struct.new(:type, :url, :poster_url, :alt, :presentation, :mime, :width, :height, :bytes, keyword_init: true) do
  def image?
    type == "image"
  end

  def video?
    type == "video"
  end
end
```

`app/lib/parses_media_items.rb`:

```ruby
class ParsesMediaItems
  TYPES = %w[image video].freeze

  def parse(raw)
    Array(raw).filter_map { |item|
      next unless item.is_a?(Hash)
      item = item.stringify_keys
      next unless TYPES.include?(item["type"]) && http_url?(item["url"])

      MediaItem.new(
        type: item["type"],
        url: item["url"],
        poster_url: item["poster_url"].presence,
        alt: item["alt"].to_s,
        presentation: item["presentation"].presence,
        mime: item["mime"].presence,
        width: positive_integer(item["width"]),
        height: positive_integer(item["height"]),
        bytes: positive_integer(item["bytes"])
      )
    }
  end

  private

  def http_url?(url)
    url.is_a?(String) && url.match?(%r{\Ahttps?://}i)
  end

  def positive_integer(value)
    value if value.is_a?(Integer) && value.positive?
  end
end
```

`app/lib/selects_media.rb`:

```ruby
class SelectsMedia
  Selection = Struct.new(:images, :video, :dropped, keyword_init: true) do
    def empty?
      images.empty? && video.nil?
    end
  end

  def select(items, max_images:)
    video = items.find(&:video?)
    if video
      Selection.new(images: [], video:, dropped: items.size - 1)
    else
      images = items.select(&:image?)
      Selection.new(images: images.take(max_images), video: nil, dropped: items.size - [images.size, max_images].min)
    end
  end
end
```

`app/lib/media_unavailable.rb`:

```ruby
class MediaUnavailable < StandardError
end
```

`app/lib/records_media_fallback.rb`:

```ruby
class RecordsMediaFallback
  def record(crosspost, reason)
    crosspost.update!(metadata: crosspost.metadata.merge(
      "media_fallback" => {"reason" => reason, "at" => Now.time.iso8601}
    ))
    Rails.logger.warn("Crosspost #{crosspost.id} posted without media: #{reason}")
  end
end
```

- [ ] **Step 5: Run them to see them pass**

Run: `rt "bin/rails test test/lib/parses_media_items_test.rb test/lib/selects_media_test.rb test/lib/records_media_fallback_test.rb"`
Expected: `9 runs, 16 assertions, 0 failures, 0 errors, 0 skips`.

- [ ] **Step 6: Lint and commit**

Run: `rt "bundle exec standardrb app/lib test/lib"`
Expected: no output.

```bash
cd /tmp/posse-wave1
git add app/lib/media_item.rb app/lib/parses_media_items.rb app/lib/selects_media.rb app/lib/media_unavailable.rb app/lib/records_media_fallback.rb test/lib/parses_media_items_test.rb test/lib/selects_media_test.rb test/lib/records_media_fallback_test.rb
git commit -F - <<'EOF'
feat: parse media items, choose what to post, record a media fallback

The shared pieces each platform's media step uses. ParsesMediaItems turns
the stored media hashes into MediaItems with the contract's fields,
dropping anything without an image or video type and an http(s) URL.
SelectsMedia picks one video, or up to a platform's image count, and
counts what it leaves out. RecordsMediaFallback writes why a post went out
without its media into the crosspost's metadata, and MediaUnavailable is
what an uploader raises to trigger it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 3: Download media with a size cap

Branch `feat/media-foundation`.

**Files:**
- Create: `app/lib/downloads_media.rb`
- Test: `test/lib/downloads_media_test.rb`

**Interfaces:**
- Consumes: `MediaItem` (Task 2), `Result` (`app/lib/result.rb`).
- Produces: `DownloadsMedia#download(item, max_bytes:) -> Result`.
  - Success: `data` is a `DownloadsMedia::Downloaded` (`bytes`, binary String; `content_type`,
    String).
  - Failure: `error` is a sentence naming the URL.
  - The content type comes from `item.mime`, then the response header (parameters stripped, generic
    octet-stream ignored), then Marcel's sniff of the bytes.
  - Refuses without fetching when `item.bytes > max_bytes`, and stops reading when
    `Content-Length` or the body passes `max_bytes`.

- [ ] **Step 1: Write the failing test**

`test/lib/downloads_media_test.rb`:

```ruby
require "test_helper"

class DownloadsMediaTest < ActiveSupport::TestCase
  PNG = "\x89PNG\r\n\x1A\n".b + ("\x00".b * 24)

  def setup
    @subject = DownloadsMedia.new
  end

  def test_downloads_the_bytes_and_prefers_the_items_mime
    stub_request(:get, "https://example.com/a.gif").to_return(status: 200, body: "GIF89a", headers: {"Content-Type" => "application/octet-stream"})

    result = @subject.download(MediaItem.new(type: "image", url: "https://example.com/a.gif", mime: "image/gif"), max_bytes: 100)

    assert result.success?
    assert_equal "GIF89a".b, result.data.bytes
    assert_equal "image/gif", result.data.content_type
  end

  def test_takes_the_content_type_header_without_its_parameters
    stub_request(:get, "https://example.com/a.png").to_return(status: 200, body: PNG, headers: {"Content-Type" => "image/png; charset=binary"})

    result = @subject.download(MediaItem.new(type: "image", url: "https://example.com/a.png"), max_bytes: 100)

    assert_equal "image/png", result.data.content_type
  end

  def test_sniffs_the_bytes_when_nothing_names_a_type
    stub_request(:get, "https://example.com/a").to_return(status: 200, body: PNG)

    result = @subject.download(MediaItem.new(type: "image", url: "https://example.com/a"), max_bytes: 100)

    assert_equal "image/png", result.data.content_type
  end

  def test_sniffs_the_bytes_behind_a_generic_content_type
    stub_request(:get, "https://example.com/a.png").to_return(status: 200, body: PNG, headers: {"Content-Type" => "application/octet-stream"})

    result = @subject.download(MediaItem.new(type: "image", url: "https://example.com/a.png"), max_bytes: 100)

    assert_equal "image/png", result.data.content_type
  end

  def test_follows_redirects
    stub_request(:get, "https://example.com/old.png").to_return(status: 301, headers: {"Location" => "https://cdn.example.com/a.png"})
    stub_request(:get, "https://cdn.example.com/a.png").to_return(status: 200, body: PNG, headers: {"Content-Type" => "image/png"})

    result = @subject.download(MediaItem.new(type: "image", url: "https://example.com/old.png"), max_bytes: 100)

    assert_equal PNG, result.data.bytes
  end

  def test_refuses_an_item_that_declares_too_many_bytes_without_fetching_it
    result = @subject.download(MediaItem.new(type: "image", url: "https://example.com/big.png", bytes: 101), max_bytes: 100)

    assert result.failure?
    assert_equal "https://example.com/big.png is over the 100-byte limit", result.error
    assert_not_requested :get, "https://example.com/big.png"
  end

  def test_refuses_a_response_whose_length_is_over_the_limit
    stub_request(:get, "https://example.com/big.png").to_return(status: 200, body: "x" * 101, headers: {"Content-Length" => "101"})

    result = @subject.download(MediaItem.new(type: "image", url: "https://example.com/big.png"), max_bytes: 100)

    assert_equal "https://example.com/big.png is over the 100-byte limit", result.error
  end

  def test_refuses_a_body_that_runs_past_the_limit
    stub_request(:get, "https://example.com/big.png").to_return(status: 200, body: "x" * 101)

    result = @subject.download(MediaItem.new(type: "image", url: "https://example.com/big.png"), max_bytes: 100)

    assert_equal "https://example.com/big.png is over the 100-byte limit", result.error
  end

  def test_reports_an_http_error
    stub_request(:get, "https://example.com/gone.png").to_return(status: 404, body: "Not Found")

    result = @subject.download(MediaItem.new(type: "image", url: "https://example.com/gone.png"), max_bytes: 100)

    assert_equal "Could not download https://example.com/gone.png: HTTP 404", result.error
  end

  def test_reports_a_connection_error
    stub_request(:get, "https://example.com/a.png").to_timeout

    result = @subject.download(MediaItem.new(type: "image", url: "https://example.com/a.png"), max_bytes: 100)

    assert_match %r{\ACould not download https://example.com/a.png: }, result.error
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `rt "bin/rails test test/lib/downloads_media_test.rb"`
Expected: `10 runs, 0 assertions, 0 failures, 10 errors`, each
`NameError: uninitialized constant DownloadsMediaTest::DownloadsMedia`.

- [ ] **Step 3: Write the implementation**

`app/lib/downloads_media.rb`:

```ruby
class DownloadsMedia
  Downloaded = Struct.new(:bytes, :content_type, keyword_init: true)
  TooLarge = Class.new(StandardError)
  GENERIC_TYPES = %w[application/octet-stream binary/octet-stream].freeze

  def download(item, max_bytes:)
    return Result.failure(too_large(item, max_bytes)) if item.bytes.to_i > max_bytes

    body = +"".b
    response = HTTParty.get(item.url, stream_body: true, follow_redirects: true) do |fragment|
      next unless fragment.code == 200
      raise TooLarge if fragment.http_response.content_length.to_i > max_bytes

      body << fragment
      raise TooLarge if body.bytesize > max_bytes
    end
    return Result.failure("Could not download #{item.url}: HTTP #{response.code}") unless response.code == 200

    Result.success(Downloaded.new(bytes: body, content_type: content_type(item, response, body)))
  rescue TooLarge
    Result.failure(too_large(item, max_bytes))
  rescue => e
    Result.failure("Could not download #{item.url}: #{e.message}")
  end

  private

  def too_large(item, max_bytes)
    "#{item.url} is over the #{max_bytes}-byte limit"
  end

  def content_type(item, response, body)
    item.mime.presence || named_type(response.headers["content-type"]) || Marcel::MimeType.for(StringIO.new(body))
  end

  def named_type(header)
    type = header.to_s.split(";").first.to_s.strip.downcase
    type unless type.blank? || GENERIC_TYPES.include?(type)
  end
end
```

`fragment.code == 200` skips the body of a redirect, which HTTParty also yields while streaming.

- [ ] **Step 4: Run it to see it pass**

Run: `rt "bin/rails test test/lib/downloads_media_test.rb"`
Expected: `10 runs, 15 assertions, 0 failures, 0 errors, 0 skips`.

- [ ] **Step 5: Lint and commit**

Run: `rt "bundle exec standardrb app/lib test/lib"`
Expected: no output.

```bash
cd /tmp/posse-wave1
git add app/lib/downloads_media.rb test/lib/downloads_media_test.rb
git commit -F - <<'EOF'
feat: download media with a size cap and a trustworthy content type

DownloadsMedia fetches an image into memory for a platform to upload. It
follows redirects, refuses a file whose declared size, Content-Length or
body passes the cap, and reports failures as a Result rather than raising.
The content type comes from the item's mime, then the server's header,
then the bytes themselves, so a file served as application/octet-stream
is still identified.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 4: Instagram posts the merged media list

Branch `feat/media-foundation`.

**Files:**
- Modify: `app/lib/fetches_feed/applies_post_overrides.rb:15`
- Modify: `app/lib/platforms/instagram.rb:36`
- Modify: `app/lib/platforms/instagram/translates_instagram_post.rb:2-4`
- Modify: `app/lib/platforms/instagram/publishes_instagram_post.rb:62`
- Create: `test/lib/fetches_feed/applies_post_overrides_test.rb`
- Modify: `test/lib/instagram_test.rb` (two tests before `test_instagram_story_video`)
- Modify: `test/lib/translates_instagram_post_test.rb:26`

**Interfaces:**
- Consumes: `crosspost_config.media`, which `MungesConfig` already merges from
  `platform_overrides[tag]`.
- Produces: `TranslatesInstagramPost#from_crosspost(crosspost, media, channel: "feed")`, where
  `media` is the raw Array of string-keyed hashes.

- [ ] **Step 1: Write the failing tests**

`test/lib/fetches_feed/applies_post_overrides_test.rb`:

```ruby
require "test_helper"

class FetchesFeed
  class AppliesPostOverridesTest < ActiveSupport::TestCase
    setup do
      @subject = AppliesPostOverrides.new
    end

    def test_keeps_media_a_platform_override_lists
      attrs = @subject.apply({}, '{"platform_overrides":{"instagram":{"media":[{"type":"image","url":"https://example.com/a.jpg"}]}}}')

      assert_equal [{type: "image", url: "https://example.com/a.jpg"}], attrs[:platform_overrides][:instagram][:media]
    end

    def test_empties_override_media_that_is_not_a_list
      attrs = @subject.apply({}, '{"platform_overrides":{"instagram":{"media":"https://example.com/a.jpg"}}}')

      assert_equal [], attrs[:platform_overrides][:instagram][:media]
    end

    def test_leaves_an_override_without_media_alone
      attrs = @subject.apply({}, '{"platform_overrides":{"bsky":{"format_string":"{{title}}"}}}')

      assert_equal({format_string: "{{title}}"}, attrs[:platform_overrides][:bsky])
    end
  end
end
```

In `test/lib/instagram_test.rb`, insert before `  def test_instagram_story_video`:

```ruby
  def test_instagram_posts_the_media_its_platform_override_names
    webp_url = "https://example.com/media/map.webp"
    jpg_url = "https://example.com/media/map.jpg"
    post_url = "https://example.com/posts/map"
    stub_request(:get, feed_url)
      .to_return(body: <<~XML, status: 200)
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom" xmlns:posse="https://posseparty.com/2024/Feed">
          <title>Test Feed</title>
          <id>#{feed_url}</id>
          <updated>2026-10-01T00:00:00Z</updated>
          <entry>
            <title>Map</title>
            <id>#{post_url}</id>
            <published>2026-10-01T00:00:00Z</published>
            <updated>2026-10-01T00:00:00Z</updated>
            <link rel="alternate" href="#{post_url}"/>
            <posse:post><![CDATA[{"syndicate":true,"content":"A map","media":[{"type":"image","url":"#{webp_url}"}],"platform_overrides":{"instagram":{"media":[{"type":"image","url":"#{jpg_url}"}]}}}]]></posse:post>
          </entry>
        </feed>
      XML
    feed = @user.feeds.create!(url: feed_url, label: "civilytics.com social - test")
    FetchesFeed.new.fetch!(feed, cache: false)
    crosspost = Crosspost.includes(:account).find_by!(post: Post.find_by!(remote_id: post_url))
    crosspost.update!(status: "wip")
    calls_instagram_api = Mocktail.of_next(Platforms::Instagram::CallsInstagramApi)
    stubs { |m| calls_instagram_api.call(method: :post, path: "SOME_USER_ID/media", query: m.that { |query| query[:image_url] == jpg_url }) }.with {
      Platforms::Instagram::CallsInstagramApi::Result.new(
        success?: false,
        data: {error: {code: 352, error_subcode: "2207008", type: "OAuthException", fbtrace_id: "fbtrace"}},
        message: "Waiting for Instagram container to exist"
      )
    }

    result = PublishesCrosspost.new.publish(crosspost.id)

    assert result.needs_to_finish?
    verify { |m| calls_instagram_api.call(method: :post, path: "SOME_USER_ID/media", query: m.that { |query| query[:image_url] == jpg_url }) }
  end

  def test_instagram_skips_a_post_whose_override_empties_the_media
    post_url = "https://example.com/posts/text-only"
    stub_request(:get, feed_url)
      .to_return(body: <<~XML, status: 200)
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom" xmlns:posse="https://posseparty.com/2024/Feed">
          <title>Test Feed</title>
          <id>#{feed_url}</id>
          <updated>2026-10-01T00:00:00Z</updated>
          <entry>
            <title>Text only</title>
            <id>#{post_url}</id>
            <published>2026-10-01T00:00:00Z</published>
            <updated>2026-10-01T00:00:00Z</updated>
            <link rel="alternate" href="#{post_url}"/>
            <posse:post><![CDATA[{"syndicate":true,"media":[{"type":"image","url":"https://example.com/media/map.webp"}],"platform_overrides":{"instagram":{"media":[]}}}]]></posse:post>
          </entry>
        </feed>
      XML
    feed = @user.feeds.create!(url: feed_url, label: "civilytics.com social - test")
    FetchesFeed.new.fetch!(feed, cache: false)
    crosspost = Crosspost.find_by!(post: Post.find_by!(remote_id: post_url))
    crosspost.update!(status: "wip")

    result = PublishesCrosspost.new.publish(crosspost.id)

    assert result.success?
    assert_equal "skipped", crosspost.reload.status
  end

```

The first test's stub matches only a request for the JPEG, so a request for the top-level WebP gets
no answer and the post does not reach `needs_to_finish?`. The 352/2207008 error is the existing
"container not ready yet" signal, which stops the flow before any further API call.

In `test/lib/translates_instagram_post_test.rb`, replace:

```ruby
    instagram_post = translator.from_crosspost(crosspost)
```

with:

```ruby
    instagram_post = translator.from_crosspost(crosspost, post.media)
```

- [ ] **Step 2: Run them to see them fail**

Run: `rt "bin/rails test test/lib/fetches_feed/applies_post_overrides_test.rb test/lib/instagram_test.rb test/lib/translates_instagram_post_test.rb"`
Expected:
- `test_empties_override_media_that_is_not_a_list` fails: expected `[]`, actual
  `"https://example.com/a.jpg"`.
- Both new Instagram tests error with `undefined method 'needs_to_finish?'` (or `'success?'`) for
  `PublishCrosspostJob`. Instagram still reads the post's top-level media, so the publish raises
  and a retry job comes back instead of a result.
- The translator test errors with `wrong number of arguments (given 2, expected 1)`.

- [ ] **Step 3: Write the implementation**

In `app/lib/fetches_feed/applies_post_overrides.rb`, replace:

```ruby
      syndication_config[:platform_overrides] = {} unless syndication_config[:platform_overrides].is_a?(Hash)
```

with:

```ruby
      syndication_config[:platform_overrides] = {} unless syndication_config[:platform_overrides].is_a?(Hash)
      syndication_config[:platform_overrides].each_value do |overrides|
        overrides[:media] = [] if overrides.is_a?(Hash) && overrides.key?(:media) && !overrides[:media].is_a?(Array)
      end
```

In `app/lib/platforms/instagram.rb`, replace `if crosspost.post.media.present?` with
`if crosspost_config.media.present?`.

In `app/lib/platforms/instagram/translates_instagram_post.rb`, replace:

```ruby
  def from_crosspost(crosspost, channel: "feed")
    post = crosspost.post
    medias = post.media
```

with:

```ruby
  def from_crosspost(crosspost, media, channel: "feed")
    post = crosspost.post
    medias = media
```

In `app/lib/platforms/instagram/publishes_instagram_post.rb`, replace:

```ruby
        instagram_post = @translates_instagram_post.from_crosspost(crosspost, channel:)
```

with:

```ruby
        instagram_post = @translates_instagram_post.from_crosspost(crosspost, crosspost_config.media, channel:)
```

- [ ] **Step 4: Run them to see them pass**

Run: `rt "bin/rails test test/lib/fetches_feed/applies_post_overrides_test.rb test/lib/instagram_test.rb test/lib/translates_instagram_post_test.rb"`
Expected: `13 runs, ... 0 failures, 0 errors, 0 skips`.

- [ ] **Step 5: Lint and commit**

Run: `rt "bundle exec standardrb app/lib test/lib"`
Expected: no output.

```bash
cd /tmp/posse-wave1
git add app/lib/fetches_feed/applies_post_overrides.rb app/lib/platforms/instagram.rb app/lib/platforms/instagram/translates_instagram_post.rb app/lib/platforms/instagram/publishes_instagram_post.rb test/lib/fetches_feed/applies_post_overrides_test.rb test/lib/instagram_test.rb test/lib/translates_instagram_post_test.rb
git commit -F - <<'EOF'
feat: Instagram posts the media its platform override names

Instagram read the post's top-level media, so a feed could not send it a
JPEG while sending other platforms a GIF or WebP. It now reads the merged
config, where platform_overrides.instagram.media replaces the top-level
list, and an override that empties the list skips the crosspost as a
post without media always has.

An override whose media is not a list is read as no media, matching the
guard on the top-level field.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 5: Fixture images for the recordings

Branch `feat/media-foundation`. Waves 2 and 3 branch from here too, so the fixtures live here. The
recordings fetch them from GitHub at
`https://raw.githubusercontent.com/jknowles/posse_party/feat/media-foundation/test/fixtures/files/media/`.
Pushing the branch happens in Task 8, under Jared's approval.

**Files:**
- Create: `test/fixtures/files/media/still.jpg`, `still.png`, `loop.gif`

**Interfaces:**
- Produces: three plain 240 × 240 images: an orange JPEG, a navy PNG, and a three-frame GIF
  (orange, navy, paper; 0.5 s a frame, looping).

- [ ] **Step 1: Generate them with libvips**

The fork already depends on `ruby-vips`, so the image is reproducible from this script. Run it once.
It is not committed.

```bash
cat > /tmp/posse-wave1/tmp/make_media_fixtures.rb <<'EOF'
require "vips"

dir = "test/fixtures/files/media"
FileUtils.mkdir_p(dir)
frame = ->(r, g, b) { (Vips::Image.black(240, 240) + [r, g, b]).cast(:uchar).copy(interpretation: :srgb) }

frame.call(194, 83, 17).jpegsave("#{dir}/still.jpg", Q: 80, strip: true)
frame.call(34, 64, 106).pngsave("#{dir}/still.png", strip: true)
loop_image = Vips::Image.arrayjoin([frame.call(194, 83, 17), frame.call(34, 64, 106), frame.call(250, 247, 242)], across: 1).copy
loop_image.set_type(GObject::GINT_TYPE, "page-height", 240)
loop_image.set_type(Vips::ARRAY_INT_TYPE, "delay", [500, 500, 500])
loop_image.set_type(GObject::GINT_TYPE, "loop", 0)
loop_image.gifsave("#{dir}/loop.gif")
Dir["#{dir}/*"].sort.each { |f| puts "#{f} #{File.size(f)}" }
EOF
rt "bin/rails runner tmp/make_media_fixtures.rb"
rm /tmp/posse-wave1/tmp/make_media_fixtures.rb
```

Expected: three lines naming the files, each between about 700 and 1,600 bytes.

- [ ] **Step 2: Check them**

Run: `file /tmp/posse-wave1/test/fixtures/files/media/* && magick identify /tmp/posse-wave1/test/fixtures/files/media/loop.gif`
Expected: `GIF image data, version 89a, 240 x 240`, `JPEG image data ... 240x240`,
`PNG image data, 240 x 240`, and three frames listed for `loop.gif[0]` to `[2]`.

- [ ] **Step 3: Commit**

```bash
cd /tmp/posse-wave1
git add test/fixtures/files/media
git commit -F - <<'EOF'
test: add a JPEG, a PNG and an animated GIF for media recordings

Three 240 px squares, a few hundred bytes each, generated with libvips.
Recorded platform tests fetch them by their GitHub raw URLs on this
branch, so the cassettes hold real downloads of known files.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 4: Run the foundation's full suite**

Run: `rt "CI=true ./script/test" > /tmp/posse-wave1-foundation.log 2>&1; tail -3 /tmp/posse-wave1-foundation.log; git -C /tmp/posse-wave1 status --short`
Expected: two `0 failures, 0 errors` lines, one for the tests and one for the system tests, and an
empty `git status`. `script/test` runs `standard:fix` first, so any output from `status` means it
changed a file: read the change, then commit it as `style: standardrb`.

---

### Task 6: LinkedIn uploads a post's images

Branch `feat/linkedin-images`, created from `feat/media-foundation` with `fix/linkedin-one-url`
merged in first. Both touch `syndicates_linkedin_post.rb`, and the merge keeps the deploy free of
conflicts.

**Files:**
- Modify: `app/lib/platforms/linkedin/uploads_image.rb` (whole file)
- Create: `app/lib/platforms/linkedin/uploads_media.rb`
- Test: `test/lib/platforms/linkedin/uploads_image_test.rb`,
  `test/lib/platforms/linkedin/uploads_media_test.rb`

**Interfaces:**
- Consumes: `ParsesMediaItems`, `SelectsMedia`, `DownloadsMedia`, `RecordsMediaFallback`,
  `MediaUnavailable` (Tasks 2–3); `InitiatesImageUpload#initiate(access_token:, person_urn:)`,
  returning `Result(success?, upload_url, image_urn, message)`.
- Produces:
  - `UploadsImage#upload_bytes(bytes, content_type:, upload_url:, access_token:) -> Outcome`.
    `#upload(image_url, upload_url, access_token:)` keeps its signature and still sends
    `image/jpeg`, so the existing cassettes still match.
  - `Platforms::Linkedin::UploadsMedia#upload(crosspost, crosspost_config, access_token:,
    person_urn:) -> [UploadsMedia::Uploaded]`, where `Uploaded = Struct(:urn, :alt)`.
    - Returns `[]` when there is no media.
    - Never raises: a video, an unsupported type, a failed download, initiate or upload records a
      fallback and returns `[]`.
    - Constants: `MAX_IMAGES = 20`, `MAX_IMAGE_BYTES = 20 MB`,
      `CONTENT_TYPES = image/jpeg, image/png, image/gif`.

- [ ] **Step 1: Create the branch**

```bash
cd /tmp/posse-wave1
git switch -c feat/linkedin-images feat/media-foundation
git merge --no-edit fix/linkedin-one-url
```

Expected: `Merge made by the 'ort' strategy`, with 4 files changed.

- [ ] **Step 2: Write the failing tests**

`test/lib/platforms/linkedin/uploads_image_test.rb`:

```ruby
require "test_helper"

class Platforms::Linkedin::UploadsImageTest < ActiveSupport::TestCase
  UPLOAD_URL = "https://www.linkedin.com/dms-uploads/sp/v2/image-1"

  def setup
    @subject = Platforms::Linkedin::UploadsImage.new
  end

  def test_puts_the_bytes_with_their_own_content_type
    upload = stub_request(:put, UPLOAD_URL)
      .with(body: "GIF89a", headers: {"Authorization" => "Bearer token", "Content-Type" => "image/gif"})
      .to_return(status: 201)

    outcome = @subject.upload_bytes("GIF89a", content_type: "image/gif", upload_url: UPLOAD_URL, access_token: "token")

    assert outcome.success?
    assert_requested upload
  end

  def test_reports_an_upload_linkedin_rejects
    stub_request(:put, UPLOAD_URL).to_return(status: 400, body: "Bad image")

    outcome = @subject.upload_bytes("GIF89a", content_type: "image/gif", upload_url: UPLOAD_URL, access_token: "token")

    assert_equal "Failed to upload image to LinkedIn. Response: Bad image", outcome.message
  end

  def test_reports_a_connection_error
    stub_request(:put, UPLOAD_URL).to_timeout

    outcome = @subject.upload_bytes("GIF89a", content_type: "image/gif", upload_url: UPLOAD_URL, access_token: "token")

    assert_match(/\AFailed to upload image to LinkedIn: /, outcome.message)
  end
end
```

`test/lib/platforms/linkedin/uploads_media_test.rb`:

```ruby
require "test_helper"

class Platforms::Linkedin::UploadsMediaTest < ActiveSupport::TestCase
  GIF_URL = "https://example.com/media/loop.gif"
  PNG_URL = "https://example.com/media/still.png"

  def setup
    @downloads_media = Mocktail.of_next(DownloadsMedia)
    @initiates_image_upload = Mocktail.of_next(Platforms::Linkedin::InitiatesImageUpload)
    @uploads_image = Mocktail.of_next(Platforms::Linkedin::UploadsImage)
    @records_media_fallback = Mocktail.of_next(RecordsMediaFallback)
    @subject = Platforms::Linkedin::UploadsMedia.new
    @crosspost = crossposts(:admin_bsky_crosspost)
  end

  def test_uploads_each_image_and_returns_its_urn_and_alt
    stub_download(GIF_URL, "GIF89a", "image/gif")
    stub_download(PNG_URL, "PNG", "image/png")
    stubs { @initiates_image_upload.initiate(access_token: "token", person_urn: "urn:li:person:1") }.with {
      Platforms::Linkedin::InitiatesImageUpload::Result.new(success?: true, upload_url: "https://upload.example.com/1", image_urn: "urn:li:image:1")
    }
    stubs { @uploads_image.upload_bytes("GIF89a", content_type: "image/gif", upload_url: "https://upload.example.com/1", access_token: "token") }.with { Outcome.success }
    stubs { @uploads_image.upload_bytes("PNG", content_type: "image/png", upload_url: "https://upload.example.com/1", access_token: "token") }.with { Outcome.success }

    uploaded = @subject.upload(@crosspost, config([
      {"type" => "image", "url" => GIF_URL, "alt" => "A loop"},
      {"type" => "image", "url" => PNG_URL}
    ]), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal [
      Platforms::Linkedin::UploadsMedia::Uploaded.new(urn: "urn:li:image:1", alt: "A loop"),
      Platforms::Linkedin::UploadsMedia::Uploaded.new(urn: "urn:li:image:1", alt: "")
    ], uploaded
    verify_never_called { @records_media_fallback.record }
  end

  def test_no_media_uploads_nothing
    uploaded = @subject.upload(@crosspost, config(nil), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal [], uploaded
    verify_never_called { @downloads_media.download }
  end

  def test_a_video_falls_back_until_linkedin_video_ships
    uploaded = @subject.upload(@crosspost, config([{"type" => "video", "url" => "https://example.com/media/loop.mp4"}]), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal [], uploaded
    verify { @records_media_fallback.record(@crosspost, "LinkedIn video is not supported yet") }
  end

  def test_a_type_linkedin_does_not_take_falls_back
    stub_download(PNG_URL, "RIFF", "image/webp")

    uploaded = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal [], uploaded
    verify { @records_media_fallback.record(@crosspost, "LinkedIn takes JPEG, PNG and GIF, not image/webp (#{PNG_URL})") }
  end

  def test_a_failed_download_falls_back
    stubs { @downloads_media.download(MediaItem.new(type: "image", url: PNG_URL, alt: ""), max_bytes: 20 * 1024 * 1024) }.with {
      Result.failure("Could not download #{PNG_URL}: HTTP 404")
    }

    uploaded = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal [], uploaded
    verify { @records_media_fallback.record(@crosspost, "Could not download #{PNG_URL}: HTTP 404") }
  end

  def test_an_upload_linkedin_will_not_start_falls_back
    stub_download(PNG_URL, "PNG", "image/png")
    stubs { @initiates_image_upload.initiate(access_token: "token", person_urn: "urn:li:person:1") }.with {
      Platforms::Linkedin::InitiatesImageUpload::Result.new(success?: false, message: "Failed to initiate LinkedIn image upload.")
    }

    uploaded = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal [], uploaded
    verify { @records_media_fallback.record(@crosspost, "Failed to initiate LinkedIn image upload.") }
  end

  def test_a_rejected_upload_falls_back
    stub_download(PNG_URL, "PNG", "image/png")
    stubs { @initiates_image_upload.initiate(access_token: "token", person_urn: "urn:li:person:1") }.with {
      Platforms::Linkedin::InitiatesImageUpload::Result.new(success?: true, upload_url: "https://upload.example.com/1", image_urn: "urn:li:image:1")
    }
    stubs { @uploads_image.upload_bytes("PNG", content_type: "image/png", upload_url: "https://upload.example.com/1", access_token: "token") }.with {
      Outcome.failure("Failed to upload image to LinkedIn. Response: Bad image")
    }

    uploaded = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal [], uploaded
    verify { @records_media_fallback.record(@crosspost, "Failed to upload image to LinkedIn. Response: Bad image") }
  end

  def test_images_past_twenty_are_dropped_and_recorded
    stub_download(PNG_URL, "PNG", "image/png")
    stubs { @initiates_image_upload.initiate(access_token: "token", person_urn: "urn:li:person:1") }.with {
      Platforms::Linkedin::InitiatesImageUpload::Result.new(success?: true, upload_url: "https://upload.example.com/1", image_urn: "urn:li:image:1")
    }
    stubs { @uploads_image.upload_bytes("PNG", content_type: "image/png", upload_url: "https://upload.example.com/1", access_token: "token") }.with { Outcome.success }

    uploaded = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}] * 22), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal 20, uploaded.size
    verify { @records_media_fallback.record(@crosspost, "LinkedIn takes at most 20 images; dropped 2") }
  end

  private

  def config(media)
    CrosspostConfig.new(media:)
  end

  def stub_download(url, bytes, content_type)
    stubs { |m| @downloads_media.download(m.that { |item| item.url == url }, max_bytes: 20 * 1024 * 1024) }.with {
      Result.success(DownloadsMedia::Downloaded.new(bytes:, content_type:))
    }
  end
end
```

- [ ] **Step 3: Run them to see them fail**

Run: `rt "bin/rails test test/lib/platforms/linkedin/uploads_image_test.rb test/lib/platforms/linkedin/uploads_media_test.rb"`
Expected: 11 errors.
- The three `UploadsImageTest` tests: `NoMethodError: undefined method 'upload_bytes'`.
- The eight `UploadsMediaTest` tests: `NameError: uninitialized constant
  Platforms::Linkedin::UploadsMedia`.

- [ ] **Step 4: Write the implementation**

`app/lib/platforms/linkedin/uploads_image.rb`, whole file:

```ruby
class Platforms::Linkedin
  class UploadsImage
    def upload(image_url, upload_url, access_token:)
      return Outcome.failure("Image URL is required") if image_url.blank?
      return Outcome.failure("Upload URL is required") if upload_url.blank?

      if (image_data = download_image(image_url)).present?
        upload_bytes(image_data, content_type: "image/jpeg", upload_url:, access_token:)
      else
        Outcome.failure("Failed to download image from #{image_url}")
      end
    end

    def upload_bytes(bytes, content_type:, upload_url:, access_token:)
      response = HTTParty.put(
        upload_url,
        headers: {
          "Authorization" => "Bearer #{access_token}",
          "Content-Type" => content_type
        },
        body: bytes
      )

      if response.success?
        Outcome.success
      else
        Outcome.failure("Failed to upload image to LinkedIn. Response: #{response.parsed_response || response.body}")
      end
    rescue => e
      Outcome.failure("Failed to upload image to LinkedIn: #{e.message}")
    end

    private

    def download_image(image_url)
      response = HTTParty.get(image_url)
      response.body if response.success?
    end
  end
end
```

`app/lib/platforms/linkedin/uploads_media.rb`:

```ruby
class Platforms::Linkedin
  class UploadsMedia
    MAX_IMAGES = 20
    MAX_IMAGE_BYTES = 20 * 1024 * 1024
    CONTENT_TYPES = %w[image/jpeg image/png image/gif].freeze

    Uploaded = Struct.new(:urn, :alt, keyword_init: true)

    def initialize
      @parses_media_items = ParsesMediaItems.new
      @selects_media = SelectsMedia.new
      @downloads_media = DownloadsMedia.new
      @initiates_image_upload = InitiatesImageUpload.new
      @uploads_image = UploadsImage.new
      @records_media_fallback = RecordsMediaFallback.new
    end

    def upload(crosspost, crosspost_config, access_token:, person_urn:)
      selection = @selects_media.select(@parses_media_items.parse(crosspost_config.media), max_images: MAX_IMAGES)
      return [] if selection.empty?
      raise MediaUnavailable, "LinkedIn video is not supported yet" if selection.video

      uploaded = selection.images.map { |item| upload_image(item, access_token:, person_urn:) }
      if selection.dropped.positive?
        @records_media_fallback.record(crosspost, "LinkedIn takes at most #{MAX_IMAGES} images; dropped #{selection.dropped}")
      end
      uploaded
    rescue MediaUnavailable => e
      @records_media_fallback.record(crosspost, e.message)
      []
    end

    private

    def upload_image(item, access_token:, person_urn:)
      download = @downloads_media.download(item, max_bytes: MAX_IMAGE_BYTES)
      raise MediaUnavailable, download.error if download.failure?

      content_type = download.data.content_type
      unless CONTENT_TYPES.include?(content_type)
        raise MediaUnavailable, "LinkedIn takes JPEG, PNG and GIF, not #{content_type} (#{item.url})"
      end

      upload_init = @initiates_image_upload.initiate(access_token:, person_urn:)
      raise MediaUnavailable, upload_init.message unless upload_init.success?

      upload = @uploads_image.upload_bytes(download.data.bytes, content_type:, upload_url: upload_init.upload_url, access_token:)
      raise MediaUnavailable, upload.message unless upload.success?

      Uploaded.new(urn: upload_init.image_urn, alt: item.alt)
    end
  end
end
```

- [ ] **Step 5: Run them to see them pass, along with the existing LinkedIn tests**

Run: `rt "bin/rails test test/lib/platforms/linkedin test/lib/linkedin_test.rb"`
Expected: `0 failures, 0 errors`. `linkedin_take` and `linkedin_parentheses_fix` still replay,
which shows the og-image upload still sends `image/jpeg`.

- [ ] **Step 6: Lint and commit**

Run: `rt "bundle exec standardrb app/lib test/lib"`
Expected: no output.

```bash
cd /tmp/posse-wave1
git add app/lib/platforms/linkedin/uploads_image.rb app/lib/platforms/linkedin/uploads_media.rb test/lib/platforms/linkedin/uploads_image_test.rb test/lib/platforms/linkedin/uploads_media_test.rb
git commit -F - <<'EOF'
feat: upload a post's images to LinkedIn with their real content type

UploadsMedia takes the merged media list, keeps up to 20 images, and
uploads each one through LinkedIn's Images API, returning its URN and alt
text. It accepts JPEG, PNG and GIF, the types LinkedIn takes. A video, any
other type, a failed download or a failed upload records why in the
crosspost's metadata and returns no media, so the post still goes out with
its link card.

UploadsImage#upload_bytes sends the file's own content type; the og-image
thumbnail path keeps sending image/jpeg. A network error during an upload
now falls back instead of failing the post.

Refs #9

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 7: LinkedIn posts images in place of the card

Branch `feat/linkedin-images`.

**Files:**
- Modify: `app/lib/platforms/linkedin/publishes_post.rb` (constants, `publish`, `build_post_data`,
  new `media_entry`)
- Modify: `app/lib/platforms/linkedin/syndicates_linkedin_post.rb` (initializer, `syndicate!`, new
  `card_thumbnail`)
- Modify: `docs/feed.md` (the `media` row of the properties table)
- Test: `test/lib/platforms/linkedin/publishes_post_test.rb` (four tests and a helper appended),
  `test/lib/platforms/linkedin/syndicates_linkedin_post_test.rb` (new)

**Interfaces:**
- Consumes: `UploadsMedia#upload` and `UploadsMedia::Uploaded` (Task 6);
  `LimitsToOneUrl#limit(crosspost_config, crosspost_content) -> Post(content, card_url)` (from
  `fix/linkedin-one-url`).
- Produces: `PublishesPost#publish(content, crosspost_config, access_token:, person_urn:,
  image_urn: nil, url: nil, media: [])`.
  - One `Uploaded` gives `content: {media: {id:, altText:}}`.
  - Several give `content: {multiImage: {images: [{id:, altText:}]}}`.
  - Blank alt is omitted, and alt is truncated to `ALT_TEXT_MAX_LENGTH = 4086`.
  - With media there is no `article`.

- [ ] **Step 1: Write the failing tests**

Append to `test/lib/platforms/linkedin/publishes_post_test.rb`, inside the class, after the last
test:

```ruby
  def test_posts_one_image_as_media_with_its_alt_text
    api = Mocktail.of_next(Platforms::Linkedin::CallsLinkedinApi)
    subject = Platforms::Linkedin::PublishesPost.new
    stubs {
      api.call(method: :post, path: "rest/posts", access_token: "token", body: post_body(
        content: {media: {id: "urn:li:image:1", altText: "A loop"}}
      ))
    }.with {
      Platforms::Linkedin::CallsLinkedinApi::Result.new(success?: true, headers: {"x-restli-id" => "urn:li:share:1"})
    }

    result = subject.publish("A map", CrosspostConfig.new(url: "https://example.com/social/map/"),
      access_token: "token", person_urn: "urn:li:person:abc123",
      media: [Platforms::Linkedin::UploadsMedia::Uploaded.new(urn: "urn:li:image:1", alt: "A loop")])

    assert_equal "urn:li:share:1", result.post_urn
  end

  def test_posts_several_images_as_a_multi_image_and_omits_blank_alt_text
    api = Mocktail.of_next(Platforms::Linkedin::CallsLinkedinApi)
    subject = Platforms::Linkedin::PublishesPost.new
    stubs {
      api.call(method: :post, path: "rest/posts", access_token: "token", body: post_body(
        content: {multiImage: {images: [{id: "urn:li:image:1", altText: "A loop"}, {id: "urn:li:image:2"}]}}
      ))
    }.with {
      Platforms::Linkedin::CallsLinkedinApi::Result.new(success?: true, headers: {"x-restli-id" => "urn:li:share:2"})
    }

    result = subject.publish("A map", CrosspostConfig.new(url: "https://example.com/social/map/"),
      access_token: "token", person_urn: "urn:li:person:abc123",
      media: [
        Platforms::Linkedin::UploadsMedia::Uploaded.new(urn: "urn:li:image:1", alt: "A loop"),
        Platforms::Linkedin::UploadsMedia::Uploaded.new(urn: "urn:li:image:2", alt: "")
      ])

    assert_equal "urn:li:share:2", result.post_urn
  end

  def test_truncates_alt_text_to_linkedins_limit
    api = Mocktail.of_next(Platforms::Linkedin::CallsLinkedinApi)
    subject = Platforms::Linkedin::PublishesPost.new
    stubs {
      api.call(method: :post, path: "rest/posts", access_token: "token", body: post_body(
        content: {media: {id: "urn:li:image:1", altText: ("a" * 4100).truncate(4086)}}
      ))
    }.with {
      Platforms::Linkedin::CallsLinkedinApi::Result.new(success?: true, headers: {"x-restli-id" => "urn:li:share:3"})
    }

    result = subject.publish("A map", CrosspostConfig.new(url: "https://example.com/social/map/"),
      access_token: "token", person_urn: "urn:li:person:abc123",
      media: [Platforms::Linkedin::UploadsMedia::Uploaded.new(urn: "urn:li:image:1", alt: "a" * 4100)])

    assert_equal "urn:li:share:3", result.post_urn
  end

  def test_a_card_without_a_summary_has_no_description
    api = Mocktail.of_next(Platforms::Linkedin::CallsLinkedinApi)
    subject = Platforms::Linkedin::PublishesPost.new
    stubs {
      api.call(method: :post, path: "rest/posts", access_token: "token", body: post_body(
        content: {article: {source: "https://example.com/social/map/", title: "A map"}}
      ))
    }.with {
      Platforms::Linkedin::CallsLinkedinApi::Result.new(success?: true, headers: {"x-restli-id" => "urn:li:share:4"})
    }

    result = subject.publish("A map", CrosspostConfig.new(url: "https://example.com/social/map/", title: "A map", summary: nil),
      access_token: "token", person_urn: "urn:li:person:abc123", url: "https://example.com/social/map/")

    assert_equal "urn:li:share:4", result.post_urn
  end

  private

  def post_body(content:)
    {
      author: "urn:li:person:abc123",
      commentary: "A map",
      visibility: "PUBLIC",
      distribution: {feedDistribution: "MAIN_FEED", targetEntities: [], thirdPartyDistributionChannels: []},
      lifecycleState: "PUBLISHED",
      content:
    }
  end
```

Each stub answers only the exact body, so a wrong body makes the mock return `nil` and the test
errors. That makes the stub itself the check on the body.

`test/lib/platforms/linkedin/syndicates_linkedin_post_test.rb`:

```ruby
require "test_helper"

class Platforms::Linkedin::SyndicatesLinkedinPostTest < ActiveSupport::TestCase
  URL = "https://example.com/social/map/"

  def setup
    @uploads_media = Mocktail.of_next(Platforms::Linkedin::UploadsMedia)
    @limits_to_one_url = Mocktail.of_next(Platforms::Linkedin::LimitsToOneUrl)
    @publishes_post = Mocktail.of_next(Platforms::Linkedin::PublishesPost)
    @subject = Platforms::Linkedin::SyndicatesLinkedinPost.new
    @crosspost = Crosspost.create!(post: posts(:user_post), account: accounts(:user_linkedin_account), status: "wip")
    @config = CrosspostConfig.new(url: URL)
  end

  def test_posts_uploaded_images_with_the_composed_text_and_no_card
    media = [Platforms::Linkedin::UploadsMedia::Uploaded.new(urn: "urn:li:image:1", alt: "A loop")]
    stubs { @uploads_media.upload(@crosspost, @config, access_token: "linkedin-access-token", person_urn: "urn:li:person:TEST123") }.with { media }
    stubs {
      @publishes_post.publish("A map \\(2024\\)\n\n#{URL}", @config, access_token: "linkedin-access-token", person_urn: "urn:li:person:TEST123", image_urn: nil, url: nil, media:)
    }.with { published("urn:li:share:1") }

    result = @subject.syndicate!(@crosspost, @config, "A map (2024)\n\n#{URL}")

    assert result.success?
    assert_equal "published", @crosspost.reload.status
    assert_equal "urn:li:share:1", @crosspost.remote_id
    assert_equal "A map (2024)\n\n#{URL}", @crosspost.content
    verify_never_called { @limits_to_one_url.limit }
  end

  def test_without_media_posts_the_link_card_as_before
    stubs { @uploads_media.upload(@crosspost, @config, access_token: "linkedin-access-token", person_urn: "urn:li:person:TEST123") }.with { [] }
    stubs { @limits_to_one_url.limit(@config, "A map") }.with { Platforms::Linkedin::LimitsToOneUrl::Post.new(content: "A map", card_url: URL) }
    stubs {
      @publishes_post.publish("A map", @config, access_token: "linkedin-access-token", person_urn: "urn:li:person:TEST123", image_urn: nil, url: URL, media: [])
    }.with { published("urn:li:share:2") }

    result = @subject.syndicate!(@crosspost, @config, "A map")

    assert result.success?
    assert_equal "urn:li:share:2", @crosspost.reload.remote_id
  end

  private

  def published(urn)
    Platforms::Linkedin::PublishesPost::Result.new(true, urn, "https://www.linkedin.com/feed/update/#{urn}/")
  end
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `rt "bin/rails test test/lib/platforms/linkedin/publishes_post_test.rb test/lib/platforms/linkedin/syndicates_linkedin_post_test.rb"`
Expected: `9 runs, 12 assertions, 0 failures, 6 errors`.
- Five errors are `ArgumentError: unknown keyword: :media`: the three new `PublishesPost` media
  tests, raised from `publish`, and both `SyndicatesLinkedinPostTest` tests, raised from their
  `stubs` block. Mocktail checks a stubbed call against the real method's signature.
- `test_a_card_without_a_summary_has_no_description` errors with
  `undefined method 'truncate' for nil` at `publishes_post.rb`.

- [ ] **Step 3: Write the implementation**

In `app/lib/platforms/linkedin/publishes_post.rb`:

1. After `    DESCRIPTION_MAX_LENGTH = 4084`, add the line `    ALT_TEXT_MAX_LENGTH = 4086`.
2. Replace the `publish` signature and its `build_post_data` call:

```ruby
    def publish(content, crosspost_config, access_token:, person_urn:, image_urn: nil, url: nil, media: [])
      return Result.new(success?: false, message: "Content is required") if content.blank?

      post_data = build_post_data(content, crosspost_config, person_urn:, image_urn:, url:, media:)
```

3. Replace `build_post_data` from its `def` line through the end of the method with:

```ruby
    def build_post_data(content, crosspost_config, person_urn:, image_urn:, url:, media: [])
      {
        author: person_urn,
        commentary: content,
        visibility: "PUBLIC",
        distribution: {
          feedDistribution: "MAIN_FEED",
          targetEntities: [],
          thirdPartyDistributionChannels: []
        },
        lifecycleState: "PUBLISHED",
        content: (
          if media.size > 1
            {multiImage: {images: media.map { |image| media_entry(image) }}}
          elsif media.one?
            {media: media_entry(media.first)}
          elsif url.present?
            {
              article: {
                source: url,
                title: crosspost_config.og_title.presence || crosspost_config.title.presence || content.truncate(TITLE_MAX_LENGTH),
                description: crosspost_config.og_description.presence || crosspost_config.summary&.truncate(DESCRIPTION_MAX_LENGTH),
                thumbnail: image_urn
              }.compact
            }
          end
        )
      }.compact
    end

    def media_entry(image)
      {id: image.urn, altText: image.alt.presence&.truncate(ALT_TEXT_MAX_LENGTH)}.compact
    end
```

In `app/lib/platforms/linkedin/syndicates_linkedin_post.rb`:

1. After `      @uploads_image = UploadsImage.new`, add `      @uploads_media = UploadsMedia.new`.
2. Replace:

```ruby
      content, url = @limits_to_one_url.limit(crosspost_config, crosspost_content).to_a
      og_image = (url == crosspost_config.url) ? crosspost_config.og_image : @scrapes_og_image.scrape(url)
      image_urn = if url.present? &&
          og_image.present? &&
          (upload_init_result = @initiates_image_upload.initiate(access_token:, person_urn:)).success? &&
          @uploads_image.upload(og_image, upload_init_result.upload_url, access_token:).success?
        upload_init_result.image_urn
      end
```

with:

```ruby
      # With media there is no card: the composed text, appended URL included, is the commentary
      media = @uploads_media.upload(crosspost, crosspost_config, access_token:, person_urn:)
      content, url = media.any? ? [crosspost_content, nil] : @limits_to_one_url.limit(crosspost_config, crosspost_content).to_a
      image_urn = card_thumbnail(url, crosspost_config, access_token:, person_urn:) if url.present?
```

3. In the `@publishes_post.publish(...)` call, add `media:` after `url:`, so it reads
   `@publishes_post.publish(escaped_content, crosspost_config, access_token:, person_urn:, image_urn:, url:, media:)`.
4. After the method's closing `rescue … end`, add:

```ruby

    private

    def card_thumbnail(url, crosspost_config, access_token:, person_urn:)
      og_image = (url == crosspost_config.url) ? crosspost_config.og_image : @scrapes_og_image.scrape(url)
      if og_image.present? &&
          (upload_init_result = @initiates_image_upload.initiate(access_token:, person_urn:)).success? &&
          @uploads_image.upload(og_image, upload_init_result.upload_url, access_token:).success?
        upload_init_result.image_urn
      end
    end
```

`linkedin.rb` needs no change: `publish!` already passes `crosspost_config` to `syndicate!`.

- [ ] **Step 4: Run them to see them pass**

Run: `rt "bin/rails test test/lib/platforms/linkedin test/lib/linkedin_test.rb"`
Expected: `0 failures, 0 errors`, with the two existing LinkedIn cassettes still replaying.

- [ ] **Step 5: Say what LinkedIn now does with `media`**

In `docs/feed.md`, replace the `media` row of the properties table:

```markdown
| `media` | array<object> | Media attachments used by certain platforms (Instagram requires images/video; YouTube requires exactly one video). When present, `media.poster_url` is used by platforms that support custom covers/thumbnails (such as Instagram Reels and YouTube). |
```

with:

```markdown
| `media` | array<object> | Media attachments used by certain platforms (Instagram requires images/video; YouTube requires exactly one video; LinkedIn posts up to 20 JPEG, PNG or GIF images in place of the link card, and does not post video yet). When present, `media.poster_url` is used by platforms that support custom covers/thumbnails (such as Instagram Reels and YouTube). When LinkedIn cannot post an image, the post goes out with its link card and the reason is recorded in the crosspost's metadata. |
```

- [ ] **Step 6: Run the full suite**

Run: `rt "CI=true ./script/test" > /tmp/posse-wave1-linkedin.log 2>&1; grep "runs," /tmp/posse-wave1-linkedin.log; git -C /tmp/posse-wave1 status --short`
Expected: `371 runs, ... 0 failures, 0 errors` and `24 runs, ... 0 failures, 0 errors`. `git status`
lists only the files this task changed.

- [ ] **Step 7: Lint and commit**

Run: `rt "bundle exec standardrb app/lib test/lib"`
Expected: no output.

```bash
cd /tmp/posse-wave1
git add app/lib/platforms/linkedin/publishes_post.rb app/lib/platforms/linkedin/syndicates_linkedin_post.rb docs/feed.md test/lib/platforms/linkedin/publishes_post_test.rb test/lib/platforms/linkedin/syndicates_linkedin_post_test.rb
git commit -F - <<'EOF'
feat: post a feed's images and GIFs natively on LinkedIn

A LinkedIn post with media now carries the images LinkedIn hosts, in
place of the link card: one image as content.media, two to twenty as
content.multiImage, each with its alt text. The composed text, appended
URL included, is the commentary, so LimitsToOneUrl is skipped. A GIF is
an image to LinkedIn and plays as one.

When no media can be posted, the post goes out exactly as before. A card
without a summary no longer raises: its description is left out.

Fixes #9

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 8: Record the LinkedIn cassettes

Branch `feat/linkedin-images`. **This task publishes three real LinkedIn posts. It does not start
until Jared approves the session.** The tests are written first and fail for want of cassettes. Jared
then runs one recording command in his own terminal, deletes the three posts, and the tests replay
offline from then on.

**Files:**
- Modify: `test/lib/linkedin_test.rb` (three tests and two helpers appended)
- Create: `test/support/vcr_cassettes/linkedin_image.yml`, `linkedin_multi_image.yml`,
  `linkedin_gif.yml`

**Interfaces:**
- Consumes: the fixtures (Task 5) at their raw URLs; `vcr_secrets` and `perfect_vcr_match`
  (`test/support/vcr_helpers.rb`).

- [ ] **Step 1: Write the recorded tests**

Append to `test/lib/linkedin_test.rb`, inside the class, after the last test:

```ruby
  MEDIA_BASE = "https://raw.githubusercontent.com/jknowles/posse_party/feat/media-foundation/test/fixtures/files/media"

  def test_linkedin_posts_one_image_with_its_alt_text
    crosspost = linkedin_crosspost_with_media("https://example.com/social/still/", [
      {"type" => "image", "url" => "#{MEDIA_BASE}/still.jpg", "alt" => "An orange square", "mime" => "image/jpeg"}
    ])

    perfect_vcr_match("linkedin_image") do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_published_with_media crosspost
  end

  def test_linkedin_posts_several_images_as_a_multi_image
    crosspost = linkedin_crosspost_with_media("https://example.com/social/stills/", [
      {"type" => "image", "url" => "#{MEDIA_BASE}/still.jpg", "alt" => "An orange square", "mime" => "image/jpeg"},
      {"type" => "image", "url" => "#{MEDIA_BASE}/still.png", "alt" => "A navy square", "mime" => "image/png"}
    ])

    perfect_vcr_match("linkedin_multi_image") do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_published_with_media crosspost
  end

  def test_linkedin_posts_a_gif_from_its_platform_override
    crosspost = linkedin_crosspost_with_media("https://example.com/social/loop/", [
      {"type" => "video", "url" => "#{MEDIA_BASE}/loop.mp4", "presentation" => "gif"}
    ], linkedin_media: [
      {"type" => "image", "url" => "#{MEDIA_BASE}/loop.gif", "alt" => "Orange, navy and paper squares in turn", "mime" => "image/gif"}
    ])

    perfect_vcr_match("linkedin_gif") do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_published_with_media crosspost
  end

  private

  def linkedin_crosspost_with_media(post_url, media, linkedin_media: media)
    user = New.create(User, email: "user@example.com")
    user.accounts.create!(platform_tag: "linkedin", label: "LinkedIn", credentials: vcr_secrets({
      "client_id" => nil,
      "client_secret" => nil,
      "access_token" => ENV["LINKEDIN_ACCESS_TOKEN"],
      "person_urn" => ENV["LINKEDIN_PERSON_URN"]
    }))
    posse = {
      syndicate: true,
      format_string: "{{content}}",
      content: "PosseParty media test (deleted after recording)",
      media:,
      platform_overrides: {linkedin: {media: linkedin_media, append_url: true, append_url_spacer: "\n\n", attach_link: false}}
    }
    stub_request(:get, feed_url).to_return(status: 200, body: <<~XML)
      <?xml version="1.0" encoding="utf-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom" xmlns:posse="https://posseparty.com/2024/Feed">
        <title>Test Feed</title>
        <id>#{feed_url}</id>
        <updated>2026-10-01T00:00:00Z</updated>
        <entry>
          <title>Media test</title>
          <id>#{post_url}</id>
          <published>2026-10-01T00:00:00Z</published>
          <updated>2026-10-01T00:00:00Z</updated>
          <link rel="alternate" href="#{post_url}"/>
          <posse:post><![CDATA[#{posse.to_json}]]></posse:post>
        </entry>
      </feed>
    XML
    FetchesFeed.new.fetch!(user.feeds.create!(url: feed_url, label: "media test"), cache: false)
    Crosspost.find_by!(post: Post.find_by!(remote_id: post_url)).tap { |crosspost| crosspost.update!(status: "wip") }
  end

  def assert_published_with_media(crosspost)
    crosspost.reload
    assert_empty crosspost.failures
    assert_equal "published", crosspost.status
    assert_match(/\Aurn:li:(share|ugcPost):/, crosspost.remote_id)
    assert_nil crosspost.metadata["media_fallback"]
  end
```

What each assertion pins:

- `assert_nil crosspost.metadata["media_fallback"]` is what tells a native image post apart from a
  silent fallback to the card.
- `perfect_vcr_match` matches method, URI, body and headers, so the cassettes also pin
  `Content-Type: image/gif` on the GIF upload and the `content.media` body.
- The post's `remote_id` is matched by pattern, because the recorded ID is not known in advance.
- The GIF test's top-level item is a video that LinkedIn never sees, which is how civilytics.com
  sends a loop.

- [ ] **Step 2: Run them to see them fail**

Run: `rt "bin/rails test test/lib/linkedin_test.rb"`
Expected: the three new tests fail at `assert_empty crosspost.failures`, with a failure message
containing `An HTTP request has been made that VCR does not know how to handle`. The two existing
tests pass.

The failure also shows the fallback working. With the media download blocked, `UploadsMedia`
recorded it, and the post went on to try `rest/posts` with a card.

- [ ] **Step 3: Lint and commit the tests**

Run: `rt "bundle exec standardrb test/lib"`
Expected: no output.

```bash
cd /tmp/posse-wave1
git add test/lib/linkedin_test.rb
git commit -F - <<'EOF'
test: LinkedIn posts an image, several images and a GIF

Three recorded tests through PublishesCrosspost, each from a feed entry
carrying media. They check that the post publishes with no media fallback
recorded; the cassettes pin the upload content types and post bodies.
Cassettes follow in the next commit.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 4: STOP. Ask Jared to approve the recording session**

Put this to Jared and wait for a yes:

> Recording session for wave 1:
> - **Account:** your LinkedIn person account, the one PosseParty posts as.
> - **What gets published:** three posts, each saying "PosseParty media test (deleted after
>   recording)" with a link to example.com:
>   - one orange square (JPEG);
>   - an orange and a navy square together (multi-image);
>   - a three-frame GIF.
> - **What I push first:** `feat/media-foundation`, to `origin`, so GitHub serves the fixture
>   images. The push contains Tasks 1–5 and nothing else.
> - **What you do:**
>   1. Export `LINKEDIN_ACCESS_TOKEN` and `LINKEDIN_PERSON_URN` in your own terminal.
>   2. Run one command.
>   3. Delete the three posts from your LinkedIn activity page.
>   4. Unset the variables.
>
>   The token never enters this conversation or a file.
> - **What I check before commit:** that no cassette contains your token or person URN.

- [ ] **Step 5: Push the fixtures and check GitHub serves them**

```bash
cd /tmp/posse-wave1
git push -u origin feat/media-foundation
for f in still.jpg still.png loop.gif; do curl -sI "https://raw.githubusercontent.com/jknowles/posse_party/feat/media-foundation/test/fixtures/files/media/$f" | head -1; done
```

Expected: three `HTTP/2 200` lines.

- [ ] **Step 6: Turn recording on**

In `test/lib/linkedin_test.rb`, change each of the three new `perfect_vcr_match("linkedin_…")`
calls to pass `record: true`, for example `perfect_vcr_match("linkedin_image", record: true) do`.

- [ ] **Step 7: Jared records, in his own terminal**

Give Jared this to run. The values are for him to fill in. Both are in PosseParty's LinkedIn
account credentials on maxwell.

```bash
export LINKEDIN_ACCESS_TOKEN='…'
export LINKEDIN_PERSON_URN='urn:li:person:…'
POSSE_TREE=/tmp/posse-wave1 ~/.cache/posse-test/rt.sh "bin/rails test test/lib/linkedin_test.rb -n '/posts_(one_image|several_images|a_gif)/'"
```

Expected: `3 runs, ... 0 failures, 0 errors`, and three posts on his LinkedIn profile: the square,
the pair, and the GIF, which should animate.

**If any test fails, stop.** Have Jared delete whatever posted, and read the cassette's last
response. If LinkedIn rejected the post because an image was still processing, the fix is
`WaitsForProcessing`, which this plan does not include. Report back rather than adding it here.

Then Jared:

1. Deletes the three posts from his LinkedIn activity page and confirms they are gone.
2. Checks his own token is in no cassette:
   `grep -c "$LINKEDIN_ACCESS_TOKEN" /tmp/posse-wave1/test/support/vcr_cassettes/linkedin_{image,multi_image,gif}.yml`.
   Expected: `0` for each file.
3. Runs `unset LINKEDIN_ACCESS_TOKEN LINKEDIN_PERSON_URN`.

- [ ] **Step 8: Turn recording off and replay**

Remove the three `record: true` arguments. Then:

Run: `rt "bin/rails test test/lib/linkedin_test.rb"`
Expected: `5 runs, ... 0 failures, 0 errors`. This runs offline: the tests use placeholder
credentials, and VCR substitutes them for the filtered secrets.

- [ ] **Step 9: Check the cassettes for secrets**

```bash
cd /tmp/posse-wave1/test/support/vcr_cassettes
grep -n "Bearer" linkedin_image.yml linkedin_multi_image.yml linkedin_gif.yml | grep -v "{{access_token}}"
grep -n "urn:li:person:" linkedin_image.yml linkedin_multi_image.yml linkedin_gif.yml | grep -v "{{person_urn}}"
grep -n -i "set-cookie\|client_secret\|password" linkedin_image.yml linkedin_multi_image.yml linkedin_gif.yml | head
```

Expected: the first two print nothing. For the third, show Jared what it prints. Session cookies
from LinkedIn's responses are in the committed `linkedin_take.yml` upstream too. The `ut=` token in
each upload URL is a single-use upload signature, and upstream commits those as well. Jared decides
whether either stays.

- [ ] **Step 10: Commit the cassettes**

```bash
cd /tmp/posse-wave1
git add test/lib/linkedin_test.rb test/support/vcr_cassettes/linkedin_image.yml test/support/vcr_cassettes/linkedin_multi_image.yml test/support/vcr_cassettes/linkedin_gif.yml
git commit -F - <<'EOF'
test: record LinkedIn image, multi-image and GIF posts

Recorded against a real account on <date>; the three posts were deleted
straight after. Credentials are filtered to placeholders.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

Replace `<date>` with the recording date.

---

### Task 9: Deploy wave 1 to maxwell

**Every command that touches maxwell waits for Jared's yes.** The runbook is the gitignored
`maxwell-deploy.local.md` in the fork checkout, section 1a.

**Files:**
- Create: branch `test/deploy-YYYYMMDD` (local)
- Modify: `maxwell-deploy.local.md` (deploy log; never committed)

- [ ] **Step 1: Build the deploy branch and run the full suite on it**

```bash
cd /tmp/posse-wave1
DEPLOY=test/deploy-$(date +%Y%m%d)
git switch -c "$DEPLOY" main
git merge --no-edit test/deploy-20260928
git merge --no-edit feat/linkedin-images
rt "CI=true ./script/test" > /tmp/posse-wave1-deploy.log 2>&1; grep "runs," /tmp/posse-wave1-deploy.log
```

Expected: no conflicts, then `404 runs, ... 0 failures, 0 errors` and
`24 runs, ... 0 failures, 0 errors`. If `main` moved in Task 0, the
first merge is not a fast-forward; that is expected.

- [ ] **Step 2: STOP. Ask Jared to approve the deploy**

> Ready to deploy wave 1 to maxwell:
> - **Image:** `posse_party:media-YYYYMMDD`, built on maxwell from `$DEPLOY` at `<sha>`.
> - **What it contains:** today's deploy plus the media contract, the foundation and LinkedIn
>   images.
> - **Migrations:** none.
> - **Rollback:** `POSSE_IMAGE=posse_party:media-20260928 docker compose up -d`.
> - **Before it:** you take the `pg_dump` (runbook step 3), as on 2026-09-28.

- [ ] **Step 3: Build on maxwell**

```bash
cd /tmp/posse-wave1
SHA=$(git rev-parse HEAD); TAG=media-$(date +%Y%m%d)
ssh maxwell 'rm -rf ~/tmp/posse-build && mkdir -p ~/tmp/posse-build'
git archive --format=tar HEAD | ssh maxwell 'tar -x -C ~/tmp/posse-build'
ssh maxwell "cd ~/tmp/posse-build && docker build --build-arg GIT_COMMIT=$SHA -t posse_party:$TAG ."
```

Expected: the build ends with `naming to docker.io/library/posse_party:media-YYYYMMDD`.

- [ ] **Step 4: Jared takes the database dump**

Jared runs the runbook's step 3 dump and confirms the file exists. Do not continue without it.

- [ ] **Step 5: Run the new image and confirm it**

```bash
SHA=$(git -C /tmp/posse-wave1 rev-parse HEAD); TAG=media-$(date +%Y%m%d)
ssh maxwell "cd ~/docker-compose/posse && POSSE_IMAGE=posse_party:$TAG docker compose up -d"
ssh maxwell 'cd ~/docker-compose/posse && docker compose ps'
ssh maxwell 'cd ~/docker-compose/posse && docker compose logs -n 80 web worker'
curl -s -o /dev/null -w '%{http_code}\n' http://maxwell:3001/up
ssh maxwell 'cd ~/docker-compose/posse && docker compose exec -T web bin/rails runner "puts GitCommit.new.identify"'
```

Expected:
- `web` and `worker` are up, with no errors in the logs.
- `/up` returns `200`.
- The runner prints `$SHA`. The image tag alone does not prove which commit is running.

If any of these fails, roll back with the command in Step 2 and report.

- [ ] **Step 6: Log the deploy and draft the `.env` change**

Append to the fork checkout's `maxwell-deploy.local.md` deploy log, in the style of the 2026-09-28
entry:
- the date, `posse_party:media-YYYYMMDD`, the commit and `$DEPLOY`;
- the merged branches (`test/deploy-20260928` plus `docs/media-contract`,
  `feat/media-foundation` and `feat/linkedin-images`);
- "no migrations", the dump file, and the rollback command from Step 2.

Then give Jared this one-line change to apply himself, since the file holds secrets and lives in
`jared/maxwell_docker_compose`. It makes the image survive a bare `docker compose up -d`:

> In `~/docker-compose/posse/.env` on maxwell, add `POSSE_IMAGE=posse_party:media-YYYYMMDD`, and
> commit it the way that repository keeps its `.env`. Until then, any redeploy must repeat the
> inline `POSSE_IMAGE=`.

- [ ] **Step 7: Ask about pushing the step branches**

Ask Jared whether to push `docs/media-contract` and `feat/linkedin-images` to `origin`
(`feat/media-foundation` went up in Task 8), and whether to push `$DEPLOY` as the 2026-09-28 one
was. Push only what he approves.

---

### Task 10: Check a real post, then update what describes it

This task waits for homepage_test PR #129 to reach `main` and for a civilytics.com social post that
carries a GIF. Both are Jared's calls.

- [ ] **Step 1: Jared posts one GIF to LinkedIn and checks it**

Jared creates the LinkedIn crosspost for that post by hand in PosseParty and publishes it. On
LinkedIn he checks four things:

- the GIF plays;
- its alt text is set (LinkedIn's image menu shows it);
- the post's link is in the text;
- no link card appears.

Then confirm no fallback was recorded:

```bash
ssh maxwell 'cd ~/docker-compose/posse && docker compose exec -T web bin/rails runner "c = Crosspost.joins(:account).where(accounts: {platform_tag: %q(linkedin)}).order(:updated_at).last; p [c.status, c.remote_id, c.metadata[%q(media_fallback)]]"'
```

Expected: `["published", "urn:li:share:…", nil]`. If the third element is a Hash, its `reason` says
why the GIF did not post. Report it before changing anything.

- [ ] **Step 2: Update homepage_test's `docs/posse-party.md`**

In homepage_test, on a branch off `dev` (or on `feat/social-feed` if PR #129 is still open), replace
the paragraph that begins "As of October 2026 PosseParty posts media only to Instagram" with:

```markdown
As of <month> 2026 PosseParty posts media to Instagram and LinkedIn (and Facebook,
Threads, Pixelfed and YouTube, which this feed does not name). LinkedIn gets the GIF
and stills from its override as images, and posts its link card instead when it
cannot. Until the fork's remaining media steps land, a post with media reaches
Bluesky and Mastodon as its text with the link appended; hold that platform's
crosspost if the media matters.
```

Commit only when Jared asks. The repo's pre-commit hooks and CI apply as usual.

- [ ] **Step 3: Update the fork's media plan status**

On `docs/media-plan`, update the status line in `docs/planning/media.md`. It should say that step 8
(LinkedIn images) shipped in wave 1 (`posse_party:media-YYYYMMDD`), and that steps 4, 5, 6, 7 and 9
remain. Commit it locally.

- [ ] **Step 4: Draft the outward notes for Jared to approve**

Show each draft and post nothing without his yes:

1. A comment on jaredknowles.com #61:
   > PosseParty's `docs/feed.md` now documents `alt`, `presentation`, `mime`, `width`, `height` and
   > `bytes` on a media item, with the names this issue uses. `width` and `height` are optional for
   > images. LinkedIn posts images and GIFs natively as of `posse_party:media-YYYYMMDD`; Mastodon
   > and Bluesky follow in the next wave.
2. Closing fork issue #9 (LinkedIn images): the commit says "Fixes #9", but `feat/linkedin-images`
   never merges to the fork's `main`, so GitHub will not close it.
3. A new fork issue for the parked follow-up: show `media_fallback` on the crosspost page.

- [ ] **Step 5: Clean up**

```bash
cd /home/jared/Nextcloud/Civilytics/Code/jknowles/posse_party
git worktree remove /tmp/posse-wave1
ssh maxwell 'rm -rf ~/tmp/posse-build'
```

Keep `~/.cache/posse-test`, the `posse-test-*` containers and the volume for waves 2 and 3. Keep
`posse_party:media-20260928` on maxwell until the wave-2 deploy, as the rollback image.
