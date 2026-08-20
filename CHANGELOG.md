# CHANGELOG

This file lists user-visible changes (including potentially breaking changes). The app is not versioned; entries are reverse-chronological by date.

## 2026-08-20

- Platforms can now offer a "Compose Manually" link on a crosspost, which opens that platform's own composer with the crosspost's content already filled in. X is the first platform to support it. This pairs with the existing "Manually publish crossposts" account setting for anyone who would rather not pay X's per-post API charges. After posting, paste the resulting URL into the same card (or `PATCH /api/crossposts/:id`) to record the crosspost as published.
- New `GET /api/crossposts/pending` returns crossposts awaiting manual publication, including the composed content and a ready-to-open compose URL.

## 2025-12-31

- Instagram Stories now requires libvips (via `ruby-vips`) to letterbox non-9:16 images into 9:16 story JPEGs with black bars. If you don’t publish to the `story` channel, you don’t need libvips installed.
