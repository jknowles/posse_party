# Plan: LinkedIn Company Page as a syndication target

**Status:** Deferred — blocked on LinkedIn API approval (see "Blocker" below). No code written yet.
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

Steps to unblock:

1. On the **existing** LinkedIn developer app, request the
   [Community Management API](https://developer.linkedin.com/product-catalog/marketing/community-management-api)
   product (no second app needed).
2. Complete LinkedIn's access form: legal org name, registered address, business email, website,
   use-case description. Must read as a legitimate org/commercial use.
3. Development Tier is granted first (limited volume — enough to build & verify). Standard Tier needs
   a further upgrade request (possibly a screen-recording walkthrough).
4. Approval grants the `w_organization_social` scope — that is the green light to ship.

Reference: <https://learn.microsoft.com/en-us/linkedin/marketing/community-management/community-management-overview>

## Design (decided)

- New platform class **`Platforms::LinkedinPage`**, `TAG = "linkedin_page"`, `LABEL = "LinkedIn Page"`.
- **Reuse the existing LinkedIn developer app** (just add the Community Management API product).
- **Page selection:** user **pastes the Organization URN** (`urn:li:organization:123`) as a required
  credential — mirrors how the current `person_urn` works. (Chosen over auto-discovery via
  `organizationAcls` to keep surface area small.)
- The implementation is largely a **clone of `app/lib/platforms/linkedin/`**. Only behavioral changes:
  - OAuth scope adds `w_organization_social` (keep `openid profile` if needed for the connect flow).
  - Post/image `author` / `owner` = the organization URN instead of the person URN.
  - Same `/rest/posts` endpoint, same `LinkedIn-Version` header (currently `202605`), same OG-image
    + image-upload flow, same special-character escaping.

## Implementation checklist (mirrors the PixelFed addition, commit 4d897fe)

Core (create):
- [ ] `app/lib/platforms/linkedin_page.rb` — platform class (TAG, LABEL, REQUIRED_CREDENTIALS incl.
      `organization_urn`, CREDENTIAL_LABELS, POST_CONSTRAINTS, DEFAULT_CROSSPOST_OPTIONS,
      RENEWABLE/RENEWAL_URL_SUPPORTED, `publish!`, `renew!`, `renewal_url` with org scope).
- [ ] `app/lib/platforms/linkedin_page/` — syndication worker + helpers, cloned/adapted from the
      existing `app/lib/platforms/linkedin/` services (publishes_post, calls_linkedin_api,
      initiates_image_upload, uploads_image, scrapes_og_image, token exchange/renewal).

Registration / wiring (edit):
- [ ] `app/lib/publishes_crosspost/matches_platform_api.rb` — add `Platforms::LinkedinPage` to `PLATFORMS`.
- [ ] `app/controllers/docs_controller.rb` — add `linkedin_page` to `DOC_PATHS`.
- [ ] `config/routes.rb` + `app/controllers/credential_renewals_controller.rb` — add the OAuth
      renewal callback (mirror the `linkedin` route/action) if using the in-app OAuth renewal flow.

UI / icon:
- [ ] `app/assets/images/icons/linkedin_page.svg` (white-on-transparent).
- [ ] `app/views/shared/_platform_icon.html.erb` — add `when "linkedin_page"` to both the color and
      icon-file case statements.

Docs:
- [ ] `docs/account_setup/linkedin_page.md` (+ screenshots under `docs/images/`).
- [ ] `docs/feed.md` — add to supported adapters + `platform_overrides` example.
- [ ] `README.md` — add to the supported-platforms list.
- [ ] `site/layouts/index.html` — add the platform icon + color to the landing page hero grid.

Tests / fixtures:
- [ ] `test/fixtures/accounts.yml` + `test/fixtures/crossposts.yml` — add a `linkedin_page` fixture.
- [ ] `test/lib/linkedin_page_test.rb` — integration happy-path with stubbed API.
- [ ] `test/lib/platforms/linkedin_page/*_test.rb` — unit tests per helper.
- [ ] `test/lib/platforms/required_credentials_test.rb` — add the class + a dedicated credential test.
- [ ] `test/system/account_test.rb` — assert the new platform appears with correct credential fields.

## How to resume

When LinkedIn approval is in hand: `git checkout feat/linkedin-page`, then implement per the
checklist above (TDD: write the `required_credentials` + syndication tests first, stub the API).
