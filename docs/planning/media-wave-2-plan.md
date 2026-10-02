# Media wave 2 (Mastodon and Bluesky images) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mastodon and Bluesky post the images and GIFs a feed sends in `media`, without a media
problem ever failing a crosspost.

**Architecture:** The wave-1 foundation is extended, and one branch per platform starts from it.

- `feat/media-foundation` gains `WaitsForProcessing`, a shared `RedactsBearerToken`, and two fixes
  from the wave-1 ledger: a stale `media_fallback` is cleared at each attempt (M9), and a download
  has a 60-second deadline (M10).
- `feat/mastodon-images` uploads up to 4 images, GIFs included, to `POST /api/v2/media`. It waits up
  to 60 s for any image Mastodon is still processing, and otherwise finishes later through the
  existing `finish!` path. The status carries an `Idempotency-Key`.
- `feat/bsky-images` merges `fix/bsky-fit-thumbnail`, extracts `UploadsBskyBlob` from
  `AttachesWebCard`, and posts up to 4 images as `app.bsky.embed.images` in place of the link card.
  When the feed asked for a card, the card's link becomes the appended 🔗.

Then a whole-branch review, two recording sessions, one deploy to maxwell, and one real post that
Jared checks.

**Tech Stack:** Ruby 3.4.8, Rails, Minitest, Mocktail, VCR and WebMock, HTTParty, Marcel, ruby-vips,
bskyrb 0.5.3. Tests run in Docker (`postgres:17-alpine`, plus the `posse-test-ruby` image with
libvips, Node 22 and Playwright Chromium).

**Spec:** `docs/planning/media-steps-4-9-design.md` (branch `docs/media-plan`). Its §5, §6, §8 step 4,
§9 step 5, §10 and §11 are the sections this wave implements. Read it with this plan, and read
`docs/planning/media-wave-1-ledger.md` for the rulings wave 1 made on the code this wave builds on.

**Verified before writing:** every code block below was run in a scratch worktree off
`origin/feat/media-foundation` (`914ff83`), and this plan was generated from those files.

- `CI=true ./script/test` passes at each branch point: the foundation after Task 2 (356 tests, 24
  system tests), Mastodon after Task 4 (387, 24), Bluesky after Task 8 (385, 24).
- The three recordings were rehearsed against local fake Mastodon and Bluesky servers. The cassettes
  came out with the instance URL, the token, the Bluesky email and app password, and both Bluesky
  session tokens replaced by placeholders, and they replayed offline. They were then deleted.
- With those rehearsal cassettes in place, a deploy tree built as Task 13 builds it (`main`,
  `test/deploy-20261001`, both wave-2 branches, the two `docs/feed.md` conflicts resolved) passes in
  full: 477 tests, 24 system tests.
- The recorded tests in Tasks 5 and 9 fail until real cassettes exist, as expected.

## Global Constraints

- Fork conventions (`AGENTS.md`):
  - POROs live in `app/lib`, take no `initialize` arguments, and build their collaborators as ivars.
  - Return `Result`, `Outcome` or a Struct.
  - Tests are named as methods and contain no loops, branching or metaprogramming.
  - No `attr_reader`, no empty initializers, no dead code.
  - VCR for third-party servers; WebMock only for error branches that cannot be recorded.
- Media never fails a crosspost (spec §6). A media problem posts what the post would have been
  without media and records `{"media_fallback" => {"reason", "at"}}` in `crosspost.metadata`. In
  this wave *any* error inside a media step falls back, not only `MediaUnavailable` (ledger M7).
- Mastodon (spec §4, §8):
  - up to 4 images, GIFs included; video falls back until wave 3;
  - a 16 MB download cap; JPEG, PNG, GIF or WebP;
  - `POST /api/v2/media` with a multipart `file` and a `description` taken from `alt`, truncated to
    1,500 characters;
  - 200 means ready; 202 means poll `GET /api/v1/media/:id`, where 206 is still processing and 200
    is ready;
  - wait inline up to 60 s, 3 s apart, then finish later with
    `metadata["mastodon_media"] = {"ids", "status"}`;
  - `POST /api/v1/statuses` with `status`, `media_ids` and `Idempotency-Key: posse-party-crosspost-<id>`;
  - a rejected upload (413, 422, or any other refusal) falls back to the text with the appended URL.
- Bluesky (spec §4, §9):
  - up to 4 images; video falls back until wave 3;
  - JPEG, PNG, WebP or GIF;
  - each image brought within 2,000,000 bytes by `FitsImageWithinByteLimit`;
  - `alt` always present (an empty string is allowed);
  - `aspectRatio` from the feed's `width` and `height`, else read with libvips, else left out;
  - with media there is no web card; the link is the appended 🔗.
- The foundation holds only what waves 1 and 2 use. `download_to_tempfile` comes with wave 3.
- Step branches stay upstream-clean, with no fork-only files. `maxwell-deploy.local.md` is never
  committed.
- Recording sessions, from wave 1's lessons:
  - real account, approved by Jared first;
  - credentials never enter this transcript or a file. Jared captures them and runs the recording
    in his own terminal. Each capture from maxwell goes through `| tail -n 1`, because
    `bin/rails runner` prints an Active Storage warning on stdout first, and is checked against a
    character pattern, not a length;
  - never run a recorded test yourself while `record: true` is set: VCR then makes real calls with
    placeholder credentials;
  - every post deleted straight after, and Jared confirms before the cassettes are committed;
  - cassettes grepped for `Bearer` and the account's identifiers, and Jared greps for his real
    secret.
- Jared's standing rule: commit as each task says, but every push, deploy, comment or issue change
  stops for his approval first.
- Commit messages follow the fork: conventional prefix, a body that says what changed and why,
  `Refs #1` on the Mastodon and Bluesky commits, and the trailer
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Every commit in this clone queues a roborev review in the background (hooks installed 2026-10-01).
  It never blocks a commit; Task 10 reads the findings.

## Review Focus

These five inputs are the ones most likely to reach the code from a real feed without the spec
naming them. Each has a test in the owning task.

1. **A Bluesky post with images from a feed that asked for a card**, which is Bluesky's default
   (`attach_link: true`) and what jaredknowles.com's shots send, should keep its link as the appended
   🔗, trimmed to fit 300 graphemes, not lose it. This is wave 1's I3 for Bluesky. Pinned by
   `test_appends_the_link_a_card_would_have_carried` and
   `test_trims_text_at_the_limit_to_make_room_for_the_link` (Task 8).
2. **Alt text longer than 1,500 characters on Mastodon** should be truncated, not make Mastodon
   refuse the image and post the text alone. Pinned by `test_truncates_alt_text_to_mastodons_limit`
   (Task 3).
3. **More than four images** should post the first four and record the drop. Pinned by
   `test_images_past_four_are_dropped_and_recorded` (Tasks 3 and 7).
4. **A Mastodon token captured with a line break**, the way wave 1 lost a LinkedIn token, should
   appear in no fallback reason, log line or failure. Pinned by
   `test_an_unexpected_error_falls_back_without_the_access_token` (Task 3) and
   `test_a_failure_does_not_repeat_the_access_token` (Task 4).
5. **A retry after a media fallback** whose next attempt posts the media should not keep the old
   `media_fallback`, which would say the post went out without media. Pinned by
   `test_a_new_attempt_clears_the_media_fallback_an_earlier_attempt_recorded` (Task 2).

## Rulings made while verifying (carry these; do not re-decide)

- **The wave-1 minors that touch shared code** (the handoff asked which belong in the foundation):
  - M9, a stale `media_fallback`: fixed centrally. `PublishesCrosspost#publish` clears it at the
    start of each attempt, so the fix reaches LinkedIn at deploy without touching
    `feat/linkedin-images`. M9's other half (the log line says "posted without media" for a drop)
    stays deferred.
  - M10, no download deadline: fixed in `DownloadsMedia`. A download gives up after 60 seconds,
    measured with `Now`, so the test moves `Now` inside the stubbed response.
  - M7, errors other than `MediaUnavailable`: wave 2's uploaders rescue any error in their media
    step and record its class and message. LinkedIn keeps M7 until wave 3 next touches
    `UploadsMedia`.
- `WaitsForProcessing#wait(timeout: 60, interval: 3) { ready? }` returns `true` or `false`. It
  measures time on the monotonic clock, because a test can freeze `Now` and a frozen clock never
  runs out. It never sleeps past its deadline.
- `RedactsBearerToken` moves to the foundation as a top-level class. LinkedIn keeps its own
  `Platforms::Linkedin::RedactsBearerToken` until wave 3. The two constants do not collide.
- Mastodon's media calls live in one class, `CallsMastodonMediaApi` (`upload` and `check`). The
  status post stays in `SyndicatesMastodonPost`. A file goes up from a `Tempfile`, because HTTParty
  0.24 streams multipart bodies and needs a real IO with a path.
- Mastodon's 1,500-character alt limit is `MAX_DESCRIPTION_LENGTH` in every release through v4.5.0;
  Mastodon's `main` raises it to 10,000. JPEG, PNG, GIF and WebP are its `IMAGE_FILE_EXTENSIONS`.
  A GIF may share a status with stills: Mastodon refuses only audio or video beside other media.
- Finishing later: `finish!` checks once, with no inline wait. A check that fails, for any reason,
  posts the text rather than waiting again.
- The `Idempotency-Key` names the crosspost, whose ID differs between test runs. `perfect_vcr_match`
  now matches headers with the key left out, so upstream's Mastodon cassettes replay unchanged, and
  the recorded tests assert the key with `assert_requested`.
- Mastodon's media cassettes match on method and URI only, because the multipart boundary is random;
  the recorded tests assert the bodies instead. The instance URL is a VCR secret: it is stored as
  `{{base_url}}` and replays as `https://mastodon.example`.
- `UploadsBskyBlob#upload(bytes, content_type, record_manager)` returns a `Result`, where the spec
  wrote "returns blob". `AttachesWebCard` still raises when a thumbnail download or upload fails, as
  today (out of scope), and now says why. The og:image download is capped at 20 MB.
- Bluesky's record-building moves out of `SyndicatesBskyPost` into `ComposesPostRecord`, so the
  choice between images and card can be tested without a session. `KeepsLinkWithMedia` recomposes
  the text with `ComposesCrosspostContent`, as `RecoversFromInvalidLinkAttachment` does, so the
  300-grapheme limit and the 🔗 facet hold.
- `feat/bsky-images` merges `origin/fix/bsky-fit-thumbnail` first: `FitsImageWithinByteLimit` lives
  there, as `fix/linkedin-one-url` did for LinkedIn.
- Bluesky credentials never travel in a header (the email and app password go in createSession's
  JSON body; the access token is server-issued), so there is nothing to redact there. The recorded
  test filters both session tokens with a VCR filter that touches only `/xrpc/` calls.
- `docs/feed.md`: each step branch documents its own platform in the `media` row, so each branch can
  go upstream with its docs. The deploy merge resolves the two conflicts with one combined row
  (Task 13).
- No new fixtures. The recorded tests fetch `914ff83`'s fixtures, already on GitHub, so nothing is
  pushed before recording.

## Not in this plan

- Video on Mastodon and Bluesky (wave 3). A video item falls back with a reason, so a civilytics.com
  GIF post reaches Bluesky (which is sent the loop MP4) as its text with the link appended.
- **A status Mastodon refuses, or a record Bluesky refuses, after the uploads succeed fails as it
  does today.** As in wave 1, the fallback covers the media step only.
- LinkedIn's M7 and its copy of `RedactsBearerToken` (wave 3); M5, M6, M8, M11 and M13, and M9's log
  wording, which stay deferred.
- **The fallback reason is not shown in the UI.** The fork issue proposed in wave 1's Task 10 covers
  it.
- Bluesky's PDS stays hard-coded to `https://bsky.social`.
- WebP and GIF on Bluesky are accepted (the lexicon takes `image/*`), but the recording uses JPEG
  and PNG, so their rendering is unchecked.

---

### Task 0: Prepare the worktree and the test environment

No commits. Everything here is local.

**Files:**
- Modify (outside the repo): `~/.cache/posse-test/rt.sh`
- Create: worktree `/tmp/posse-wave2`

**Interfaces:**
- Produces: `~/.cache/posse-test/rt.sh`, which runs one command in the test container against
  `$POSSE_TREE`, now `/tmp/posse-wave2` by default, and passes the Mastodon and Bluesky recording
  variables through. Every later `rt "<command>"` means `~/.cache/posse-test/rt.sh "<command>"`.
  Each Bash call starts a fresh shell, so write the full path, not an alias.

- [ ] **Step 1: Check that upstream has not moved and wave 1 is where it was left**

The fork's checkout moved out of Nextcloud on 2026-10-01. It is now
`/home/jared/code/jknowles/posse_party`, and it has no local branches for the wave-1 work, only
`origin/…` ones.

```bash
cd /home/jared/code/jknowles/posse_party
git fetch upstream && git fetch origin
git rev-list --count main..upstream/main
git rev-parse --short main
git rev-parse --short origin/feat/media-foundation
git rev-parse --short origin/test/deploy-20261001
git rev-parse --short origin/fix/bsky-fit-thumbnail
```

Expected: `0`, then `de502b2`, `914ff83`, `5a094dc` and `0cac4a7`. If the count is not 0, or a SHA
differs, **stop and ask Jared**.

- [ ] **Step 2: Create the worktree on the foundation**

```bash
git worktree add -b feat/media-foundation /tmp/posse-wave2 origin/feat/media-foundation
```

Expected: `branch 'feat/media-foundation' set up to track 'origin/feat/media-foundation'`.

- [ ] **Step 3: Point the runner at the new worktree and pass the recording variables through**

```bash
cat > ~/.cache/posse-test/rt.sh <<'EOF'
#!/bin/sh
# Runs one command in the fork's test environment against the worktree at $POSSE_TREE
# (default /tmp/posse-wave2), then hands every file the container wrote back to you.
exec docker run --rm --network posse-test -v "${POSSE_TREE:-/tmp/posse-wave2}:/app" -v posse-test-gems:/gems \
  -e DATABASE_URL=postgres://postgres:postgres@posse-test-db/posse_party_test \
  -e RAILS_ENV=test -e CI=true -e LINKEDIN_ACCESS_TOKEN -e LINKEDIN_PERSON_URN \
  -e MASTODON_BASE_URL -e MASTODON_ACCESS_TOKEN -e BSKY_EMAIL -e BSKY_PASSWORD \
  posse-test-ruby sh -c "$*; s=\$?; chown -R $(id -u):$(id -g) /app; exit \$s"
EOF
chmod +x ~/.cache/posse-test/rt.sh
```

`-e NAME` passes a variable through only if the shell running `rt.sh` has it set; nothing is
written to disk. `/tmp/posse-wave1` no longer exists, which is why the default changes.

- [ ] **Step 4: Check the image and the database**

```bash
docker image inspect posse-test-ruby --format '{{.Id}}' || docker build -q -t posse-test-ruby ~/.cache/posse-test
docker start posse-test-db
```

Expected: an image ID, then `posse-test-db`.

- [ ] **Step 5: Install dependencies and run the baseline**

```bash
rt "bundle install --quiet && yarn install --frozen-lockfile --silent && bin/rails db:prepare"
rt "bin/rails test test/lib"
```

Expected: the last line reads `277 runs, ... 0 failures, 0 errors, 0 skips`.

---

### Task 1: Wait for processing, and redact bearer tokens

Branch `feat/media-foundation`.

**Files:**
- Create: `app/lib/waits_for_processing.rb`, `app/lib/redacts_bearer_token.rb`
- Test: `test/lib/waits_for_processing_test.rb`, `test/lib/redacts_bearer_token_test.rb`

**Interfaces:**
- Produces:
  - `WaitsForProcessing#wait(timeout: 60, interval: 3) { … } -> true | false`. It asks the block
    first, then every `interval` seconds, until the block answers truthy (`true`) or `timeout`
    seconds pass (`false`). It never sleeps past the deadline.
  - `RedactsBearerToken#redact(message) -> String`, with every `Bearer <token>` replaced by
    `Bearer [FILTERED]`.

- [ ] **Step 1: Write the failing tests**

`test/lib/waits_for_processing_test.rb`:

```ruby
require "test_helper"

class WaitsForProcessingTest < ActiveSupport::TestCase
  def setup
    @subject = WaitsForProcessing.new
  end

  def test_answers_true_once_the_block_does
    answers = [false, nil, true]

    ready = @subject.wait(timeout: 1, interval: 0) { answers.shift }

    assert_equal true, ready
    assert_empty answers
  end

  def test_answers_false_when_the_time_runs_out
    asked = 0

    ready = @subject.wait(timeout: 0.05, interval: 0.01) {
      asked += 1
      false
    }

    assert_equal false, ready
    assert_operator asked, :>, 1
  end

  def test_never_sleeps_past_the_deadline
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    @subject.wait(timeout: 0.05, interval: 10) { false }

    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1
  end
end
```

`test/lib/redacts_bearer_token_test.rb`. Net::HTTP refuses a header holding a line break, and its
error quotes the header with the line break escaped, which is the message below:

```ruby
require "test_helper"

class RedactsBearerTokenTest < ActiveSupport::TestCase
  def test_replaces_the_token_net_http_quotes_in_a_header_error
    message = %(header Authorization has field value "Bearer a warning\\nSECRET-TOKEN-123", this cannot include CR/LF)

    assert_equal %(header Authorization has field value "Bearer [FILTERED]", this cannot include CR/LF), RedactsBearerToken.new.redact(message)
  end

  def test_leaves_a_message_without_a_token_alone
    assert_equal "Net::ReadTimeout", RedactsBearerToken.new.redact("Net::ReadTimeout")
  end
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `rt "bin/rails test test/lib/waits_for_processing_test.rb test/lib/redacts_bearer_token_test.rb"`
Expected: `5 runs, 0 assertions, 0 failures, 5 errors`, each a `NameError: uninitialized constant`
for `WaitsForProcessing` or `RedactsBearerToken`.

- [ ] **Step 3: Write the implementation**

`app/lib/waits_for_processing.rb`:

```ruby
class WaitsForProcessing
  # Asks the block until it answers truthy or the time runs out, and says which happened. Time is
  # measured on the monotonic clock: a test can freeze Now, and a frozen clock never runs out.
  def wait(timeout: 60, interval: 3)
    deadline = clock + timeout
    loop do
      return true if yield

      remaining = deadline - clock
      return false unless remaining.positive?

      sleep([interval, remaining].min)
    end
  end

  private

  def clock
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
```

`app/lib/redacts_bearer_token.rb`:

```ruby
# Net::HTTP quotes a header it refuses (one holding a line break, say) in its error message, so an
# exception raised while building a request can carry the access token
class RedactsBearerToken
  def redact(message)
    message.gsub(/Bearer [^"]*/, "Bearer [FILTERED]")
  end
end
```

- [ ] **Step 4: Run them to see them pass**

Run: `rt "bin/rails test test/lib/waits_for_processing_test.rb test/lib/redacts_bearer_token_test.rb"`
Expected: `5 runs, 10 assertions, 0 failures, 0 errors, 0 skips`.

- [ ] **Step 5: Lint and commit**

Run: `rt "bundle exec standardrb app/lib test/lib"`
Expected: no output.

```bash
cd /tmp/posse-wave2
git add app/lib/waits_for_processing.rb app/lib/redacts_bearer_token.rb test/lib/waits_for_processing_test.rb test/lib/redacts_bearer_token_test.rb
git commit -F - <<'EOF'
feat: wait for media processing, and redact bearer tokens from errors

WaitsForProcessing asks a block until it answers or a deadline passes,
sleeping between asks but never past the deadline. Mastodon needs it for
images it is still processing, and the video steps will need it too. It
measures time on the monotonic clock, so a test that freezes Now cannot
make it wait forever.

RedactsBearerToken moves the wave-1 LinkedIn helper to where every
platform can use it: Net::HTTP quotes a header it refuses in its error,
so a token captured with a line break would otherwise reach a fallback
reason or a failure.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 2: Clear a stale fallback each attempt, and give downloads a deadline

Branch `feat/media-foundation`. These are the wave-1 ledger's M9 and M10.

**Files:**
- Modify: `app/lib/publishes_crosspost.rb:18`
- Modify: `app/lib/downloads_media.rb` (whole file below)
- Create: `test/lib/publishes_crosspost_test.rb`
- Modify: `test/lib/downloads_media_test.rb` (one test, before `test_reports_an_http_error`)

**Interfaces:**
- Produces:
  - Every `PublishesCrosspost#publish` attempt starts with no `media_fallback` in
    `crosspost.metadata`. Other keys are kept.
  - `DownloadsMedia#download(item, max_bytes:)` keeps its signature. It now fails with
    `"<url> took longer than 60 seconds to download"` once 60 seconds have passed.

- [ ] **Step 1: Write the failing tests**

`test/lib/publishes_crosspost_test.rb`. The `test` platform publishes without calling out, so the
attempt succeeds and the test reads what the attempt left behind:

```ruby
require "test_helper"

class PublishesCrosspostTest < ActiveSupport::TestCase
  def test_a_new_attempt_clears_the_media_fallback_an_earlier_attempt_recorded
    account = New.create(Account, user: users(:admin), platform_tag: "test", label: "@test", active: true)
    crosspost = Crosspost.create!(post: posts(:admin_post), account:, status: "wip", metadata: {
      "post" => "kept",
      "media_fallback" => {"reason" => "Could not download https://example.com/a.png: HTTP 503", "at" => "2026-10-06T10:00:00Z"}
    })

    PublishesCrosspost.new.publish(crosspost.id)

    assert_equal "published", crosspost.reload.status
    assert_equal({"post" => "kept"}, crosspost.metadata)
  end
end
```

In `test/lib/downloads_media_test.rb`, insert before `  def test_reports_an_http_error`:

```ruby
  def test_gives_up_on_a_download_that_runs_past_its_deadline
    Now.override!(Time.zone.parse("2026-10-06 10:00:00 UTC"))
    stub_request(:get, "https://example.com/slow.png").to_return {
      Now.override!(Time.zone.parse("2026-10-06 10:01:01 UTC"))
      {status: 200, body: PNG}
    }

    result = @subject.download(MediaItem.new(type: "image", url: "https://example.com/slow.png"), max_bytes: 100)

    assert_equal "https://example.com/slow.png took longer than 60 seconds to download", result.error
  end

```

The stubbed response moves `Now` 61 seconds on while the request is in flight, which is how a slow
host looks to the download.

- [ ] **Step 2: Run them to see them fail**

Run: `rt "bin/rails test test/lib/publishes_crosspost_test.rb test/lib/downloads_media_test.rb"`
Expected: `12 runs, 18 assertions, 2 failures, 0 errors`.
- The publish test: expected `{"post" => "kept"}`, actual still holds `"media_fallback"`.
- The download test: expected the deadline message, actual `nil`, because the download succeeded.

- [ ] **Step 3: Write the implementation**

In `app/lib/publishes_crosspost.rb`, replace:

```ruby
    crosspost.update!(last_attempted_at: Now.time, attempts: crosspost.attempts + 1)
```

with:

```ruby
    # A media fallback describes one attempt, so a new attempt starts without the last one's
    crosspost.update!(last_attempted_at: Now.time, attempts: crosspost.attempts + 1, metadata: crosspost.metadata.except("media_fallback"))
```

`app/lib/downloads_media.rb`, whole file:

```ruby
class DownloadsMedia
  Downloaded = Struct.new(:bytes, :content_type, keyword_init: true)
  TooLarge = Class.new(StandardError)
  TooSlow = Class.new(StandardError)
  DEADLINE = 60.seconds
  GENERIC_TYPES = %w[application/octet-stream binary/octet-stream].freeze

  def download(item, max_bytes:)
    return Result.failure(too_large(item, max_bytes)) if item.bytes.to_i > max_bytes

    started_at = Now.time
    body = +"".b
    response = HTTParty.get(item.url, stream_body: true, follow_redirects: true) do |fragment|
      raise TooSlow if Now.time - started_at > DEADLINE
      next unless fragment.code == 200
      raise TooLarge if fragment.http_response.content_length.to_i > max_bytes

      body << fragment
      raise TooLarge if body.bytesize > max_bytes
    end
    return Result.failure("Could not download #{item.url}: HTTP #{response.code}") unless response.code == 200

    Result.success(Downloaded.new(bytes: body, content_type: content_type(item, response, body)))
  rescue TooLarge
    Result.failure(too_large(item, max_bytes))
  rescue TooSlow
    Result.failure("#{item.url} took longer than #{DEADLINE.inspect} to download")
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

The deadline is checked on every fragment, before the redirect check, so a slow redirect counts too.

- [ ] **Step 4: Run them to see them pass**

Run: `rt "bin/rails test test/lib/publishes_crosspost_test.rb test/lib/downloads_media_test.rb"`
Expected: `12 runs, 18 assertions, 0 failures, 0 errors, 0 skips`.

- [ ] **Step 5: Lint and commit**

Run: `rt "bundle exec standardrb app/lib test/lib"`
Expected: no output.

```bash
cd /tmp/posse-wave2
git add app/lib/publishes_crosspost.rb app/lib/downloads_media.rb test/lib/publishes_crosspost_test.rb test/lib/downloads_media_test.rb
git commit -F - <<'EOF'
fix: clear a stale media fallback each attempt, and give downloads a deadline

A media fallback recorded by one attempt stayed in the crosspost's
metadata when a retry went on to post the media, so it said the post had
gone out without media when it had not. Each attempt now starts without
the last one's.

A media download had no overall deadline, so a host that sent a byte at a
time could hold a crosspost until the job timed out. It now gives up after
60 seconds, which leaves room for Mastodon's wait and four images inside
the 10-minute job.

Both fixes are in shared code, so they reach every platform's media step.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 6: Run the foundation's full suite**

Run: `rt "CI=true ./script/test" > /tmp/posse-wave2-foundation.log 2>&1; grep "runs," /tmp/posse-wave2-foundation.log; git -C /tmp/posse-wave2 status --short`
Expected: `356 runs, ... 0 failures, 0 errors` and `24 runs, ... 0 failures, 0 errors`, and an empty
`git status`. `script/test` runs `standard:fix` first, so any output from `status` means it changed
a file: read the change, then commit it as `style: standardrb`.

---

### Task 3: Mastodon uploads images and waits while they process

Branch `feat/mastodon-images`, created from `feat/media-foundation`.

**Files:**
- Create: `app/lib/platforms/mastodon/calls_mastodon_media_api.rb`,
  `app/lib/platforms/mastodon/uploads_mastodon_media.rb`
- Test: `test/lib/platforms/mastodon/calls_mastodon_media_api_test.rb`,
  `test/lib/platforms/mastodon/uploads_mastodon_media_test.rb`

**Interfaces:**
- Consumes: `ParsesMediaItems`, `SelectsMedia#select(items, max_images:)`,
  `DownloadsMedia#download(item, max_bytes:)`, `RecordsMediaFallback#record(crosspost, reason)`,
  `MediaUnavailable` (wave 1); `WaitsForProcessing`, `RedactsBearerToken` (Task 1).
- Produces:
  - `Platforms::Mastodon::CallsMastodonMediaApi`:
    - `#upload(account, bytes:, extension:, description:) -> Result`. On success `data` is an
      `Uploaded(id, ready?)`: `ready?` is true for HTTP 200 and false for 202. Any other status is a
      failure naming the code and body. A blank description is left out.
    - `#check(account, id) -> Result`. On success `data` is `true` for 200 and `false` for 206. Any
      other status is a failure.
  - `Platforms::Mastodon::UploadsMastodonMedia`:
    - `#upload(crosspost, crosspost_config) -> Media(ids, ready?)`. `Media` is a Struct.
      `UploadsMastodonMedia::NONE` (`ids: []`, `ready?: true`) means "post the text alone".
    - `#finish(crosspost, ids) -> Media`, which checks each ID once.
    - Neither ever raises: every failure records a fallback (token redacted) and returns `NONE`.
    - Constants: `MAX_IMAGES = 4`, `MAX_BYTES = 16 MB`, `MAX_DESCRIPTION_LENGTH = 1_500`,
      `EXTENSIONS` for JPEG, PNG, GIF and WebP.

- [ ] **Step 1: Create the branch**

```bash
cd /tmp/posse-wave2 && git switch -c feat/mastodon-images feat/media-foundation
```

- [ ] **Step 2: Write the failing tests**

`test/lib/platforms/mastodon/calls_mastodon_media_api_test.rb`. The upload stub matches only a
multipart body carrying the file and its description; the file's name comes from a `Tempfile`, so it
is matched by pattern:

```ruby
require "test_helper"

class Platforms::Mastodon::CallsMastodonMediaApiTest < ActiveSupport::TestCase
  def setup
    @subject = Platforms::Mastodon::CallsMastodonMediaApi.new
    @account = Account.new(platform_tag: "mastodon", credentials: {"base_url" => "https://mastodon.example", "access_token" => "token"})
  end

  def test_uploads_the_file_with_its_description_and_reports_it_ready
    upload = stub_request(:post, "https://mastodon.example/api/v2/media")
      .with(headers: {"Authorization" => "Bearer token"}) { |request|
        request.headers["Content-Type"].start_with?("multipart/form-data") &&
          request.body.match?(/name="file"; filename="media[^"]*\.png"/) &&
          request.body.include?("Content-Type: image/png\r\n\r\nPNG") &&
          request.body.include?(%(name="description"\r\n\r\nA navy square))
      }
      .to_return(status: 200, body: {id: "110", url: "https://files.mastodon.example/110.png"}.to_json, headers: {"Content-Type" => "application/json"})

    result = @subject.upload(@account, bytes: "PNG", extension: ".png", description: "A navy square")

    assert result.success?
    assert_equal Platforms::Mastodon::CallsMastodonMediaApi::Uploaded.new(id: "110", ready?: true), result.data
    assert_requested upload
  end

  def test_an_upload_mastodon_is_still_processing_is_not_ready
    stub_request(:post, "https://mastodon.example/api/v2/media")
      .to_return(status: 202, body: {id: "111", url: nil}.to_json, headers: {"Content-Type" => "application/json"})

    result = @subject.upload(@account, bytes: "GIF89a", extension: ".gif", description: "A loop")

    assert_equal Platforms::Mastodon::CallsMastodonMediaApi::Uploaded.new(id: "111", ready?: false), result.data
  end

  def test_leaves_out_a_blank_description
    upload = stub_request(:post, "https://mastodon.example/api/v2/media")
      .with { |request| !request.body.include?(%(name="description")) }
      .to_return(status: 200, body: {id: "112"}.to_json, headers: {"Content-Type" => "application/json"})

    @subject.upload(@account, bytes: "PNG", extension: ".png", description: "")

    assert_requested upload
  end

  def test_reports_an_upload_mastodon_refuses
    stub_request(:post, "https://mastodon.example/api/v2/media")
      .to_return(status: 422, body: {error: "File type of uploaded media could not be verified"}.to_json, headers: {"Content-Type" => "application/json"})

    result = @subject.upload(@account, bytes: "RIFF", extension: ".webp", description: "")

    assert result.failure?
    assert_equal %(Mastodon refused the upload (HTTP 422): {"error":"File type of uploaded media could not be verified"}), result.error
  end

  def test_checks_media_that_has_finished_processing
    stub_request(:get, "https://mastodon.example/api/v1/media/111")
      .with(headers: {"Authorization" => "Bearer token"})
      .to_return(status: 200, body: {id: "111", url: "https://files.mastodon.example/111.mp4"}.to_json, headers: {"Content-Type" => "application/json"})

    result = @subject.check(@account, "111")

    assert result.success?
    assert_equal true, result.data
  end

  def test_checks_media_that_is_still_processing
    stub_request(:get, "https://mastodon.example/api/v1/media/111")
      .to_return(status: 206, body: {id: "111", url: nil}.to_json, headers: {"Content-Type" => "application/json"})

    assert_equal false, @subject.check(@account, "111").data
  end

  def test_reports_media_mastodon_could_not_process
    stub_request(:get, "https://mastodon.example/api/v1/media/111")
      .to_return(status: 422, body: {error: "Error processing thumbnail for uploaded media"}.to_json, headers: {"Content-Type" => "application/json"})

    result = @subject.check(@account, "111")

    assert result.failure?
    assert_equal %(Mastodon could not process media 111 (HTTP 422): {"error":"Error processing thumbnail for uploaded media"}), result.error
  end
end
```

`test/lib/platforms/mastodon/uploads_mastodon_media_test.rb`. `stubs(ignore_block: true) { … }` is
how Mocktail stubs a method called with a block: without `ignore_block`, a demonstration with no
block never matches. `.with { |call| call.block.call }` then runs the uploader's real polling block,
so the test exercises the checks inside the wait.

```ruby
require "test_helper"

class Platforms::Mastodon::UploadsMastodonMediaTest < ActiveSupport::TestCase
  GIF_URL = "https://example.com/media/loop.gif"
  PNG_URL = "https://example.com/media/still.png"
  MAX_BYTES = 16 * 1024 * 1024

  def setup
    @downloads_media = Mocktail.of_next(DownloadsMedia)
    @calls_mastodon_media_api = Mocktail.of_next(Platforms::Mastodon::CallsMastodonMediaApi)
    @waits_for_processing = Mocktail.of_next(WaitsForProcessing)
    @records_media_fallback = Mocktail.of_next(RecordsMediaFallback)
    @subject = Platforms::Mastodon::UploadsMastodonMedia.new
    @crosspost = crossposts(:admin_mastodon_crosspost)
    @account = @crosspost.account
  end

  def test_uploads_each_image_mastodon_processes_at_once
    stub_download(GIF_URL, "GIF89a", "image/gif")
    stub_download(PNG_URL, "PNG", "image/png")
    stub_upload("GIF89a", ".gif", "A loop", id: "1", ready: true)
    stub_upload("PNG", ".png", "", id: "2", ready: true)

    media = @subject.upload(@crosspost, config([
      {"type" => "image", "url" => GIF_URL, "alt" => "A loop"},
      {"type" => "image", "url" => PNG_URL}
    ]))

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::Media.new(ids: ["1", "2"], ready?: true), media
    verify_never_called { @waits_for_processing.wait }
    verify_never_called { @records_media_fallback.record }
  end

  def test_no_media_uploads_nothing
    media = @subject.upload(@crosspost, config(nil))

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::NONE, media
    verify_never_called { @downloads_media.download }
  end

  def test_waits_for_media_mastodon_is_still_processing
    stub_download(GIF_URL, "GIF89a", "image/gif")
    stub_upload("GIF89a", ".gif", "A loop", id: "1", ready: false)
    stubs(ignore_block: true) { @waits_for_processing.wait }.with { |call| call.block.call }
    stubs { @calls_mastodon_media_api.check(@account, "1") }.with { Result.success(true) }

    media = @subject.upload(@crosspost, config([{"type" => "image", "url" => GIF_URL, "alt" => "A loop"}]))

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::Media.new(ids: ["1"], ready?: true), media
  end

  def test_media_still_processing_when_the_wait_runs_out_is_left_to_finish
    stub_download(GIF_URL, "GIF89a", "image/gif")
    stub_upload("GIF89a", ".gif", "A loop", id: "1", ready: false)
    stubs(ignore_block: true) { @waits_for_processing.wait }.with { false }

    media = @subject.upload(@crosspost, config([{"type" => "image", "url" => GIF_URL, "alt" => "A loop"}]))

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::Media.new(ids: ["1"], ready?: false), media
    verify_never_called { @records_media_fallback.record }
  end

  def test_media_mastodon_cannot_process_falls_back
    stub_download(GIF_URL, "GIF89a", "image/gif")
    stub_upload("GIF89a", ".gif", "A loop", id: "1", ready: false)
    stubs(ignore_block: true) { @waits_for_processing.wait }.with { |call| call.block.call }
    stubs { @calls_mastodon_media_api.check(@account, "1") }.with { Result.failure("Mastodon could not process media 1 (HTTP 422): {}") }

    media = @subject.upload(@crosspost, config([{"type" => "image", "url" => GIF_URL, "alt" => "A loop"}]))

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::NONE, media
    verify { @records_media_fallback.record(@crosspost, "Mastodon could not process media 1 (HTTP 422): {}") }
  end

  def test_a_video_falls_back_until_mastodon_video_ships
    media = @subject.upload(@crosspost, config([{"type" => "video", "url" => "https://example.com/media/loop.mp4"}]))

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::NONE, media
    verify { @records_media_fallback.record(@crosspost, "Mastodon video is not supported yet") }
  end

  def test_a_type_mastodon_does_not_take_falls_back
    stub_download(PNG_URL, "<svg/>", "image/svg+xml")

    media = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]))

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::NONE, media
    verify { @records_media_fallback.record(@crosspost, "Mastodon takes JPEG, PNG, GIF and WebP, not image/svg+xml (#{PNG_URL})") }
  end

  def test_a_failed_download_falls_back
    stubs { @downloads_media.download(MediaItem.new(type: "image", url: PNG_URL, alt: ""), max_bytes: MAX_BYTES) }.with {
      Result.failure("Could not download #{PNG_URL}: HTTP 404")
    }

    media = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]))

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::NONE, media
    verify { @records_media_fallback.record(@crosspost, "Could not download #{PNG_URL}: HTTP 404") }
  end

  def test_an_upload_mastodon_refuses_falls_back
    stub_download(PNG_URL, "PNG", "image/png")
    stubs { @calls_mastodon_media_api.upload(@account, bytes: "PNG", extension: ".png", description: "") }.with {
      Result.failure("Mastodon refused the upload (HTTP 413): {}")
    }

    media = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]))

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::NONE, media
    verify { @records_media_fallback.record(@crosspost, "Mastodon refused the upload (HTTP 413): {}") }
  end

  def test_images_past_four_are_dropped_and_recorded
    stub_download(PNG_URL, "PNG", "image/png")
    stub_upload("PNG", ".png", "", id: "2", ready: true)

    media = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}] * 6))

    assert_equal ["2", "2", "2", "2"], media.ids
    verify { @records_media_fallback.record(@crosspost, "Mastodon takes at most 4 images; dropped 2") }
  end

  def test_truncates_alt_text_to_mastodons_limit
    stub_download(PNG_URL, "PNG", "image/png")
    stub_upload("PNG", ".png", ("a" * 1600).truncate(1500), id: "2", ready: true)

    media = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL, "alt" => "a" * 1600}]))

    assert_equal ["2"], media.ids
  end

  def test_an_unexpected_error_falls_back_without_the_access_token
    stub_download(PNG_URL, "PNG", "image/png")
    stubs { @calls_mastodon_media_api.upload(@account, bytes: "PNG", extension: ".png", description: "") }.with {
      raise ArgumentError, %(header Authorization has field value "Bearer a warning\\nSECRET-TOKEN-123", this cannot include CR/LF)
    }

    media = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]))

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::NONE, media
    verify { @records_media_fallback.record(@crosspost, %(ArgumentError: header Authorization has field value "Bearer [FILTERED]", this cannot include CR/LF)) }
  end

  def test_finishing_reports_media_that_is_now_ready
    stubs { @calls_mastodon_media_api.check(@account, "1") }.with { Result.success(true) }

    media = @subject.finish(@crosspost, ["1"])

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::Media.new(ids: ["1"], ready?: true), media
  end

  def test_finishing_reports_media_still_processing
    stubs { @calls_mastodon_media_api.check(@account, "1") }.with { Result.success(false) }

    media = @subject.finish(@crosspost, ["1"])

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::Media.new(ids: ["1"], ready?: false), media
  end

  def test_finishing_falls_back_when_processing_failed
    stubs { @calls_mastodon_media_api.check(@account, "1") }.with { Result.failure("Mastodon could not process media 1 (HTTP 422): {}") }

    media = @subject.finish(@crosspost, ["1"])

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::NONE, media
    verify { @records_media_fallback.record(@crosspost, "Mastodon could not process media 1 (HTTP 422): {}") }
  end

  private

  def config(media)
    CrosspostConfig.new(media:)
  end

  def stub_download(url, bytes, content_type)
    stubs { |m| @downloads_media.download(m.that { |item| item.url == url }, max_bytes: MAX_BYTES) }.with {
      Result.success(DownloadsMedia::Downloaded.new(bytes:, content_type:))
    }
  end

  def stub_upload(bytes, extension, description, id:, ready:)
    stubs { @calls_mastodon_media_api.upload(@account, bytes:, extension:, description:) }.with {
      Result.success(Platforms::Mastodon::CallsMastodonMediaApi::Uploaded.new(id:, ready?: ready))
    }
  end
end
```

- [ ] **Step 3: Run them to see them fail**

Run: `rt "bin/rails test test/lib/platforms/mastodon/calls_mastodon_media_api_test.rb test/lib/platforms/mastodon/uploads_mastodon_media_test.rb"`
Expected: `22 runs, 0 assertions, 0 failures, 22 errors`, each
`NameError: uninitialized constant Platforms::Mastodon::CallsMastodonMediaApi`.

- [ ] **Step 4: Write the implementation**

`app/lib/platforms/mastodon/calls_mastodon_media_api.rb`:

```ruby
class Platforms::Mastodon
  class CallsMastodonMediaApi
    Uploaded = Struct.new(:id, :ready?, keyword_init: true)

    # 200 means Mastodon processed the file at once; 202 means it is still processing
    def upload(account, bytes:, extension:, description:)
      Tempfile.create(["media", extension], binmode: true) do |file|
        file.write(bytes)
        file.rewind
        response = HTTParty.post("#{account.credentials["base_url"]}/api/v2/media",
          headers: authorization(account),
          body: {file:, description: description.presence}.compact)

        if [200, 202].include?(response.code)
          Result.success(Uploaded.new(id: response["id"], ready?: response.code == 200))
        else
          Result.failure("Mastodon refused the upload (HTTP #{response.code}): #{response.body}")
        end
      end
    end

    # 206 means still processing; 200 means the file has its URL
    def check(account, id)
      response = HTTParty.get("#{account.credentials["base_url"]}/api/v1/media/#{id}", headers: authorization(account))

      if [200, 206].include?(response.code)
        Result.success(response.code == 200)
      else
        Result.failure("Mastodon could not process media #{id} (HTTP #{response.code}): #{response.body}")
      end
    end

    private

    def authorization(account)
      {"Authorization" => "Bearer #{account.credentials["access_token"]}"}
    end
  end
end
```

`app/lib/platforms/mastodon/uploads_mastodon_media.rb`:

```ruby
class Platforms::Mastodon
  class UploadsMastodonMedia
    MAX_IMAGES = 4
    MAX_BYTES = 16 * 1024 * 1024
    MAX_DESCRIPTION_LENGTH = 1_500
    EXTENSIONS = {"image/jpeg" => ".jpg", "image/png" => ".png", "image/gif" => ".gif", "image/webp" => ".webp"}.freeze

    Media = Struct.new(:ids, :ready?, keyword_init: true)
    NONE = Media.new(ids: [], ready?: true)

    def initialize
      @parses_media_items = ParsesMediaItems.new
      @selects_media = SelectsMedia.new
      @downloads_media = DownloadsMedia.new
      @calls_mastodon_media_api = CallsMastodonMediaApi.new
      @waits_for_processing = WaitsForProcessing.new
      @records_media_fallback = RecordsMediaFallback.new
      @redacts_bearer_token = RedactsBearerToken.new
    end

    def upload(crosspost, crosspost_config)
      selection = @selects_media.select(@parses_media_items.parse(crosspost_config.media), max_images: MAX_IMAGES)
      return NONE if selection.empty?
      raise MediaUnavailable, "Mastodon video is not supported yet" if selection.video

      uploaded = selection.images.map { |item| upload_image(crosspost.account, item) }
      if selection.dropped.positive?
        @records_media_fallback.record(crosspost, "Mastodon takes at most #{MAX_IMAGES} images; dropped #{selection.dropped}")
      end
      processing = uploaded.reject(&:ready?).map(&:id)
      Media.new(ids: uploaded.map(&:id), ready?: processing.empty? || @waits_for_processing.wait { processed?(crosspost.account, processing) })
    rescue => e
      fall_back(crosspost, e)
    end

    # Checks once on media an earlier attempt left processing
    def finish(crosspost, ids)
      Media.new(ids:, ready?: processed?(crosspost.account, ids))
    rescue => e
      fall_back(crosspost, e)
    end

    private

    def upload_image(account, item)
      download = @downloads_media.download(item, max_bytes: MAX_BYTES)
      raise MediaUnavailable, download.error if download.failure?

      content_type = download.data.content_type
      unless (extension = EXTENSIONS[content_type])
        raise MediaUnavailable, "Mastodon takes JPEG, PNG, GIF and WebP, not #{content_type} (#{item.url})"
      end

      upload = @calls_mastodon_media_api.upload(account, bytes: download.data.bytes, extension:, description: item.alt.truncate(MAX_DESCRIPTION_LENGTH))
      raise MediaUnavailable, upload.error if upload.failure?

      upload.data
    end

    def processed?(account, ids)
      ids.all? { |id|
        check = @calls_mastodon_media_api.check(account, id)
        raise MediaUnavailable, check.error if check.failure?

        check.data
      }
    end

    # Any error in the media step posts the text without media, never fails the post
    def fall_back(crosspost, error)
      reason = error.is_a?(MediaUnavailable) ? error.message : "#{error.class}: #{error.message}"
      @records_media_fallback.record(crosspost, @redacts_bearer_token.redact(reason))
      NONE
    end
  end
end
```

- [ ] **Step 5: Run them to see them pass**

Run: `rt "bin/rails test test/lib/platforms/mastodon/calls_mastodon_media_api_test.rb test/lib/platforms/mastodon/uploads_mastodon_media_test.rb"`
Expected: `22 runs, 39 assertions, 0 failures, 0 errors, 0 skips`.

- [ ] **Step 6: Lint and commit**

Run: `rt "bundle exec standardrb app/lib test/lib"`
Expected: no output.

```bash
cd /tmp/posse-wave2
git add app/lib/platforms/mastodon/calls_mastodon_media_api.rb app/lib/platforms/mastodon/uploads_mastodon_media.rb test/lib/platforms/mastodon/calls_mastodon_media_api_test.rb test/lib/platforms/mastodon/uploads_mastodon_media_test.rb
git commit -F - <<'EOF'
feat: upload a post's images to Mastodon and wait while they process

UploadsMastodonMedia takes the merged media list, keeps up to four images
(JPEG, PNG, GIF or WebP), and uploads each to POST /api/v2/media with its
alt text as the description, truncated to Mastodon's 1,500 characters.
Mastodon answers 202 for a file it is still processing, a GIF above all,
so the uploader polls GET /api/v1/media/:id for up to 60 seconds and says
whether everything is ready.

A video, any other type, a failed download, a refused upload, a failed
processing check or any unexpected error records why in the crosspost's
metadata, with the access token redacted, and the post goes out as text.

Refs #1

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 4: Mastodon posts the images, or finishes later

Branch `feat/mastodon-images`.

**Files:**
- Modify: `app/lib/platforms/mastodon/syndicates_mastodon_post.rb` (whole file below)
- Modify: `app/lib/platforms/mastodon.rb:31-33` (`publish!`, plus `finishable?` and `finish!`)
- Modify: `test/support/vcr_helpers.rb` (whole file below)
- Modify: `docs/feed.md` (the `media` row of the properties table, line 153)
- Test: `test/lib/platforms/mastodon/syndicates_mastodon_post_test.rb`,
  `test/lib/platforms/mastodon_test.rb` (both new)

**Interfaces:**
- Consumes: `UploadsMastodonMedia#upload`, `#finish`, `Media` and `NONE` (Task 3);
  `RedactsBearerToken` (Task 1); `PublishesCrosspost::Result(success?, message, error,
  needs_to_finish?)`.
- Produces:
  - `SyndicatesMastodonPost#syndicate!(crosspost, crosspost_config, crosspost_content)`.
    - Media ready: posts `{status, media_ids}` with `Idempotency-Key: posse-party-crosspost-<id>`.
    - Media still processing: stores `metadata["mastodon_media"] = {"ids", "status"}` and returns
      `needs_to_finish?: true`.
    - No media: posts `{status}`, exactly the body it posted before.
  - `SyndicatesMastodonPost#finish!(crosspost)`: posts the kept status once its media is ready, or
    asks to finish again.
  - `Platforms::Mastodon#publish!` passes `crosspost_config` through; `#finishable?` is true;
    `#finish!(crosspost)` delegates.
  - `perfect_vcr_match` matches headers with `Idempotency-Key` left out. Its `except:` keys
    (`:method`, `:uri`, `:body`, `:headers`) are unchanged.

- [ ] **Step 1: Write the failing tests**

`test/lib/platforms/mastodon/syndicates_mastodon_post_test.rb`. Each status stub matches only the
exact body and the idempotency header, so a wrong body or a missing key leaves the stub unmatched
and the test fails:

```ruby
require "test_helper"

class Platforms::Mastodon::SyndicatesMastodonPostTest < ActiveSupport::TestCase
  STATUSES_URL = "https://mastodon.example/api/v1/statuses"

  def setup
    @uploads_mastodon_media = Mocktail.of_next(Platforms::Mastodon::UploadsMastodonMedia)
    @subject = Platforms::Mastodon::SyndicatesMastodonPost.new
    account = New.create(Account, user: users(:admin), platform_tag: "mastodon", label: "@test", active: true,
      credentials: {"base_url" => "https://mastodon.example", "access_token" => "token"})
    @crosspost = Crosspost.create!(post: posts(:admin_post), account:, status: "wip")
    @config = CrosspostConfig.new(media: [{"type" => "image", "url" => "https://example.com/media/still.png"}])
  end

  def test_posts_the_status_with_its_media_and_an_idempotency_key
    stubs { @uploads_mastodon_media.upload(@crosspost, @config) }.with { media(["1", "2"], ready: true) }
    status = stub_status({status: "A map", media_ids: ["1", "2"]}, id: "900")

    result = @subject.syndicate!(@crosspost, @config, "A map")

    assert result.success?
    assert_requested status
    assert_equal "published", @crosspost.reload.status
    assert_equal "900", @crosspost.remote_id
    assert_equal "https://mastodon.example/@test/900", @crosspost.url
    assert_equal "A map", @crosspost.content
  end

  def test_without_media_posts_the_text_alone
    stubs { @uploads_mastodon_media.upload(@crosspost, @config) }.with { Platforms::Mastodon::UploadsMastodonMedia::NONE }
    status = stub_status({status: "A map"}, id: "901")

    result = @subject.syndicate!(@crosspost, @config, "A map")

    assert result.success?
    assert_requested status
  end

  def test_media_still_processing_is_kept_to_post_later
    @crosspost.update!(metadata: {"post" => "kept"})
    stubs { @uploads_mastodon_media.upload(@crosspost, @config) }.with { media(["1"], ready: false) }

    result = @subject.syndicate!(@crosspost, @config, "A map")

    assert result.success?
    assert result.needs_to_finish?
    assert_equal "wip", @crosspost.reload.status
    assert_equal({"post" => "kept", "mastodon_media" => {"ids" => ["1"], "status" => "A map"}}, @crosspost.metadata)
    assert_not_requested :post, STATUSES_URL
  end

  def test_finishing_posts_the_kept_status_once_its_media_is_ready
    @crosspost.update!(metadata: {"mastodon_media" => {"ids" => ["1"], "status" => "A map"}})
    stubs { @uploads_mastodon_media.finish(@crosspost, ["1"]) }.with { media(["1"], ready: true) }
    status = stub_status({status: "A map", media_ids: ["1"]}, id: "902")

    result = @subject.finish!(@crosspost)

    assert result.success?
    assert_requested status
    assert_equal "published", @crosspost.reload.status
  end

  def test_finishing_asks_again_while_the_media_is_processing
    @crosspost.update!(metadata: {"mastodon_media" => {"ids" => ["1"], "status" => "A map"}})
    stubs { @uploads_mastodon_media.finish(@crosspost, ["1"]) }.with { media(["1"], ready: false) }

    result = @subject.finish!(@crosspost)

    assert result.needs_to_finish?
    assert_not_requested :post, STATUSES_URL
  end

  def test_finishing_with_nothing_kept_fails
    result = @subject.finish!(@crosspost)

    assert_not result.success?
    assert_equal "No Mastodon media is waiting to be posted", result.message
  end

  def test_a_failure_does_not_repeat_the_access_token
    @crosspost.account.update!(credentials: {"base_url" => "https://mastodon.example", "access_token" => "a warning\nSECRET-TOKEN-123"})
    stubs { @uploads_mastodon_media.upload(@crosspost, @config) }.with { Platforms::Mastodon::UploadsMastodonMedia::NONE }

    result = @subject.syndicate!(@crosspost, @config, "A map")

    assert_not result.success?
    assert_includes result.error.message, "Bearer [FILTERED]"
    assert_not_includes result.error.message, "SECRET-TOKEN-123"
  end

  private

  def media(ids, ready:)
    Platforms::Mastodon::UploadsMastodonMedia::Media.new(ids:, ready?: ready)
  end

  def stub_status(body, id:)
    stub_request(:post, STATUSES_URL)
      .with(body: body.to_json, headers: {"Authorization" => "Bearer token", "Idempotency-Key" => "posse-party-crosspost-#{@crosspost.id}"})
      .to_return(status: 200, body: {id:, url: "https://mastodon.example/@test/#{id}"}.to_json, headers: {"Content-Type" => "application/json"})
  end
end
```

`test/lib/platforms/mastodon_test.rb` (the platform class; `test/lib/mastodon_test.rb` holds the
recorded tests):

```ruby
require "test_helper"

class Platforms::MastodonTest < ActiveSupport::TestCase
  def setup
    @syndicates_mastodon_post = Mocktail.of_next(Platforms::Mastodon::SyndicatesMastodonPost)
    @subject = Platforms::Mastodon.new
    @crosspost = crossposts(:admin_mastodon_crosspost)
  end

  def test_publishes_with_the_crosspost_config
    config = CrosspostConfig.new(media: [])
    stubs { @syndicates_mastodon_post.syndicate!(@crosspost, config, "A map") }.with { PublishesCrosspost::Result.new(success?: true) }

    result = @subject.publish!(@crosspost, config, PublishesCrosspost::IdentifiesPatternRanges::Result.new("A map", []))

    assert result.success?
  end

  def test_finishes_a_post_left_waiting_on_media
    stubs { @syndicates_mastodon_post.finish!(@crosspost) }.with { PublishesCrosspost::Result.new(success?: true) }

    assert @subject.finishable?
    assert @subject.finish!(@crosspost).success?
  end
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `rt "bin/rails test test/lib/platforms/mastodon/syndicates_mastodon_post_test.rb test/lib/platforms/mastodon_test.rb"`
Expected: `9 runs, 0 assertions, 0 failures, 9 errors`.
- Five are `ArgumentError: wrong number of arguments (given 3, …)`: four `syndicate!` calls in the
  syndicator test, and one Mocktail stub in the platform test. Mocktail checks a stubbed call
  against the real method's signature.
- Four are `NoMethodError` for `finish!`: three calls, and one Mocktail stub.

- [ ] **Step 3: Write the implementation**

`app/lib/platforms/mastodon/syndicates_mastodon_post.rb`, whole file:

```ruby
class Platforms::Mastodon
  class SyndicatesMastodonPost
    def initialize
      @uploads_mastodon_media = UploadsMastodonMedia.new
      @redacts_bearer_token = RedactsBearerToken.new
    end

    def syndicate!(crosspost, crosspost_config, crosspost_content)
      post_or_finish_later!(crosspost, crosspost_content, @uploads_mastodon_media.upload(crosspost, crosspost_config))
    rescue => e
      failure(e)
    end

    def finish!(crosspost)
      kept = crosspost.metadata["mastodon_media"]
      return PublishesCrosspost::Result.new(success?: false, message: "No Mastodon media is waiting to be posted") if kept.blank?

      post_or_finish_later!(crosspost, kept["status"], @uploads_mastodon_media.finish(crosspost, kept["ids"]))
    rescue => e
      failure(e)
    end

    private

    def post_or_finish_later!(crosspost, status, media)
      if media.ready?
        post!(crosspost, status, media.ids)
      else
        # FinishCrosspostJob checks again and posts once Mastodon has processed the media
        crosspost.update!(metadata: crosspost.metadata.merge("mastodon_media" => {"ids" => media.ids, "status" => status}))
        PublishesCrosspost::Result.new(success?: true, needs_to_finish?: true)
      end
    end

    def post!(crosspost, status, media_ids)
      response = HTTParty.post(
        "#{crosspost.account.credentials["base_url"]}/api/v1/statuses",
        headers: {
          "Authorization" => "Bearer #{crosspost.account.credentials["access_token"]}",
          "Content-Type" => "application/json",
          # Mastodon returns the status it already made for a key it has seen in the last hour
          "Idempotency-Key" => "posse-party-crosspost-#{crosspost.id}"
        },
        body: {status:, media_ids: media_ids.presence}.compact.to_json
      )

      if response.success? && (post_id = response.dig("id")).present?
        crosspost.update!(
          remote_id: post_id,
          url: response["url"],
          content: status,
          status: "published",
          published_at: Now.time
        )
        PublishesCrosspost::Result.new(success?: true)
      else
        PublishesCrosspost::Result.new(
          success?: false,
          message: "Failed to create Mastodon post (HTTP #{response.code}). Response: #{response.body}"
        )
      end
    end

    def failure(error)
      PublishesCrosspost::Result.new(success?: false, message: "Failed to syndicate to Mastodon", error: error.exception(@redacts_bearer_token.redact(error.message)))
    end
  end
end
```

`error.exception(message)` copies the exception with a new message and keeps its class and
backtrace, so the failure the crosspost page shows has the token redacted.

In `app/lib/platforms/mastodon.rb`, replace:

```ruby
    def publish!(crosspost, crosspost_config, crosspost_content)
      @syndicates_mastodon_post.syndicate!(crosspost, crosspost_content.string)
    end
```

with:

```ruby
    def publish!(crosspost, crosspost_config, crosspost_content)
      @syndicates_mastodon_post.syndicate!(crosspost, crosspost_config, crosspost_content.string)
    end

    def finishable?
      true
    end

    def finish!(crosspost)
      @syndicates_mastodon_post.finish!(crosspost)
    end
```

`test/support/vcr_helpers.rb`, whole file. Upstream's three Mastodon cassettes were recorded without
an idempotency key, and the recorded tests' crosspost IDs differ on every run, so header matching
leaves the key out:

```ruby
VCR.configure do |config|
  config.cassette_library_dir = "test/support/vcr_cassettes"
  config.allow_http_connections_when_no_cassette = true
  config.hook_into :webmock
  # Mastodon's Idempotency-Key names the crosspost, whose ID differs from one test run to the next
  config.register_request_matcher(:headers_but_idempotency_key) { |recorded, made|
    recorded.headers.except("Idempotency-Key") == made.headers.except("Idempotency-Key")
  }
end

module VcrHelpers
  MATCHERS = {method: :method, uri: :uri, body: :body, headers: :headers_but_idempotency_key}.freeze

  def perfect_vcr_match(cassette, record: false, time: nil, except: [], &blk)
    FileUtils.rm_f("test/support/vcr_cassettes/#{cassette}.yml") if record
    VCR.use_cassette(cassette, record: (record ? :all : :none), match_requests_on: MATCHERS.except(*except).values, allow_playback_repeats: false) do
      puts_sql_changes(enabled: record) do
        if time.present?
          fake_time!(time, freeze: true, &blk)
        else
          blk.call
        end
      end
    end
  end

  def vcr_secrets(hash)
    VCR.configure do |config|
      hash.each do |k, v|
        # When real secrets are absent, use deterministic per-key placeholders
        # so that each secret position is distinguishable and validated.
        placeholder = v || "SOME_#{k.to_s.upcase}"
        config.filter_sensitive_data("{{#{k}}}") { placeholder }
      end
    end

    return hash unless hash.values.any?(&:nil?)
    hash.map { |k, v| [k, v || "SOME_#{k.to_s.upcase}"] }.to_h
  end

  def puts_sql_changes(io: $stdout, enabled: true, &blk)
    return blk.call unless enabled

    writes = []
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*_args, payload|
      next if payload[:name] == "SCHEMA"
      if /\A\s*(INSERT|UPDATE|DELETE)\b/i.match?(sql = payload[:sql])
        writes << [sql, payload[:type_casted_binds] || payload[:binds]]
      end
    end

    blk.call
  ensure
    if enabled
      ActiveSupport::Notifications.unsubscribe(sub) if sub
      io.puts "== SQL INSERT, UPDATE, DELETE statements =="
      writes.each do |sql, binds|
        if binds&.any?
          bind_str = binds.map { |b| b.respond_to?(:name) ? "#{b.name}=#{b.value_before_type_cast.inspect}" : b.inspect }.join(", ")
          io.puts "#{sql}  /* binds: #{bind_str} */"
        else
          io.puts sql
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run them to see them pass, along with every recorded platform test**

Run: `rt "bin/rails test test/lib/platforms/mastodon test/lib/platforms/mastodon_test.rb test/lib/mastodon_test.rb test/lib/bsky_test.rb test/lib/linkedin_test.rb"`
Expected: `37 runs, 133 assertions, 0 failures, 0 errors, 0 skips`. Upstream's `mastodon_take`,
`mastodon_shot` and `mastodon_take_href` still replay, with the new header ignored. Without the
`vcr_helpers.rb` change, `MastodonTest#test_syndication` fails with
`An HTTP request has been made that VCR does not know how to handle … Idempotency-Key`.

- [ ] **Step 5: Say what Mastodon now does with `media`**

In `docs/feed.md`, replace the `media` row of the properties table:

```markdown
| `media` | array<object> | Media attachments used by certain platforms (Instagram requires images/video; YouTube requires exactly one video). When present, `media.poster_url` is used by platforms that support custom covers/thumbnails (such as Instagram Reels and YouTube). |
```

with:

```markdown
| `media` | array<object> | Media attachments used by certain platforms (Instagram requires images/video; YouTube requires exactly one video; Mastodon posts up to 4 JPEG, PNG, GIF or WebP images, and does not post video yet). When present, `media.poster_url` is used by platforms that support custom covers/thumbnails (such as Instagram Reels and YouTube). When Mastodon cannot post an image, the post goes out as text and the reason is recorded in the crosspost's metadata. |
```

`feat/bsky-images` and `feat/linkedin-images` change the same row, so the deploy merge in Task 13
conflicts here and resolves it with one combined row.

- [ ] **Step 6: Run the full suite**

Run: `rt "CI=true ./script/test" > /tmp/posse-wave2-mastodon.log 2>&1; grep "runs," /tmp/posse-wave2-mastodon.log; git -C /tmp/posse-wave2 status --short`
Expected: `387 runs, ... 0 failures, 0 errors` and `24 runs, ... 0 failures, 0 errors`. `git status`
lists only the files this task changed.

- [ ] **Step 7: Lint and commit**

Run: `rt "bundle exec standardrb app/lib test/lib test/support"`
Expected: no output.

```bash
cd /tmp/posse-wave2
git add app/lib/platforms/mastodon.rb app/lib/platforms/mastodon/syndicates_mastodon_post.rb test/support/vcr_helpers.rb docs/feed.md test/lib/platforms/mastodon_test.rb test/lib/platforms/mastodon/syndicates_mastodon_post_test.rb
git commit -F - <<'EOF'
feat: post a feed's images natively on Mastodon

A Mastodon status now carries the images a feed sends, uploaded and, when
Mastodon is still processing one, waited for. When the wait runs out, the
crosspost keeps the media IDs and its text in its metadata and asks to be
finished later; FinishCrosspostJob checks again and posts once Mastodon
is done, or posts the text alone if processing failed.

Every status now carries an Idempotency-Key naming the crosspost, so a
retry after a lost response returns the status Mastodon already made
instead of posting it twice. VCR header matching leaves that key out,
because the crosspost ID differs on every test run.

A failure no longer repeats the access token in its message.

Refs #1

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 5: Write the recorded Mastodon tests

Branch `feat/mastodon-images`. The tests are written now and fail for want of cassettes. Task 11
records them.

**Files:**
- Modify: `test/lib/mastodon_test.rb` (two tests and three helpers appended)

**Interfaces:**
- Consumes: the wave-1 fixtures at `914ff83` on GitHub; `vcr_secrets`, `perfect_vcr_match`
  (`test/support/vcr_helpers.rb`).

- [ ] **Step 1: Write the recorded tests**

Append to `test/lib/mastodon_test.rb`, inside the class, after the last test's `end`, leaving a blank
line:

```ruby
  MEDIA_BASE = "https://raw.githubusercontent.com/jknowles/posse_party/914ff8332cb956c77ac45a0dd182dc8a47f862a7/test/fixtures/files/media"
  BASE_URL = ENV.fetch("MASTODON_BASE_URL", "https://mastodon.example")

  def test_mastodon_posts_several_images
    crosspost = mastodon_crosspost_with_media("https://example.com/social/stills/", [
      {"type" => "image", "url" => "#{MEDIA_BASE}/still.jpg", "alt" => "An orange square", "mime" => "image/jpeg"},
      {"type" => "image", "url" => "#{MEDIA_BASE}/still.png", "alt" => "A navy square", "mime" => "image/png"}
    ])

    perfect_vcr_match("mastodon_multi_image", except: [:body, :headers]) do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_published_with_media crosspost, "https://example.com/social/stills/", media_count: 2
    assert_uploaded "image/jpeg", "An orange square"
    assert_uploaded "image/png", "A navy square"
  end

  def test_mastodon_posts_a_gif_from_its_platform_override
    crosspost = mastodon_crosspost_with_media("https://example.com/social/loop/", [
      {"type" => "video", "url" => "#{MEDIA_BASE}/loop.mp4", "presentation" => "gif"}
    ], mastodon_media: [
      {"type" => "image", "url" => "#{MEDIA_BASE}/loop.gif", "alt" => "Orange, navy and paper squares in turn", "mime" => "image/gif"}
    ])

    perfect_vcr_match("mastodon_gif", except: [:body, :headers]) do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_published_with_media crosspost, "https://example.com/social/loop/", media_count: 1
    assert_uploaded "image/gif", "Orange, navy and paper squares in turn"
    assert_not_requested(:get, "#{MEDIA_BASE}/loop.mp4")
  end

  private

  def mastodon_crosspost_with_media(post_url, media, mastodon_media: media)
    user = New.create(User, email: "user@example.com")
    user.accounts.create!(platform_tag: "mastodon", label: "Mastodon", credentials: vcr_secrets({
      "base_url" => BASE_URL,
      "access_token" => ENV["MASTODON_ACCESS_TOKEN"]
    }))
    posse = {
      syndicate: true,
      format_string: "{{content}}",
      content: "PosseParty media test (deleted after recording)",
      media:,
      platform_overrides: {mastodon: {media: mastodon_media, append_url: true, append_url_spacer: "\n\n"}}
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

  # The status carries the uploaded media, the entry's URL appended to the text, and the
  # crosspost's idempotency key
  def assert_published_with_media(crosspost, post_url, media_count:)
    crosspost.reload
    assert_empty crosspost.failures
    assert_equal "published", crosspost.status
    assert_nil crosspost.metadata["media_fallback"]
    assert_match %r{\A#{Regexp.escape(BASE_URL)}/@\w+/\d+\z}o, crosspost.url
    assert_requested(:post, "#{BASE_URL}/api/v1/statuses", headers: {"Idempotency-Key" => "posse-party-crosspost-#{crosspost.id}"}) { |request|
      body = JSON.parse(request.body)
      body["status"] == "PosseParty media test (deleted after recording)\n\n#{post_url}" && body["media_ids"].size == media_count
    }
  end

  def assert_uploaded(content_type, description)
    assert_requested(:post, "#{BASE_URL}/api/v2/media") { |request|
      request.body.include?("Content-Type: #{content_type}\r\n") && request.body.include?(%(name="description"\r\n\r\n#{description}))
    }
  end
```

What each piece pins:

- `vcr_secrets` stores the instance URL as `{{base_url}}` and the token as `{{access_token}}`. With
  no environment set, they replay as `https://mastodon.example` and `SOME_ACCESS_TOKEN`, so the test
  never names the instance and runs offline.
- `except: [:body, :headers]` is needed because each multipart upload has a random boundary.
  `assert_published_with_media` and `assert_uploaded` check the bodies and the idempotency key
  instead.
- `assert_nil crosspost.metadata["media_fallback"]` tells a post with its media apart from a silent
  fallback to text.
- The GIF test's top-level item is the loop MP4 that civilytics.com sends; Mastodon must take the GIF
  from its override and never fetch the MP4.

- [ ] **Step 2: Run them to see them fail**

Run: `rt "bin/rails test test/lib/mastodon_test.rb"`
Expected: `3 runs, ... 2 failures`. Both new tests fail at `assert_empty crosspost.failures`, with
`An HTTP request has been made that VCR does not know how to handle`. Upstream's test passes.

The failure also shows the fallback working: VCR blocked the media download, the uploader recorded
it, and the post went on to try the status as text.

- [ ] **Step 3: Lint and commit**

Run: `rt "bundle exec standardrb test/lib"`
Expected: no output.

```bash
cd /tmp/posse-wave2
git add test/lib/mastodon_test.rb
git commit -F - <<'EOF'
test: Mastodon posts several images and a GIF

Two recorded tests through PublishesCrosspost, each from a feed entry
carrying media. They check that the status carries the uploaded media,
the entry's URL and the crosspost's idempotency key, and that no media
fallback was recorded. Cassettes follow once recorded.

Refs #1

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 6: Upload Bluesky blobs in one place

Branch `feat/bsky-images`, created from `feat/media-foundation` with `origin/fix/bsky-fit-thumbnail`
merged in first.

**Files:**
- Create: `app/lib/platforms/bsky/uploads_bsky_blob.rb`
- Modify: `app/lib/platforms/bsky/attaches_web_card.rb` (whole file below)
- Test: `test/lib/platforms/bsky/uploads_bsky_blob_test.rb` (new),
  `test/lib/platforms/bsky/attaches_web_card_test.rb` (a `require` and two tests)

**Interfaces:**
- Consumes: `DownloadsMedia`, `MediaItem` (wave 1); `FitsImageWithinByteLimit#fit(bytes,
  content_type, max_bytes:) -> Result(FittedImage(bytes, content_type))` (from
  `fix/bsky-fit-thumbnail`).
- Produces: `Platforms::Bsky::UploadsBskyBlob#upload(bytes, content_type, record_manager) -> Result`.
  On success `data` is the blob Hash Bluesky returns; a refusal or network error is a failure with a
  sentence. `record_manager` is a `Bskyrb::RecordManager`, whose `session` answers `pds` and
  `access_token`.

- [ ] **Step 1: Create the branch**

```bash
cd /tmp/posse-wave2
git switch -c feat/bsky-images feat/media-foundation
git merge --no-edit origin/fix/bsky-fit-thumbnail
```

Expected: `Merge made by the 'ort' strategy`, with 4 files changed.

- [ ] **Step 2: Write the failing tests**

`test/lib/platforms/bsky/uploads_bsky_blob_test.rb`. A small `Session` Struct stands in for
`Bskyrb::Session`, whose constructor would log in:

```ruby
require "test_helper"

class Platforms::Bsky::UploadsBskyBlobTest < ActiveSupport::TestCase
  Session = Struct.new(:pds, :access_token, :did, keyword_init: true)
  UPLOAD_URL = "https://bsky.social/xrpc/com.atproto.repo.uploadBlob"
  BLOB = {"$type" => "blob", "ref" => {"$link" => "bafkreiexample"}, "mimeType" => "image/png", "size" => 3}

  def setup
    @subject = Platforms::Bsky::UploadsBskyBlob.new
    @record_manager = Bskyrb::RecordManager.new(Session.new(pds: "https://bsky.social", access_token: "jwt"))
  end

  def test_uploads_the_bytes_with_their_content_type_and_returns_the_blob
    upload = stub_request(:post, UPLOAD_URL)
      .with(body: "PNG", headers: {"Authorization" => "Bearer jwt", "Content-Type" => "image/png"})
      .to_return(status: 200, body: {blob: BLOB}.to_json, headers: {"Content-Type" => "application/json"})

    result = @subject.upload("PNG", "image/png", @record_manager)

    assert result.success?
    assert_equal BLOB, result.data
    assert_requested upload
  end

  def test_reports_an_upload_bluesky_refuses
    stub_request(:post, UPLOAD_URL).to_return(status: 400, body: {error: "InvalidRequest", message: "Blob too large"}.to_json, headers: {"Content-Type" => "application/json"})

    result = @subject.upload("PNG", "image/png", @record_manager)

    assert result.failure?
    assert_equal %(Bluesky refused the upload (HTTP 400): {"error":"InvalidRequest","message":"Blob too large"}), result.error
  end

  def test_reports_a_connection_error
    stub_request(:post, UPLOAD_URL).to_timeout

    result = @subject.upload("PNG", "image/png", @record_manager)

    assert_match(/\ACould not upload to Bluesky: /, result.error)
  end
end
```

In `test/lib/platforms/bsky/attaches_web_card_test.rb`, add `require "vips"` after
`require "test_helper"`, and append inside the class, after the last test's `end`, leaving a blank
line:

```ruby
  def test_uploads_an_og_image_behind_a_redirect_as_the_thumb
    uploads_bsky_blob = Mocktail.of_next(Platforms::Bsky::UploadsBskyBlob)
    subject = Platforms::Bsky::AttachesWebCard.new
    png = Vips::Image.black(10, 10, bands: 3).write_to_buffer(".png")
    blob = {"$type" => "blob", "ref" => {"$link" => "bafkreiexample"}, "mimeType" => "image/png", "size" => png.bytesize}
    stub_request(:get, "https://example.com/og.png").to_return(status: 301, headers: {"Location" => "https://cdn.example.com/og.png"})
    stub_request(:get, "https://cdn.example.com/og.png").to_return(status: 200, body: png, headers: {"Content-Type" => "image/png"})
    stubs { uploads_bsky_blob.upload(png, "image/png", :record_manager) }.with { Result.success(blob) }

    result = subject.attach!(CrosspostConfig.new(url: "https://example.com/posts/123", title: "A title", og_image: "https://example.com/og.png"), :record_manager)

    assert_equal blob, result["external"]["thumb"]
  end

  def test_a_thumb_bluesky_refuses_fails_the_post_as_before
    uploads_bsky_blob = Mocktail.of_next(Platforms::Bsky::UploadsBskyBlob)
    subject = Platforms::Bsky::AttachesWebCard.new
    png = Vips::Image.black(10, 10, bands: 3).write_to_buffer(".png")
    stub_request(:get, "https://example.com/og.png").to_return(status: 200, body: png, headers: {"Content-Type" => "image/png"})
    stubs { uploads_bsky_blob.upload(png, "image/png", :record_manager) }.with { Result.failure("Bluesky refused the upload (HTTP 400): {}") }

    error = assert_raises(RuntimeError) {
      subject.attach!(CrosspostConfig.new(url: "https://example.com/posts/123", title: "A title", og_image: "https://example.com/og.png"), :record_manager)
    }

    assert_equal "Failed to upload og_image: https://example.com/og.png to Bsky. Bluesky refused the upload (HTTP 400): {}", error.message
  end
```

The first test is the redirect fix the spec asks for: `Net::HTTP.get_response` did not follow one.
The second pins today's behavior on a refused thumbnail, which this wave keeps.

- [ ] **Step 3: Run them to see them fail**

Run: `rt "bin/rails test test/lib/platforms/bsky/uploads_bsky_blob_test.rb test/lib/platforms/bsky/attaches_web_card_test.rb"`
Expected: `7 runs, ... 0 failures, 5 errors`, each
`NameError: uninitialized constant Platforms::Bsky::UploadsBskyBlob`. The two existing card tests
pass.

- [ ] **Step 4: Write the implementation**

`app/lib/platforms/bsky/uploads_bsky_blob.rb`:

```ruby
class Platforms::Bsky
  class UploadsBskyBlob
    # Dropping down to do this ourselves b/c the bsky gem assumes you're reading the image from a file
    # https://github.com/ShreyanJain9/bskyrb/blob/main/lib/bskyrb/records.rb#L36
    def upload(bytes, content_type, record_manager)
      response = HTTParty.post(
        record_manager.upload_blob_uri(record_manager.session.pds),
        body: bytes,
        headers: record_manager.default_authenticated_headers(record_manager.session).merge("Content-Type" => content_type)
      )

      if response.success?
        Result.success(response["blob"])
      else
        Result.failure("Bluesky refused the upload (HTTP #{response.code}): #{response.body}")
      end
    rescue => e
      Result.failure("Could not upload to Bluesky: #{e.message}")
    end
  end
end
```

`app/lib/platforms/bsky/attaches_web_card.rb`, whole file. The class is defined in compact style
(`class Platforms::Bsky::AttachesWebCard`), so it names `Platforms::Bsky::UploadsBskyBlob` in full;
a bare `UploadsBskyBlob` would not resolve there.

```ruby
class Platforms::Bsky::AttachesWebCard
  # Bluesky rejects the whole post record when a blob is over this size
  THUMB_MAX_BYTES = 1_000_000
  # A larger og:image is scaled down to fit, so the download may be bigger than the thumb
  MAX_DOWNLOAD_BYTES = 20 * 1024 * 1024

  def initialize
    @downloads_media = DownloadsMedia.new
    @fits_image_within_byte_limit = FitsImageWithinByteLimit.new
    @uploads_bsky_blob = Platforms::Bsky::UploadsBskyBlob.new
  end

  def attach!(crosspost_config, record_manager)
    {
      "$type" => "app.bsky.embed.external",
      "external" => {
        "uri" => crosspost_config.url,
        "title" => crosspost_config.og_title.presence || crosspost_config.title,
        "description" => crosspost_config.og_description.presence || crosspost_config.summary.presence || crosspost_config.title.presence || "",
        "thumb" => upload_thumbnail!(crosspost_config.og_image, record_manager)
      }.compact
    }
  end

  private

  def upload_thumbnail!(image_url, record_manager)
    return if image_url.blank?

    download = @downloads_media.download(MediaItem.new(type: "image", url: image_url), max_bytes: MAX_DOWNLOAD_BYTES)
    raise "Failed to download og_image: #{image_url}. #{download.error}" if download.failure?

    fit_result = @fits_image_within_byte_limit.fit(download.data.bytes, download.data.content_type, max_bytes: THUMB_MAX_BYTES)
    if fit_result.failure?
      Rails.logger.warn("Posting Bsky web card without a thumbnail for og_image #{image_url}: #{fit_result.error}")
      return
    end

    upload = @uploads_bsky_blob.upload(fit_result.data.bytes, fit_result.data.content_type, record_manager)
    raise "Failed to upload og_image: #{image_url} to Bsky. #{upload.error}" if upload.failure?

    upload.data
  end
end
```

- [ ] **Step 5: Run them to see them pass, along with the recorded Bluesky tests**

Run: `rt "bin/rails test test/lib/platforms/bsky test/lib/bsky_test.rb test/lib/fits_image_within_byte_limit_test.rb"`
Expected: `14 runs, 58 assertions, 0 failures, 0 errors, 0 skips`. `bsky_shot` still replays, which
shows the og:image now downloads through `DownloadsMedia` with the same request.

- [ ] **Step 6: Lint and commit**

Run: `rt "bundle exec standardrb app/lib test/lib"`
Expected: no output.

```bash
cd /tmp/posse-wave2
git add app/lib/platforms/bsky/uploads_bsky_blob.rb app/lib/platforms/bsky/attaches_web_card.rb test/lib/platforms/bsky/uploads_bsky_blob_test.rb test/lib/platforms/bsky/attaches_web_card_test.rb
git commit -F - <<'EOF'
refactor: upload Bluesky blobs in one place, and fetch og:image through DownloadsMedia

UploadsBskyBlob is the blob upload AttachesWebCard did inline, returning
a Result, so the image step can share it. The card's og:image now
downloads through DownloadsMedia, which follows redirects (Net::HTTP's
get_response did not) and caps the download at 20 MB before the image is
shrunk to Bluesky's 1 MB thumbnail limit. A thumbnail that cannot be
downloaded or uploaded still fails the post, as before, and now says why.

Refs #1

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 7: Bluesky uploads images with alt text and aspect ratio

Branch `feat/bsky-images`.

**Files:**
- Create: `app/lib/platforms/bsky/measures_aspect_ratio.rb`, `app/lib/platforms/bsky/uploads_bsky_media.rb`
- Test: `test/lib/platforms/bsky/measures_aspect_ratio_test.rb`,
  `test/lib/platforms/bsky/uploads_bsky_media_test.rb`

**Interfaces:**
- Consumes: `UploadsBskyBlob` (Task 6); `FitsImageWithinByteLimit`; the wave-1 media pieces.
- Produces:
  - `Platforms::Bsky::MeasuresAspectRatio#measure(item, bytes) -> {"width", "height"} | nil`. It
    uses the item's `width` and `height` when both are set, otherwise reads the image header with
    libvips, and returns `nil` when neither works.
  - `Platforms::Bsky::UploadsBskyMedia#upload(crosspost, crosspost_config, record_manager) ->
    [Hash]`: the `app.bsky.embed.images` entries (`alt`, `image`, and `aspectRatio` when known), or
    `[]` when the post goes out without media. It never raises: every failure records a fallback.
    Constants: `MAX_IMAGES = 4`, `MAX_IMAGE_BYTES = 2_000_000`, `MAX_DOWNLOAD_BYTES = 20 MB`,
    `CONTENT_TYPES` for JPEG, PNG, WebP and GIF.

- [ ] **Step 1: Write the failing tests**

`test/lib/platforms/bsky/measures_aspect_ratio_test.rb`:

```ruby
require "test_helper"
require "vips"

class Platforms::Bsky::MeasuresAspectRatioTest < ActiveSupport::TestCase
  def setup
    @subject = Platforms::Bsky::MeasuresAspectRatio.new
    @png = Vips::Image.black(300, 200, bands: 3).write_to_buffer(".png")
  end

  def test_takes_the_width_and_height_the_feed_sends
    item = MediaItem.new(type: "image", url: "https://example.com/a.png", width: 1600, height: 900)

    assert_equal({"width" => 1600, "height" => 900}, @subject.measure(item, @png))
  end

  def test_reads_the_size_from_the_image_when_the_feed_sends_none
    item = MediaItem.new(type: "image", url: "https://example.com/a.png")

    assert_equal({"width" => 300, "height" => 200}, @subject.measure(item, @png))
  end

  def test_reads_the_size_from_the_image_when_the_feed_sends_only_a_width
    item = MediaItem.new(type: "image", url: "https://example.com/a.png", width: 1600)

    assert_equal({"width" => 300, "height" => 200}, @subject.measure(item, @png))
  end

  def test_measures_nothing_in_bytes_that_are_not_an_image
    item = MediaItem.new(type: "image", url: "https://example.com/a.png")

    assert_nil @subject.measure(item, "<html>not an image</html>")
  end
end
```

`test/lib/platforms/bsky/uploads_bsky_media_test.rb`. `:record_manager` stands in for the real one,
which only `UploadsBskyBlob` uses, and that is mocked:

```ruby
require "test_helper"

class Platforms::Bsky::UploadsBskyMediaTest < ActiveSupport::TestCase
  JPG_URL = "https://example.com/media/still.jpg"
  PNG_URL = "https://example.com/media/still.png"
  MAX_DOWNLOAD_BYTES = 20 * 1024 * 1024

  def setup
    @downloads_media = Mocktail.of_next(DownloadsMedia)
    @fits_image_within_byte_limit = Mocktail.of_next(FitsImageWithinByteLimit)
    @measures_aspect_ratio = Mocktail.of_next(Platforms::Bsky::MeasuresAspectRatio)
    @uploads_bsky_blob = Mocktail.of_next(Platforms::Bsky::UploadsBskyBlob)
    @records_media_fallback = Mocktail.of_next(RecordsMediaFallback)
    @subject = Platforms::Bsky::UploadsBskyMedia.new
    @crosspost = crossposts(:admin_bsky_crosspost)
  end

  def test_uploads_each_image_with_its_alt_text_and_aspect_ratio
    stub_image(JPG_URL, "JPG", "image/jpeg", blob: "blob-1", aspect_ratio: {"width" => 4, "height" => 3})
    stub_image(PNG_URL, "PNG", "image/png", blob: "blob-2", aspect_ratio: nil)

    images = @subject.upload(@crosspost, config([
      {"type" => "image", "url" => JPG_URL, "alt" => "An orange square"},
      {"type" => "image", "url" => PNG_URL}
    ]), :record_manager)

    assert_equal [
      {"alt" => "An orange square", "image" => "blob-1", "aspectRatio" => {"width" => 4, "height" => 3}},
      {"alt" => "", "image" => "blob-2"}
    ], images
    verify_never_called { @records_media_fallback.record }
  end

  def test_no_media_uploads_nothing
    assert_equal [], @subject.upload(@crosspost, config(nil), :record_manager)
    verify_never_called { @downloads_media.download }
  end

  def test_a_video_falls_back_until_bluesky_video_ships
    images = @subject.upload(@crosspost, config([{"type" => "video", "url" => "https://example.com/media/loop.mp4"}]), :record_manager)

    assert_equal [], images
    verify { @records_media_fallback.record(@crosspost, "Bluesky video is not supported yet") }
  end

  def test_a_type_bluesky_does_not_take_falls_back
    stub_download(PNG_URL, "<svg/>", "image/svg+xml")

    images = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]), :record_manager)

    assert_equal [], images
    verify { @records_media_fallback.record(@crosspost, "Bluesky takes JPEG, PNG, WebP and GIF, not image/svg+xml (#{PNG_URL})") }
  end

  def test_a_failed_download_falls_back
    stubs { @downloads_media.download(MediaItem.new(type: "image", url: PNG_URL, alt: ""), max_bytes: MAX_DOWNLOAD_BYTES) }.with {
      Result.failure("Could not download #{PNG_URL}: HTTP 404")
    }

    images = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]), :record_manager)

    assert_equal [], images
    verify { @records_media_fallback.record(@crosspost, "Could not download #{PNG_URL}: HTTP 404") }
  end

  def test_an_image_that_cannot_be_brought_within_two_megabytes_falls_back
    stub_download(PNG_URL, "PNG", "image/png")
    stubs { @fits_image_within_byte_limit.fit("PNG", "image/png", max_bytes: 2_000_000) }.with { Result.failure("could not fit image within 2000000 bytes") }

    images = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]), :record_manager)

    assert_equal [], images
    verify { @records_media_fallback.record(@crosspost, "Could not fit #{PNG_URL} within Bluesky's 2000000 bytes: could not fit image within 2000000 bytes") }
  end

  def test_an_upload_bluesky_refuses_falls_back
    stub_download(PNG_URL, "PNG", "image/png")
    stubs { @fits_image_within_byte_limit.fit("PNG", "image/png", max_bytes: 2_000_000) }.with { fitted("PNG", "image/png") }
    stubs { @uploads_bsky_blob.upload("PNG", "image/png", :record_manager) }.with { Result.failure("Bluesky refused the upload (HTTP 400): {}") }

    images = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]), :record_manager)

    assert_equal [], images
    verify { @records_media_fallback.record(@crosspost, "Bluesky refused the upload (HTTP 400): {}") }
  end

  def test_images_past_four_are_dropped_and_recorded
    stub_image(PNG_URL, "PNG", "image/png", blob: "blob-2", aspect_ratio: nil)

    images = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}] * 5), :record_manager)

    assert_equal 4, images.size
    verify { @records_media_fallback.record(@crosspost, "Bluesky takes at most 4 images; dropped 1") }
  end

  def test_an_unexpected_error_falls_back
    stub_download(PNG_URL, "PNG", "image/png")
    stubs { @fits_image_within_byte_limit.fit("PNG", "image/png", max_bytes: 2_000_000) }.with { raise NoMethodError, "undefined method 'bytes' for nil" }

    images = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]), :record_manager)

    assert_equal [], images
    verify { @records_media_fallback.record(@crosspost, "NoMethodError: undefined method 'bytes' for nil") }
  end

  private

  def config(media)
    CrosspostConfig.new(media:)
  end

  def fitted(bytes, content_type)
    Result.success(FitsImageWithinByteLimit::FittedImage.new(bytes:, content_type:))
  end

  def stub_download(url, bytes, content_type)
    stubs { |m| @downloads_media.download(m.that { |item| item.url == url }, max_bytes: MAX_DOWNLOAD_BYTES) }.with {
      Result.success(DownloadsMedia::Downloaded.new(bytes:, content_type:))
    }
  end

  def stub_image(url, bytes, content_type, blob:, aspect_ratio:)
    stub_download(url, bytes, content_type)
    stubs { @fits_image_within_byte_limit.fit(bytes, content_type, max_bytes: 2_000_000) }.with { fitted(bytes, content_type) }
    stubs { @uploads_bsky_blob.upload(bytes, content_type, :record_manager) }.with { Result.success(blob) }
    stubs { |m| @measures_aspect_ratio.measure(m.that { |item| item.url == url }, bytes) }.with { aspect_ratio }
  end
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `rt "bin/rails test test/lib/platforms/bsky/measures_aspect_ratio_test.rb test/lib/platforms/bsky/uploads_bsky_media_test.rb"`
Expected: `13 runs, 0 assertions, 0 failures, 13 errors`, each
`NameError: uninitialized constant Platforms::Bsky::MeasuresAspectRatio`.

- [ ] **Step 3: Write the implementation**

`app/lib/platforms/bsky/measures_aspect_ratio.rb`. The two `rescue` clauses stay separate: when
`require "vips"` fails, the constant `Vips::Error` does not exist to be named.

```ruby
class Platforms::Bsky
  class MeasuresAspectRatio
    # The feed's width and height win; without both, libvips reads them from the image header.
    # Bluesky treats the aspect ratio as optional, so an unreadable image gets none.
    def measure(item, bytes)
      width, height = (item.width && item.height) ? [item.width, item.height] : read(bytes)
      {"width" => width, "height" => height} if width && height
    end

    private

    def read(bytes)
      require "vips"
      image = Vips::Image.new_from_buffer(bytes, "")
      [image.width, image.height]
    rescue LoadError
      nil
    rescue Vips::Error
      nil
    end
  end
end
```

`app/lib/platforms/bsky/uploads_bsky_media.rb`:

```ruby
class Platforms::Bsky
  class UploadsBskyMedia
    MAX_IMAGES = 4
    MAX_IMAGE_BYTES = 2_000_000
    # A larger image is scaled down to fit, so the download may be bigger than Bluesky takes
    MAX_DOWNLOAD_BYTES = 20 * 1024 * 1024
    CONTENT_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze

    def initialize
      @parses_media_items = ParsesMediaItems.new
      @selects_media = SelectsMedia.new
      @downloads_media = DownloadsMedia.new
      @fits_image_within_byte_limit = FitsImageWithinByteLimit.new
      @measures_aspect_ratio = MeasuresAspectRatio.new
      @uploads_bsky_blob = UploadsBskyBlob.new
      @records_media_fallback = RecordsMediaFallback.new
    end

    # Returns the app.bsky.embed.images entries, or [] when the post goes out without media
    def upload(crosspost, crosspost_config, record_manager)
      selection = @selects_media.select(@parses_media_items.parse(crosspost_config.media), max_images: MAX_IMAGES)
      return [] if selection.empty?
      raise MediaUnavailable, "Bluesky video is not supported yet" if selection.video

      images = selection.images.map { |item| upload_image(item, record_manager) }
      if selection.dropped.positive?
        @records_media_fallback.record(crosspost, "Bluesky takes at most #{MAX_IMAGES} images; dropped #{selection.dropped}")
      end
      images
    rescue => e
      # Any error in the media step posts without media, never fails the post
      @records_media_fallback.record(crosspost, e.is_a?(MediaUnavailable) ? e.message : "#{e.class}: #{e.message}")
      []
    end

    private

    def upload_image(item, record_manager)
      download = @downloads_media.download(item, max_bytes: MAX_DOWNLOAD_BYTES)
      raise MediaUnavailable, download.error if download.failure?

      content_type = download.data.content_type
      unless CONTENT_TYPES.include?(content_type)
        raise MediaUnavailable, "Bluesky takes JPEG, PNG, WebP and GIF, not #{content_type} (#{item.url})"
      end

      fitted = @fits_image_within_byte_limit.fit(download.data.bytes, content_type, max_bytes: MAX_IMAGE_BYTES)
      raise MediaUnavailable, "Could not fit #{item.url} within Bluesky's #{MAX_IMAGE_BYTES} bytes: #{fitted.error}" if fitted.failure?

      blob = @uploads_bsky_blob.upload(fitted.data.bytes, fitted.data.content_type, record_manager)
      raise MediaUnavailable, blob.error if blob.failure?

      {"alt" => item.alt, "image" => blob.data, "aspectRatio" => @measures_aspect_ratio.measure(item, fitted.data.bytes)}.compact
    end
  end
end
```

- [ ] **Step 4: Run them to see them pass**

Run: `rt "bin/rails test test/lib/platforms/bsky/measures_aspect_ratio_test.rb test/lib/platforms/bsky/uploads_bsky_media_test.rb"`
Expected: `13 runs, 22 assertions, 0 failures, 0 errors, 0 skips`.

- [ ] **Step 5: Lint and commit**

Run: `rt "bundle exec standardrb app/lib test/lib"`
Expected: no output.

```bash
cd /tmp/posse-wave2
git add app/lib/platforms/bsky/measures_aspect_ratio.rb app/lib/platforms/bsky/uploads_bsky_media.rb test/lib/platforms/bsky/measures_aspect_ratio_test.rb test/lib/platforms/bsky/uploads_bsky_media_test.rb
git commit -F - <<'EOF'
feat: upload a post's images to Bluesky with alt text and aspect ratio

UploadsBskyMedia takes the merged media list, keeps up to four images
(JPEG, PNG, WebP or GIF), brings each within Bluesky's 2,000,000-byte
limit with FitsImageWithinByteLimit, uploads it as a blob, and returns
the app.bsky.embed.images entries with alt text and, when known, the
aspect ratio. The aspect ratio comes from the feed's width and height, or
from the image header when the feed sends neither.

A video, any other type, a failed download, an image that cannot be
shrunk enough, a refused upload or any unexpected error records why in
the crosspost's metadata, and the post goes out as before.

Refs #1

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 8: Bluesky posts the images in place of the card

Branch `feat/bsky-images`.

**Files:**
- Create: `app/lib/platforms/bsky/keeps_link_with_media.rb`, `app/lib/platforms/bsky/composes_post_record.rb`
- Modify: `app/lib/platforms/bsky/syndicates_bsky_post.rb` (whole file below)
- Modify: `docs/feed.md` (the `media` row of the properties table)
- Test: `test/lib/platforms/bsky/keeps_link_with_media_test.rb`,
  `test/lib/platforms/bsky/composes_post_record_test.rb` (both new)

**Interfaces:**
- Consumes: `UploadsBskyMedia#upload` (Task 7); `AttachesWebCard#attach!`;
  `PublishesCrosspost::ComposesCrosspostContent#compose(crosspost_config, post_constraints)`;
  `AssemblesRichTextFacets#assemble(content, pattern_ranges)`; `Platforms::Bsky::POST_CONSTRAINTS`.
- Produces:
  - `Platforms::Bsky::KeepsLinkWithMedia#keep(crosspost_config, text, facets) -> Post(text, facets)`.
    When the config asked for a card, has a URL, and no facet already links to that URL, it
    recomposes with `append_url: true, attach_link: false`. Otherwise it returns its input.
  - `Platforms::Bsky::ComposesPostRecord#compose(crosspost, crosspost_config, text:, facets:,
    record_manager:) -> Composed(text, record)`. Images give an `app.bsky.embed.images` embed and the
    kept link; no images give the card when `attach_link`, as before. `record` is the
    `createRecord` input.
  - `SyndicatesBskyPost#syndicate!` keeps its signature and stores `composed.text` as the
    crosspost's content.

- [ ] **Step 1: Write the failing tests**

`test/lib/platforms/bsky/keeps_link_with_media_test.rb`. It runs the real composer with Bluesky's
defaults, so the expected text and byte offsets are what Bluesky would be sent. In the truncation
case, 58 words, `word...` and ` 🔗` come to 299 graphemes:

```ruby
require "test_helper"

class Platforms::Bsky::KeepsLinkWithMediaTest < ActiveSupport::TestCase
  URL = "https://example.com/social/map/"

  def setup
    @subject = Platforms::Bsky::KeepsLinkWithMedia.new
  end

  def test_appends_the_link_a_card_would_have_carried
    post = @subject.keep(config(content: "A map", attach_link: true), "A map", [])

    assert_equal "A map 🔗", post.text
    assert_equal [link_facet(6, 10)], post.facets
  end

  def test_trims_text_at_the_limit_to_make_room_for_the_link
    content = "word " * 60

    post = @subject.keep(config(content:, attach_link: true), content.strip, [])

    assert_equal "#{"word " * 58}word... 🔗", post.text
    assert_operator post.text.grapheme_clusters.size, :<=, 300
    assert_equal [link_facet(298, 302)], post.facets
  end

  def test_leaves_text_that_already_links_to_the_url
    facets = [link_facet(0, 31)]

    post = @subject.keep(config(content: URL, attach_link: true), URL, facets)

    assert_equal URL, post.text
    assert_equal facets, post.facets
  end

  def test_leaves_a_post_that_asked_for_no_card
    post = @subject.keep(config(content: "A map", attach_link: false), "A map", [])

    assert_equal "A map", post.text
    assert_equal [], post.facets
  end

  private

  def config(content:, attach_link:)
    CrosspostConfig.new(**Platforms::Bsky::DEFAULT_CROSSPOST_OPTIONS, url: URL, content:, format_string: "{{content}}", attach_link:)
  end

  def link_facet(byte_start, byte_end)
    {
      "$type" => "app.bsky.richtext.facet",
      "index" => {"byteStart" => byte_start, "byteEnd" => byte_end},
      "features" => [{"uri" => URL, "$type" => "app.bsky.richtext.facet#link"}]
    }
  end
end
```

`test/lib/platforms/bsky/composes_post_record_test.rb`:

```ruby
require "test_helper"

class Platforms::Bsky::ComposesPostRecordTest < ActiveSupport::TestCase
  Session = Struct.new(:pds, :access_token, :did, keyword_init: true)
  URL = "https://example.com/social/map/"
  CARD = {"$type" => "app.bsky.embed.external", "external" => {"uri" => URL, "title" => "A map", "description" => ""}}
  IMAGES = [{"alt" => "An orange square", "image" => "blob-1"}]

  def setup
    @uploads_bsky_media = Mocktail.of_next(Platforms::Bsky::UploadsBskyMedia)
    @keeps_link_with_media = Mocktail.of_next(Platforms::Bsky::KeepsLinkWithMedia)
    @attaches_web_card = Mocktail.of_next(Platforms::Bsky::AttachesWebCard)
    @subject = Platforms::Bsky::ComposesPostRecord.new
    @crosspost = crossposts(:admin_bsky_crosspost)
    @record_manager = Bskyrb::RecordManager.new(Session.new(pds: "https://bsky.social", access_token: "jwt", did: "did:plc:example"))
    Now.override!(Time.zone.parse("2026-10-06 14:00:00 UTC"), freeze: true)
  end

  def test_posts_uploaded_images_in_place_of_the_card_and_keeps_the_link
    config = CrosspostConfig.new(url: URL, attach_link: true)
    stubs { @uploads_bsky_media.upload(@crosspost, config, @record_manager) }.with { IMAGES }
    stubs { @keeps_link_with_media.keep(config, "A map", []) }.with { Platforms::Bsky::KeepsLinkWithMedia::Post.new(text: "A map 🔗", facets: ["link facet"]) }

    composed = @subject.compose(@crosspost, config, text: "A map", facets: [], record_manager: @record_manager)

    assert_equal "A map 🔗", composed.text
    assert_equal record("A map 🔗", ["link facet"], {"$type" => "app.bsky.embed.images", "images" => IMAGES}), composed.record
    verify_never_called { @attaches_web_card.attach! }
  end

  def test_without_media_attaches_the_card_as_before
    config = CrosspostConfig.new(url: URL, attach_link: true)
    stubs { @uploads_bsky_media.upload(@crosspost, config, @record_manager) }.with { [] }
    stubs { @attaches_web_card.attach!(config, @record_manager) }.with { CARD }

    composed = @subject.compose(@crosspost, config, text: "A map", facets: [], record_manager: @record_manager)

    assert_equal "A map", composed.text
    assert_equal record("A map", [], CARD), composed.record
    verify_never_called { @keeps_link_with_media.keep }
  end

  def test_without_media_or_a_card_posts_the_text_alone
    config = CrosspostConfig.new(url: URL, attach_link: false)
    stubs { @uploads_bsky_media.upload(@crosspost, config, @record_manager) }.with { [] }

    composed = @subject.compose(@crosspost, config, text: "A map", facets: [], record_manager: @record_manager)

    assert_equal record("A map", [], nil), composed.record
  end

  private

  def record(text, facets, embed)
    {
      "collection" => "app.bsky.feed.post",
      "$type" => "app.bsky.feed.post",
      "repo" => "did:plc:example",
      "record" => {
        "$type" => "app.bsky.feed.post",
        "createdAt" => "2026-10-06T14:00:00.000Z",
        "text" => text,
        "facets" => facets,
        "embed" => embed
      }.compact
    }
  end
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `rt "bin/rails test test/lib/platforms/bsky/keeps_link_with_media_test.rb test/lib/platforms/bsky/composes_post_record_test.rb"`
Expected: `7 runs, 0 assertions, 0 failures, 7 errors`, each
`NameError: uninitialized constant Platforms::Bsky::KeepsLinkWithMedia`.

- [ ] **Step 3: Write the implementation**

`app/lib/platforms/bsky/keeps_link_with_media.rb`:

```ruby
class Platforms::Bsky
  class KeepsLinkWithMedia
    Post = Struct.new(:text, :facets, keyword_init: true)

    def initialize
      @composes_crosspost_content = PublishesCrosspost::ComposesCrosspostContent.new
      @assembles_rich_text_facets = AssemblesRichTextFacets.new
    end

    # Images take the place of the link card, so the card's link is appended to the text instead,
    # as PublishesCrosspost::RecoversFromInvalidLinkAttachment does when a card is refused
    def keep(crosspost_config, text, facets)
      if crosspost_config.attach_link && crosspost_config.url.present? && !links_to?(facets, crosspost_config.url)
        content = @composes_crosspost_content.compose(CrosspostConfig.new(**crosspost_config.to_h.merge(append_url: true, attach_link: false)), POST_CONSTRAINTS)
        Post.new(text: content.string, facets: @assembles_rich_text_facets.assemble(content.string, content.pattern_ranges))
      else
        Post.new(text:, facets:)
      end
    end

    private

    def links_to?(facets, url)
      facets.any? { |facet| facet["features"].any? { |feature| feature["uri"] == url } }
    end
  end
end
```

`app/lib/platforms/bsky/composes_post_record.rb`. This is the record-building that
`SyndicatesBskyPost#post!` did inline, with the image step added in front:

```ruby
class Platforms::Bsky
  class ComposesPostRecord
    Composed = Struct.new(:text, :record, keyword_init: true)

    def initialize
      @uploads_bsky_media = UploadsBskyMedia.new
      @keeps_link_with_media = KeepsLinkWithMedia.new
      @attaches_web_card = AttachesWebCard.new
    end

    def compose(crosspost, crosspost_config, text:, facets:, record_manager:)
      images = @uploads_bsky_media.upload(crosspost, crosspost_config, record_manager)
      post = images.any? ? @keeps_link_with_media.keep(crosspost_config, text, facets) : KeepsLinkWithMedia::Post.new(text:, facets:)
      embed = if images.any?
        {"$type" => "app.bsky.embed.images", "images" => images}
      elsif crosspost_config.attach_link
        @attaches_web_card.attach!(crosspost_config, record_manager)
      end

      Composed.new(text: post.text, record: {
        "collection" => "app.bsky.feed.post",
        "$type" => "app.bsky.feed.post",
        "repo" => record_manager.session.did,
        "record" => {
          "$type" => "app.bsky.feed.post",
          "createdAt" => Now.time.iso8601(3),
          "text" => post.text,
          "facets" => post.facets,
          "embed" => embed
        }.compact
      }.compact)
    end
  end
end
```

`app/lib/platforms/bsky/syndicates_bsky_post.rb`, whole file. `post!` now only sends the record, and
the crosspost stores the text that was actually posted:

```ruby
class Platforms::Bsky
  class SyndicatesBskyPost
    PDS_URL = "https://bsky.social"

    def initialize
      @composes_post_record = ComposesPostRecord.new
    end

    def syndicate!(crosspost, crosspost_config, crosspost_content, rich_text_facets)
      session = Bskyrb::Session.new(
        Bskyrb::Credentials.new(
          crosspost.account.credentials["email"],
          crosspost.account.credentials["password"]
        ), PDS_URL
      )
      record_manager = Bskyrb::RecordManager.new(session)
      composed = @composes_post_record.compose(crosspost, crosspost_config, text: crosspost_content, facets: rich_text_facets, record_manager:)
      uri = post!(composed.record, record_manager)
      if uri.nil?
        PublishesCrosspost::Result.new(success?: false, message: "Failed to create Bsky post")
      else
        url = uri_to_url(uri, session)
        crosspost.update!(
          remote_id: uri,
          url: url,
          content: composed.text,
          status: "published",
          published_at: Now.time
        )
        PublishesCrosspost::Result.new(success?: true)
      end
    rescue Bskyrb::UnauthorizedError => e
      PublishesCrosspost::Result.new(success?: false, message: "Failed to authenticate to Bsky (invalid credentials)", error: e)
    rescue => e
      PublishesCrosspost::Result.new(success?: false, message: "Failed to syndicate to Bsky", error: e)
    end

    private

    def post!(record, record_manager)
      result = record_manager.create_record(record)
      if result["error"].present?
        raise "Failed to create Bsky post: #{result["error"]} - #{result["message"]}. Record we sent follows: #{record.inspect}"
      end

      result&.dig("uri")
    end

    def uri_to_url(uri, session)
      bsky_handle = DIDKit::Resolver.new.get_verified_handle(session.did)
      post_id = uri[/[^\/]+$/]
      "https://bsky.app/profile/#{bsky_handle}/post/#{post_id}"
    end
  end
end
```

- [ ] **Step 4: Run them to see them pass, along with the recorded Bluesky tests**

Run: `rt "bin/rails test test/lib/platforms/bsky test/lib/bsky_test.rb"`
Expected: `30 runs, 79 assertions, 0 failures, 0 errors, 0 skips`. `bsky_take`, `bsky_shot` and
`bsky_cut_off_bug` still replay through `ComposesPostRecord`, card and all.

- [ ] **Step 5: Say what Bluesky now does with `media`**

In `docs/feed.md`, replace the `media` row of the properties table:

```markdown
| `media` | array<object> | Media attachments used by certain platforms (Instagram requires images/video; YouTube requires exactly one video). When present, `media.poster_url` is used by platforms that support custom covers/thumbnails (such as Instagram Reels and YouTube). |
```

with:

```markdown
| `media` | array<object> | Media attachments used by certain platforms (Instagram requires images/video; YouTube requires exactly one video; Bluesky posts up to 4 JPEG, PNG, WebP or GIF images in place of the link card, scaling any over 2 MB, and does not post video yet; a link card that was asked for becomes the appended link). When present, `media.poster_url` is used by platforms that support custom covers/thumbnails (such as Instagram Reels and YouTube). When Bluesky cannot post an image, the post goes out with its link card and the reason is recorded in the crosspost's metadata. |
```

- [ ] **Step 6: Run the full suite**

Run: `rt "CI=true ./script/test" > /tmp/posse-wave2-bsky.log 2>&1; grep "runs," /tmp/posse-wave2-bsky.log; git -C /tmp/posse-wave2 status --short`
Expected: `385 runs, ... 0 failures, 0 errors` and `24 runs, ... 0 failures, 0 errors`. `git status`
lists only the files this task changed.

- [ ] **Step 7: Lint and commit**

Run: `rt "bundle exec standardrb app/lib test/lib"`
Expected: no output.

```bash
cd /tmp/posse-wave2
git add app/lib/platforms/bsky/keeps_link_with_media.rb app/lib/platforms/bsky/composes_post_record.rb app/lib/platforms/bsky/syndicates_bsky_post.rb docs/feed.md test/lib/platforms/bsky/keeps_link_with_media_test.rb test/lib/platforms/bsky/composes_post_record_test.rb
git commit -F - <<'EOF'
feat: post a feed's images natively on Bluesky

A Bluesky post with media now carries up to four images as an
app.bsky.embed.images embed, in place of the link card. When the feed
asked for a card, which is Bluesky's default, the card's link is appended
to the text as the 🔗 link instead, recomposed so the text still fits 300
graphemes. When no image can be posted, the post goes out with its card
exactly as before.

ComposesPostRecord builds the record SyndicatesBskyPost used to build
inline, so the choice between images and card is tested without a
Bluesky session.

Refs #1

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 9: Write the recorded Bluesky test

Branch `feat/bsky-images`. The test is written now and fails for want of a cassette. Task 12
records it.

**Files:**
- Modify: `test/lib/bsky_test.rb` (one test and two helpers appended)

- [ ] **Step 1: Write the recorded test**

Append to `test/lib/bsky_test.rb`, inside the class, after the last test's `end`, leaving a blank
line:

```ruby
  MEDIA_BASE = "https://raw.githubusercontent.com/jknowles/posse_party/914ff8332cb956c77ac45a0dd182dc8a47f862a7/test/fixtures/files/media"

  def test_bsky_posts_several_images_in_place_of_the_card
    crosspost = bsky_crosspost_with_media("https://example.com/social/stills/", [
      {"type" => "image", "url" => "#{MEDIA_BASE}/still.jpg", "alt" => "An orange square", "mime" => "image/jpeg", "width" => 240, "height" => 240},
      {"type" => "image", "url" => "#{MEDIA_BASE}/still.png", "alt" => "A navy square", "mime" => "image/png"}
    ])

    perfect_vcr_match("bsky_multi_image", time: "2026-10-01T14:00:00.000Z", except: [:headers]) do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    crosspost.reload
    assert_empty crosspost.failures
    assert_equal "published", crosspost.status
    assert_nil crosspost.metadata["media_fallback"]
    assert_match %r{\Aat://did:plc:[a-z0-9]+/app\.bsky\.feed\.post/[a-z0-9]+\z}, crosspost.remote_id
    assert_equal "PosseParty media test (deleted after recording)\n\n🔗", crosspost.content
    assert_requested(:post, "#{Platforms::Bsky::SyndicatesBskyPost::PDS_URL}/xrpc/com.atproto.repo.uploadBlob", headers: {"Content-Type" => "image/jpeg"})
    assert_requested(:post, "#{Platforms::Bsky::SyndicatesBskyPost::PDS_URL}/xrpc/com.atproto.repo.uploadBlob", headers: {"Content-Type" => "image/png"})
    assert_requested(:post, "#{Platforms::Bsky::SyndicatesBskyPost::PDS_URL}/xrpc/com.atproto.repo.createRecord") { |request|
      JSON.parse(request.body, symbolize_names: true)[:record] in {
        text: "PosseParty media test (deleted after recording)\n\n🔗",
        facets: [{features: [{uri: "https://example.com/social/stills/"}]}],
        embed: {"$type": "app.bsky.embed.images", images: [
          {alt: "An orange square", image: {mimeType: "image/jpeg"}, aspectRatio: {width: 240, height: 240}},
          {alt: "A navy square", image: {mimeType: "image/png"}, aspectRatio: {width: 240, height: 240}}
        ]}
      }
    }
  end

  private

  # attach_link stays at Bluesky's default, true, so the recording shows the card's link appended
  def bsky_crosspost_with_media(post_url, media)
    user = New.create(User, email: "user@example.com")
    user.accounts.create!(platform_tag: "bsky", label: "Bluesky", credentials: vcr_secrets({
      "email" => ENV["BSKY_EMAIL"],
      "password" => ENV["BSKY_PASSWORD"]
    }))
    filter_bsky_session_tokens
    posse = {
      syndicate: true,
      format_string: "{{content}}",
      content: "PosseParty media test (deleted after recording)",
      media:,
      platform_overrides: {bsky: {append_url_spacer: "\n\n"}}
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

  # Bluesky issues its session tokens in createSession's response, so no environment variable
  # names them in advance. Later requests carry the access token as a Bearer header. The filters
  # touch only Bluesky's /xrpc/ calls, so they cannot rewrite another platform's recording.
  def filter_bsky_session_tokens
    VCR.configure do |config|
      config.filter_sensitive_data("ACCESS_JWT_PLACEHOLDER") { |interaction|
        if interaction.request.uri.include?("/xrpc/")
          interaction.response.body.to_s.b[/"accessJwt":"([^"]+)"/, 1] || interaction.request.headers["Authorization"]&.first&.delete_prefix("Bearer ")
        end
      }
      config.filter_sensitive_data("REFRESH_JWT_PLACEHOLDER") { |interaction|
        interaction.response.body.to_s.b[/"refreshJwt":"([^"]+)"/, 1] if interaction.request.uri.include?("/xrpc/")
      }
    end
  end
```

What each piece pins:

- `time:` freezes `createdAt`, so the record body matches on replay. It is set in the past, so the
  recorded post is not dated in the future.
- `except: [:headers]`, as upstream's Bluesky tests use, because each session's token differs. The
  body is matched, so the cassette pins the text, facets, alt text, aspect ratios and blob refs.
- `filter_bsky_session_tokens` keeps both session tokens out of the cassette. `vcr_secrets` covers
  only values known before the test runs, and Bluesky issues these during it.
- `attach_link` stays at Bluesky's default, `true`, so the recording shows the card's link appended
  as 🔗 (Review Focus 1). The PNG has no `width` or `height`, so its aspect ratio is read from the
  image.

- [ ] **Step 2: Run it to see it fail**

Run: `rt "bin/rails test test/lib/bsky_test.rb"`
Expected: `3 runs, ... 1 failures`. The new test fails at `assert_empty crosspost.failures`, with
`An HTTP request has been made that VCR does not know how to handle`. Upstream's two tests pass.

- [ ] **Step 3: Lint and commit**

Run: `rt "bundle exec standardrb test/lib"`
Expected: no output.

```bash
cd /tmp/posse-wave2
git add test/lib/bsky_test.rb
git commit -F - <<'EOF'
test: Bluesky posts several images

A recorded test through PublishesCrosspost from a feed entry with two
images and Bluesky's default card setting. It checks that the record
carries both images with alt text and aspect ratios, that the card's link
is appended as the 🔗 link, and that no media fallback was recorded. The
cassette follows once recorded.

Refs #1

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 10: Review both branches on the most capable model

Wave 1's whole-branch review found its token leak and its two-URL regression. This review comes
before recording, so a fix that changes a request does not mean recording twice.

- [ ] **Step 1: Dispatch one fresh reviewer on the most capable model**

Give it the spec, this plan, the wave-1 ledger, and two ranges:

- `git -C /tmp/posse-wave2 diff origin/feat/media-foundation...feat/mastodon-images`
- `git -C /tmp/posse-wave2 diff origin/feat/media-foundation...feat/bsky-images`

Both include Tasks 1 and 2. Ask it to check the code against the Global Constraints and the Review
Focus, and to look especially for:

- a credential that can reach a message, a log line or a cassette;
- a media error that can still fail a post;
- a request that differs between recording and replay;
- a path where a Bluesky post loses its link.

- [ ] **Step 2: Read the roborev reviews the commit hook queued**

```bash
cd /tmp/posse-wave2
roborev list --branch feat/media-foundation
roborev list --branch feat/mastodon-images
roborev list --branch feat/bsky-images
```

Open each finished review with `roborev show --job <id>`. Reviews still queued can be read later;
do not wait on them.

- [ ] **Step 3: Grade, fix and record**

Fix each Critical or Important finding test-first, as its own commit on the branch it belongs to. A
fix to Tasks 1–2 goes on `feat/media-foundation`, after which `feat/mastodon-images` and
`feat/bsky-images` merge it. For every finding, record a ruling for Jared: the finding, the decision,
and the cost if the decision is wrong. Then re-run Task 4 Step 6 and Task 8 Step 6 on their
branches.

---

### Task 11: Record the Mastodon cassettes

Branch `feat/mastodon-images`. **This task publishes two real Mastodon posts. It does not start until
Jared approves the session.** Jared runs the one recording command in his own terminal, deletes the
two posts, and the tests replay offline from then on.

**Files:**
- Modify: `test/lib/mastodon_test.rb` (`record: true`, then back)
- Create: `test/support/vcr_cassettes/mastodon_multi_image.yml`, `mastodon_gif.yml`

- [ ] **Step 1: STOP. Ask Jared to approve the recording session**

Put this to Jared and wait for a yes:

> Recording session for wave 2, Mastodon:
> - **Account:** the Mastodon account PosseParty posts as. If there is more than one, which?
> - **What gets published:** two posts, each saying "PosseParty media test (deleted after
>   recording)" with a link to example.com:
>   - an orange and a navy square together, each with alt text;
>   - a three-frame GIF, which Mastodon converts and may take a few seconds to process.
> - **What I push first:** nothing. The fixtures are on GitHub at `914ff83` already.
> - **What you do:**
>   1. Capture the instance URL and token in your own terminal.
>   2. Run one command.
>   3. Delete the two posts.
>   4. Unset the variables.
>
>   Neither value enters this conversation or a file.
> - **What I check before commit:**
>   - no cassette contains your token or the instance URL;
>   - the cassettes keep the public profile Mastodon returns with each status (username, display
>     name, avatar URLs on the instance's media host). You decide whether that stays.

- [ ] **Step 2: Turn recording on**

```bash
cd /tmp/posse-wave2 && git switch feat/mastodon-images
```

In `test/lib/mastodon_test.rb`, change the two new calls to pass `record: true`:
`perfect_vcr_match("mastodon_multi_image", record: true, except: [:body, :headers]) do` and
`perfect_vcr_match("mastodon_gif", record: true, except: [:body, :headers]) do`.

**From here until Step 4, run no test yourself.** VCR would make real calls with placeholder
credentials.

- [ ] **Step 3: Jared records, in his own terminal**

Give Jared this to run. The first command lists the accounts without any secret, so he can pick the
ID.

```bash
ssh maxwell "cd ~/docker-compose/posse && docker compose exec -T web bin/rails runner 'Account.where(platform_tag: %w[mastodon bsky]).each { |a| puts [a.id, a.platform_tag, a.label, a.active].join(%q( | )) }'"
posse_cred() { ssh maxwell "cd ~/docker-compose/posse && docker compose exec -T web bin/rails runner 'puts Account.find($1).credentials[%q($2)]'" | tail -n 1; }
export MASTODON_BASE_URL="$(posse_cred <id> base_url)"
export MASTODON_ACCESS_TOKEN="$(posse_cred <id> access_token)"
[[ $MASTODON_BASE_URL =~ ^https://[A-Za-z0-9.-]+$ ]] && echo base_url ok
[[ $MASTODON_ACCESS_TOKEN =~ ^[A-Za-z0-9._~-]+$ ]] && echo token ok
~/.cache/posse-test/rt.sh "bin/rails test test/lib/mastodon_test.rb -n '/posts_(several_images|a_gif)/'"
```

Expected: `base_url ok`, `token ok`, then `2 runs, ... 0 failures, 0 errors`. If either `ok` is
missing, stop: the capture picked up something else, such as the Active Storage warning, and the
recording must not run. On Mastodon there are two posts: the pair of squares, and the GIF, which
should play.

**If either test fails, stop.** Have Jared delete whatever posted, and read the failure. If the GIF
was still processing after 60 seconds, the crosspost asked to finish later and the test saw it
unpublished: report back rather than raising the wait.

Then Jared:

1. Deletes both posts on Mastodon and confirms they are gone.
2. Checks that neither secret is in a cassette:
   `grep -c -e "$MASTODON_ACCESS_TOKEN" -e "$MASTODON_BASE_URL" /tmp/posse-wave2/test/support/vcr_cassettes/mastodon_{multi_image,gif}.yml`.
   Expected: `0` for each file.
3. Runs `unset MASTODON_BASE_URL MASTODON_ACCESS_TOKEN`.

- [ ] **Step 4: Turn recording off and replay**

Remove the two `record: true` arguments. Then:

Run: `rt "bin/rails test test/lib/mastodon_test.rb"`
Expected: `3 runs, ... 0 failures, 0 errors`, offline. If the GIF was polled, the test sleeps 3
seconds per poll while it replays.

- [ ] **Step 5: Check the cassettes**

```bash
cd /tmp/posse-wave2/test/support/vcr_cassettes
grep -n "Bearer" mastodon_multi_image.yml mastodon_gif.yml | grep -v "{{access_token}}"
grep -c "{{base_url}}" mastodon_multi_image.yml mastodon_gif.yml
grep -o -E '"(acct|username|display_name|avatar)":"[^"]*"' mastodon_multi_image.yml | sort -u
```

Expected: the first prints nothing, and the second counts more than 0 in each file. Show Jared what
the third prints, the account's public profile, and let him decide whether it stays.

- [ ] **Step 6: Commit the cassettes, once Jared confirms the posts are deleted**

```bash
cd /tmp/posse-wave2
git add test/lib/mastodon_test.rb test/support/vcr_cassettes/mastodon_multi_image.yml test/support/vcr_cassettes/mastodon_gif.yml
git commit -F - <<'EOF'
test: record Mastodon multi-image and GIF posts

Recorded against a real account on <date>; the two posts were deleted
straight after. The token and the instance URL are filtered to
placeholders.

Refs #1

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

Replace `<date>` with the recording date.

---

### Task 12: Record the Bluesky cassette

Branch `feat/bsky-images`. **This task publishes one real Bluesky post. It does not start until Jared
approves the session.**

**Files:**
- Modify: `test/lib/bsky_test.rb` (`record: true`, then back)
- Create: `test/support/vcr_cassettes/bsky_multi_image.yml`

- [ ] **Step 1: STOP. Ask Jared to approve the recording session**

> Recording session for wave 2, Bluesky:
> - **Account:** the Bluesky account PosseParty posts as. If there is more than one, which?
> - **What gets published:** one post saying "PosseParty media test (deleted after recording)",
>   with an orange and a navy square, each with alt text, and a 🔗 linking to example.com. It is
>   dated 2026-10-01 14:00 UTC, the time the test freezes.
> - **What I push first:** nothing.
> - **What you do:**
>   1. Capture the account's email and app password in your own terminal.
>   2. Run one command.
>   3. Delete the post.
>   4. Unset the variables.
> - **What I check before commit:**
>   - no cassette contains a session token, the email or the app password;
>   - the cassette keeps the account's DID and handle, which are public, and the post's `at://`
>     URI. You decide whether those stay.

- [ ] **Step 2: Turn recording on**

```bash
cd /tmp/posse-wave2 && git switch feat/bsky-images
```

In `test/lib/bsky_test.rb`, change the new call to
`perfect_vcr_match("bsky_multi_image", record: true, time: "2026-10-01T14:00:00.000Z", except: [:headers]) do`.

**From here until Step 4, run no test yourself.**

- [ ] **Step 3: Jared records, in his own terminal**

```bash
posse_cred() { ssh maxwell "cd ~/docker-compose/posse && docker compose exec -T web bin/rails runner 'puts Account.find($1).credentials[%q($2)]'" | tail -n 1; }
export BSKY_EMAIL="$(posse_cred <id> email)"
export BSKY_PASSWORD="$(posse_cred <id> password)"
[[ $BSKY_EMAIL =~ ^[^[:space:]@]+@[^[:space:]@]+$ ]] && echo email ok
[[ $BSKY_PASSWORD =~ ^[A-Za-z0-9-]+$ ]] && echo password ok
~/.cache/posse-test/rt.sh "bin/rails test test/lib/bsky_test.rb -n /several_images/"
```

Expected: `email ok`, `password ok`, then `1 runs, ... 0 failures, 0 errors`, and one post on Bluesky
with both squares, their alt text, and the 🔗.

**If the test fails, stop**, have Jared delete whatever posted, and report.

Then Jared:

1. Deletes the post on Bluesky and confirms it is gone.
2. Checks: `grep -c -e "$BSKY_EMAIL" -e "$BSKY_PASSWORD" /tmp/posse-wave2/test/support/vcr_cassettes/bsky_multi_image.yml`.
   Expected: `0`.
3. Runs `unset BSKY_EMAIL BSKY_PASSWORD`.

- [ ] **Step 4: Turn recording off and replay**

Remove the `record: true` argument. Then:

Run: `rt "bin/rails test test/lib/bsky_test.rb"`
Expected: `3 runs, ... 0 failures, 0 errors`, offline.

- [ ] **Step 5: Check the cassette**

```bash
cd /tmp/posse-wave2/test/support/vcr_cassettes
grep -n -E "eyJ|Bearer" bsky_multi_image.yml | grep -v "PLACEHOLDER"
grep -c -E "ACCESS_JWT_PLACEHOLDER|REFRESH_JWT_PLACEHOLDER|\{\{email\}\}|\{\{password\}\}" bsky_multi_image.yml
```

Expected: the first prints nothing (a JWT starts `eyJ`); the second counts more than 0.

- [ ] **Step 6: Commit the cassette, once Jared confirms the post is deleted**

```bash
cd /tmp/posse-wave2
git add test/lib/bsky_test.rb test/support/vcr_cassettes/bsky_multi_image.yml
git commit -F - <<'EOF'
test: record a Bluesky multi-image post

Recorded against a real account on <date>; the post was deleted straight
after. The email, app password and both session tokens are filtered to
placeholders.

Refs #1

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 13: Deploy wave 2 to maxwell

**This task waits until wave 1's real post is checked** (wave-1 plan, Task 10 Step 1: a
civilytics.com GIF crosspost to LinkedIn), so a problem can be traced to one wave. Ask Jared whether
that check is done before Step 1.

**Every command that touches maxwell waits for Jared's yes.** The runbook is the gitignored
`maxwell-deploy.local.md`, section 1a. Since the 2026-10-01 migration it lives in the data home,
`/home/jared/Nextcloud/Civilytics/Code/jknowles/posse_party/maxwell-deploy.local.md`, not in the
checkout.

**Corrected after wave 2 ran (2026-10-02).** As first written, this task's feed-row script replaced
a whole conflict block with the `media` row. `feat/bsky-images` had also changed the `og_image` row,
so git put `attach_link` through `media` in one block and the script deleted four rows; the merge
was redone by hand. The date-based names would also have reused wave 1's branch and image on a
same-day deploy, and Step 6 recomputed the tag from a date that had moved on by the time of the
dump. The steps below carry both fixes. The run's ledger is in the data home at
`.superpowers/sdd/media-wave-2-plan/progress.md`.

**Files:**
- Create: branch `test/deploy-YYYYMMDD-wave2` (local)
- Modify: `maxwell-deploy.local.md` (deploy log; never committed)

- [ ] **Step 1: Build the deploy branch**

`feat/linkedin-images`, `feat/mastodon-images` and `feat/bsky-images` each rewrote the `media` row
of `docs/feed.md`, so each wave-2 merge conflicts there. This script swaps in the row for all three
platforms and keeps every other row from the deploy side. It stops if the two sides of a conflict
block differ in any row besides `media`: a branch that also edited a neighboring row needs that
change merged by hand.

```bash
cat > /tmp/posse-wave2-feed-row.py <<'EOF'
import pathlib, re

path = pathlib.Path("docs/feed.md")
media = "| `media` | array<object> | Media attachments used by certain platforms (Instagram requires images/video; YouTube requires exactly one video; LinkedIn posts up to 20 JPEG, PNG or GIF images, Mastodon up to 4 JPEG, PNG, GIF or WebP images, and Bluesky up to 4 JPEG, PNG, WebP or GIF images, scaling any over 2 MB; none of the three posts video yet). On LinkedIn and Bluesky the images take the place of the link card: the post's URL stays in its text, and a link card that was asked for becomes the appended link. When present, `media.poster_url` is used by platforms that support custom covers/thumbnails (such as Instagram Reels and YouTube). When a platform cannot post an image, the post goes out as it would have without media, and the reason is recorded in the crosspost's metadata. |"

def field(line):
    return line.split("|")[1].strip() if line.startswith("|") else line

def resolve(block):
    ours, theirs = block.group(1).splitlines(), block.group(2).splitlines()
    others = sorted({field(line) for line in set(ours) ^ set(theirs)} - {"`media`"})
    assert not others, f"rows besides media differ: {', '.join(others)}. Resolve docs/feed.md by hand."
    assert "`media`" in map(field, ours), "no media row on the deploy side of the conflict"
    return "".join((media if field(line) == "`media`" else line) + "\n" for line in ours)

text, count = re.subn(r"<<<<<<< [^\n]*\n(.*?)=======\n(.*?)>>>>>>> [^\n]*\n", resolve, path.read_text(), flags=re.S)
assert count, "no conflict block in docs/feed.md"
path.write_text(text)
EOF
```

```bash
cd /tmp/posse-wave2
DEPLOY=test/deploy-$(date +%Y%m%d)-wave2
git switch -c "$DEPLOY" main
git merge --no-edit origin/test/deploy-20261001
git merge --no-edit feat/mastodon-images
```

Expected: the first merge fast-forwards; the second stops with
`CONFLICT (content): Merge conflict in docs/feed.md` and no other conflict.

```bash
cd /tmp/posse-wave2
python3 /tmp/posse-wave2-feed-row.py && git add docs/feed.md && git commit --no-edit
git merge --no-edit feat/bsky-images
```

Expected: a conflict in `docs/feed.md` and nowhere else. If the script stops, it names the rows
where the two sides disagree, without knowing which side changed them. Resolve by hand against the
merge base: `git diff $(git merge-base HEAD MERGE_HEAD) MERGE_HEAD -- docs/feed.md` shows what the
merging branch changed. Keep the deploy side's row where only the deploy side changed it, take the
branch's row where only the branch changed it, and where both changed it write one row carrying both
edits. Put in the combined `media` row, then diff the result against both parents. In wave 2 the
script stops on `attach_link` (changed on the deploy side only) and `og_image` (changed on both; the
`feat/bsky-images` row already contained the deploy side's sentence).

```bash
cd /tmp/posse-wave2
python3 /tmp/posse-wave2-feed-row.py && git add docs/feed.md && git commit --no-edit
grep -c -e "^<<<<<<<" -e "^>>>>>>>" docs/feed.md
```

Expected: `0`.

- [ ] **Step 2: Run the full suite on it**

Run: `rt "CI=true ./script/test" > /tmp/posse-wave2-deploy.log 2>&1; grep "runs," /tmp/posse-wave2-deploy.log; git status --short`
Expected: `477 runs, ... 0 failures, 0 errors` and `24 runs, ... 0 failures, 0 errors`, and an empty
`git status`. If Task 10 added tests, the first count is higher by that many.

- [ ] **Step 3: STOP. Ask Jared to approve the deploy**

> Ready to deploy wave 2 to maxwell:
> - **Image:** `posse_party:media-YYYYMMDD-wave2`, built on maxwell from `$DEPLOY` at `<sha>`.
> - **What it contains:** wave 1's deploy plus the foundation's two fixes, Mastodon images and
>   Bluesky images.
> - **Migrations:** none.
> - **Rollback:** `POSSE_IMAGE=posse_party:media-20261001 docker compose up -d`.
> - **Before it:** you take the `pg_dump` (runbook step 3).

- [ ] **Step 4: Build on maxwell**

```bash
cd /tmp/posse-wave2
DEPLOY=$(git branch --show-current); SHA=$(git rev-parse HEAD); TAG=media-${DEPLOY#test/deploy-}
ssh maxwell 'rm -rf ~/tmp/posse-build && mkdir -p ~/tmp/posse-build'
git archive --format=tar HEAD | ssh maxwell 'tar -x -C ~/tmp/posse-build'
ssh maxwell "cd ~/tmp/posse-build && docker build --build-arg GIT_COMMIT=$SHA -t posse_party:$TAG ."
```

Expected: the build ends with `naming to docker.io/library/posse_party:media-YYYYMMDD-wave2`.

- [ ] **Step 5: Jared takes the database dump**

Jared runs the runbook's step 3 dump and confirms the file exists. Do not continue without it.

- [ ] **Step 6: Run the new image and confirm it**

```bash
DEPLOY=$(git -C /tmp/posse-wave2 branch --show-current); SHA=$(git -C /tmp/posse-wave2 rev-parse HEAD)
TAG=media-${DEPLOY#test/deploy-}
ssh maxwell "cd ~/docker-compose/posse && POSSE_IMAGE=posse_party:$TAG docker compose up -d"
ssh maxwell 'cd ~/docker-compose/posse && docker compose ps'
ssh maxwell 'cd ~/docker-compose/posse && docker compose logs -n 80 web worker'
curl -s -o /dev/null -w '%{http_code}\n' http://maxwell:3001/up
ssh maxwell 'cd ~/docker-compose/posse && docker compose exec -T web bin/rails runner "puts GitCommit.new.identify"' | tail -n 1
```

Expected:
- `web` and `worker` are up, with no errors in the logs.
- `/up` returns `200`.
- The runner prints `$SHA`. The image tag alone does not prove which commit is running.

The tag comes from the branch name, never from today's date: the dump can land on a later day than
the build, as it did in wave 2 (built 2026-10-01, switched 2026-10-02).

If any of these fails, roll back with the command in Step 3 and report.

- [ ] **Step 7: Log the deploy and draft the `.env` change**

Append to the runbook's deploy log, in the style of the 2026-10-01 entry:
- the date, `posse_party:media-YYYYMMDD-wave2`, the commit and `$DEPLOY`;
- the merged branches (`test/deploy-20261001`, `feat/mastodon-images`, `feat/bsky-images`, which
  carry the updated `feat/media-foundation`), and the `docs/feed.md` resolution;
- "no migrations", the dump file, and the rollback command from Step 3.

Then give Jared this to apply himself, since the file holds secrets:

> On maxwell, set `POSSE_IMAGE=posse_party:media-YYYYMMDD-wave2` in `~/docker-compose/posse/.env`,
> run `bin/secrets-seal`, and commit `posse/.env.age`. Never `git add -f` the plaintext `.env`.
> Until then, a bare `docker compose up -d` keeps running `media-20261001`, which is pinned there
> now.

- [ ] **Step 8: Ask about pushing**

Ask Jared whether to push to `origin`:
- `feat/media-foundation`, a fast-forward from `914ff83`;
- `feat/mastodon-images` and `feat/bsky-images`;
- `$DEPLOY`, as `test/deploy-20261001` was.

Push only what he approves.

---

### Task 14: Check a real post, then update what describes it

This waits for the deploy and for a civilytics.com social post that names Mastodon and Bluesky and
carries two stills. Both are Jared's calls.

- [ ] **Step 1: Jared posts one entry with stills and checks it**

Jared creates the Mastodon and Bluesky crossposts for that post by hand in PosseParty and publishes
them. He checks four things on each platform:

- both images appear, in order;
- each has its alt text;
- the post's link is in the text (on Bluesky, the 🔗 opens the post's URL);
- on Bluesky, no link card appears.

Then confirm no fallback was recorded:

```bash
ssh maxwell 'cd ~/docker-compose/posse && docker compose exec -T web bin/rails runner "Crosspost.joins(:account).where(accounts: {platform_tag: %w[mastodon bsky]}).order(:updated_at).last(2).each { |c| p [c.account.platform_tag, c.status, c.url, c.metadata[%q(media_fallback)]] }"' | tail -n 2
```

Expected: two lines, each `[platform, "published", url, nil]`. A Hash in the fourth place gives the
reason the images did not post: report it before changing anything.

- [ ] **Step 2: Update homepage_test's `docs/posse-party.md`**

In homepage_test, on a branch off `dev`, replace the paragraph that begins "As of October 2026
PosseParty posts media" (in whichever version wave 1 left it) with:

```markdown
As of <month> 2026 PosseParty posts media to Instagram, LinkedIn, Mastodon and
Bluesky (and Facebook, Threads, Pixelfed and YouTube, which this feed does not
name). LinkedIn and Mastodon get a GIF from their override, and stills as images.
Bluesky gets the stills; until the fork's video step lands, a GIF post reaches
Bluesky as its text with the link appended. When a platform cannot post the
media, the post goes out without it, and PosseParty records why.
```

Commit only when Jared asks. The repo's pre-commit hooks and CI apply as usual.

- [ ] **Step 3: Update the fork's media plan status**

On `docs/media-plan`, update the status line in `docs/planning/media.md`: steps 4 and 5 (Mastodon
and Bluesky images) shipped in wave 2 (`posse_party:media-YYYYMMDD-wave2`); steps 6, 7 and 9 remain.
Commit it locally.

- [ ] **Step 4: Draft the outward notes for Jared to approve**

Show each draft and post nothing without his yes:

1. A comment on jaredknowles.com #61:
   > Mastodon and Bluesky now post images natively, as of `posse_party:media-YYYYMMDD-wave2`, up to
   > four per post, each with its `alt`. On Bluesky the images replace the link card, and when an
   > entry asks for a card (Bluesky's default), its link is appended as 🔗 instead. Bluesky images
   > over 2 MB are scaled down. Video on both platforms follows in the next wave.
2. A comment on fork issue #1: steps 4 and 5 shipped in wave 2; Pixelfed media and video remain, so
   the issue stays open.

- [ ] **Step 5: Clean up**

```bash
cd /home/jared/code/jknowles/posse_party
git worktree remove /tmp/posse-wave2
ssh maxwell 'rm -rf ~/tmp/posse-build'
rm /tmp/posse-wave2-feed-row.py
```

Keep `~/.cache/posse-test`, the `posse-test-*` containers and the gems volume for wave 3. Keep
`posse_party:media-20261001` on maxwell until wave 3's deploy, as the rollback image.
