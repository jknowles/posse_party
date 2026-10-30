# Plan: LinkedIn Company Page as a syndication target

**Status:** Done 2026-10-30 — deployed to maxwell as `posse_party:media-20261030` and verified
with a real post on the Civilytics Company Page. Open: setup-guide screenshots, and whether this
goes upstream (it would follow the LinkedIn media branches it is stacked on).
**Branch:** `feat/linkedin-page` (build the feature here on top of this plan).
**Decided:** 2026-06-21.

## Goal

Add posting to a LinkedIn **Company/Organization Page** as a syndication target, **in addition to**
the existing personal-profile LinkedIn integration. Both must work on the same instance at the same time.

This is feasible because each connected account is just a row in `accounts` with its own
`platform_tag` (no uniqueness constraint), so a personal-profile account and a Page account
coexist and route independently.

## Background: personal vs. page (resolved confusion)

- The **existing** `Platforms::Linkedin` posts to the **personal profile**: `author: urn:li:person:…`,
  scope `w_member_social` ("Share on LinkedIn", which is self-serve and free).
- It is **not** a Page integration. The confusion arose because LinkedIn forces you to associate the
  developer app with a Company Page during app *verification* — that is verification only; posts still
  land on the personal feed.
- Posting to a **Page** is a genuinely different capability: scope `w_organization_social`,
  `author: urn:li:organization:…`, via the **Community Management API**.

## Blocker: Community Management API approval (not self-serve)

Company Page posting requires LinkedIn's Community Management API, which is approval-gated and
restricted to **registered legal organizations / commercial use cases**.

**Correction (2026-09-16):** LinkedIn will not add this product to an app that already has other
products (the request is grayed out), so the request was made on a **new developer app** tied to
the Civilytics Company Page — not on the existing personal-profile app. Once approved, the access
can be transferred to the existing app by re-submitting the form there with the approved app's
client ID, or the new app can simply be used for the Page target.

**Done so far (2026-09-16):**

- [x] Created a new developer app associated with the Civilytics Consulting LLC Company Page.
- [x] Page super admin verified the app.
- [x] Requested the Community Management API product and submitted the Development Tier access
      form (legal org name, registered address, website, privacy policy, business email).

## TODO when resuming

1. **Check the decision.** Developer Portal → My Apps → the new app → Products. Also check the
   business email (and its spam/promotions folders) for the verification and decision mail.
   - If **rejected**: LinkedIn does not allow re-applying on the same app. Read the rejection
     reason, create another new app, and submit a fresh Development Tier form.
   - If **approved**: continue below. Development Tier (500 requests per app) should be enough
     for one Page; Standard Tier needs a narrated screencast and is only worth it if the quota
     binds.
2. **Confirm the scope.** On the approved app's Auth tab, verify `w_organization_social` is
   listed. *Done 2026-10-30: both `w_organization_social` and `r_organization_social` are listed.*
   The client ID and secret are per-account credentials entered in the web UI (stored on the
   `accounts` row), not deploy `.env` values. Never put them in the repo.
   - **Redirect URL:** as of 2026-10-30 the new app lists only the instance's base domain.
     LinkedIn matches exactly, so add `https://<host>/credential_renewals/linkedin` before
     step 6.
3. **Get the Organization URN.** Page admin URL contains the numeric id
   (`linkedin.com/company/<id>/admin/`); the URN is `urn:li:organization:<id>`. This is the
   credential the user pastes (see Design).
4. **Decide which app the Page target uses.** Either point `Platforms::LinkedinPage` at the new
   app's credentials, or transfer Community Management access to the existing app (form on the
   existing app, enter the new app's client ID). Using the new app is fewer steps.
   *Decided 2026-10-30: the Page target uses the new app's credentials.*
5. **Build it.** `git checkout feat/linkedin-page`, then work the implementation checklist
   below, TDD: `required_credentials` and syndication tests first, API stubbed.
6. **Verify end to end** on the live instance: connect a "LinkedIn Page" account, publish one
   post with an image, confirm it lands on the Company Page and not the personal feed.
7. **Ship.** CHANGELOG entry, account-setup doc with screenshots, then decide fork-only vs.
   upstream PR.
   *2026-10-30: steps 2–6 done; CHANGELOG entry and setup guide text written. Screenshots and
   the upstream decision remain.*

Reference: <https://learn.microsoft.com/en-us/linkedin/marketing/community-management/community-management-overview>
and <https://learn.microsoft.com/en-us/linkedin/marketing/community-management-app-review>.

## Design (decided)

- New platform class **`Platforms::LinkedinPage`**, `TAG = "linkedin_page"`, `LABEL = "LinkedIn Page"`.
- **Developer app:** the new app created for the Community Management request (see Blocker
  above); reusing the existing app requires an access transfer after approval.
- **Page selection:** user **pastes the Organization URN** (`urn:li:organization:123`) as a required
  credential — mirrors how the current `person_urn` works. (Chosen over auto-discovery via
  `organizationAcls` to keep surface area small.)
- **Revised 2026-10-30: reuse, not clone.** `Platforms::LinkedinPage` composes the existing
  `Platforms::Linkedin::*` helpers. They were made author-agnostic (`author_urn:` keyword;
  `SyndicatesLinkedinPost#syndicate!` takes `author_credential:`), and the OAuth URL moved to
  `Platforms::Linkedin::BuildsAuthorizationUrl` with a `scope:` keyword. The Page target shares the
  `/credential_renewals/linkedin` callback: `FindsAccountByOauthState` ignores platform and the
  token exchange uses each account's own client ID and secret, so no new route or controller
  action is needed. The Page scope is `w_organization_social` alone, confirmed 2026-10-30: the
  recording session posted, and uploaded images and video, as the organization with only that scope.
  The token came from the in-app renewal flow on maxwell; the developer portal's OAuth 2.0 tools
  froze at sign-in in both Chrome and Firefox. The original plan, for the record:
- ~~The implementation is largely a **clone of `app/lib/platforms/linkedin/`**.~~ Only behavioral changes:
  - OAuth scope adds `w_organization_social` (keep `openid profile` if needed for the connect flow).
  - Post/image `author` / `owner` = the organization URN instead of the person URN.
  - Same `/rest/posts` endpoint, same `LinkedIn-Version` header (currently `202605`), same OG-image
    + image-upload flow, same special-character escaping.

## Implementation checklist (mirrors the PixelFed addition, commit 4d897fe)

Core (create):
- [x] `app/lib/platforms/linkedin_page.rb` — platform class (TAG, LABEL, REQUIRED_CREDENTIALS incl.
      `organization_urn`, CREDENTIAL_LABELS, POST_CONSTRAINTS, DEFAULT_CROSSPOST_OPTIONS,
      RENEWABLE/RENEWAL_URL_SUPPORTED, `publish!`, `renew!`, `renewal_url` with org scope).
- [x] ~~`app/lib/platforms/linkedin_page/`~~ not needed; shared helpers reused — syndication worker + helpers, cloned/adapted from the
      existing `app/lib/platforms/linkedin/` services (publishes_post, calls_linkedin_api,
      initiates_image_upload, uploads_image, scrapes_og_image, token exchange/renewal).

Registration / wiring (edit):
- [x] `app/lib/publishes_crosspost/matches_platform_api.rb` — add `Platforms::LinkedinPage` to `PLATFORMS`.
- [x] `app/controllers/docs_controller.rb` — add `linkedin_page` to `DOC_PATHS`.
- [x] ~~`config/routes.rb` + `app/controllers/credential_renewals_controller.rb`~~ not needed; shared callback — add the OAuth
      renewal callback (mirror the `linkedin` route/action) if using the in-app OAuth renewal flow.

UI / icon:
- [x] ~~`app/assets/images/icons/linkedin_page.svg`~~ reuses `linkedin.svg` (white-on-transparent).
- [x] `app/views/shared/_platform_icon.html.erb` — add `when "linkedin_page"` to both the color and
      icon-file case statements.

Docs:
- [x] `docs/account_setup/linkedin_page.md` (text done; screenshots open under `docs/images/`).
- [x] `docs/feed.md` (adapters list) — add to supported adapters + `platform_overrides` example.
- [x] `README.md` — add to the supported-platforms list.
- [ ] `site/layouts/index.html` (upstream's marketing page; only if this goes upstream) — add the platform icon + color to the landing page hero grid.

Tests / fixtures:
- [x] `test/fixtures/accounts.yml` (crossposts.yml not needed) — add a `linkedin_page` fixture.
- [x] `test/lib/linkedin_page_test.rb` — six VCR scenarios (link card, image, multi-image, GIF override,
      silent loop, clip with poster), recorded against the real Page 2026-10-30; posts deleted, cassettes
      checked for the token and the organization ID.
- [x] `test/lib/platforms/linkedin_page_test.rb`, `linkedin/syndicates_linkedin_post_test.rb`, `linkedin/builds_authorization_url_test.rb`.
- [x] `test/lib/platforms/required_credentials_test.rb` — add the class + a dedicated credential test.
- [x] `test/system/account_test.rb` — assert the new platform appears with correct credential fields.

## Stacked on the LinkedIn media branches (2026-10-30)

`feat/linkedin-page` merges `origin/feat/linkedin-video` (which carries `feat/linkedin-images` and
`feat/media-foundation`), because production runs that LinkedIn code and it threads the author
through `UploadsMedia`, `UploadsVideo`, the card thumbnail, and the video `finish!` path. The
author rename covers all of them, and `LinkedinPage` is `finishable?` like `Linkedin`. An upstream
PR would therefore follow the media branches, not precede them.

`CallsLinkedinApi` on `main` writes the `Authorization` header into its error message.
`feat/linkedin-images` already strips it and redacts bearer tokens from exceptions, so the
deployed build and this branch do not leak the token. Only `main` (upstream) still does.

## How to resume

See "TODO when resuming" above.
