# Pixelfed Account Setup

This guide walks through connecting your Pixelfed account to POSSE Party so it can publish posts on your behalf.

Pixelfed implements the same client API as Mastodon, so connecting it works much like a Mastodon account: you create an application on your Pixelfed instance and give POSSE Party the resulting access token. Because Pixelfed is a photo-sharing platform, POSSE Party only syndicates posts that include at least one image — text-only posts are skipped.

## What POSSE Party Needs From You

- `Base URL` for your Pixelfed instance, for example `https://pixelfed.social`
- `Access Token` that authorizes POSSE Party to publish posts to your account via the Pixelfed API

Both values come from an application you create in your Pixelfed account settings.

## How to Set Up Your Account

1. [Create a new application in Pixelfed](#1-create-a-new-application-in-pixelfed)
2. [Generate an access token](#2-generate-an-access-token)
3. [Add Pixelfed to POSSE Party](#3-add-pixelfed-to-posse-party)

### 1. Create a New Application in Pixelfed

1. Log in to your Pixelfed instance in a web browser and open **Settings**. In the sidebar, click **Applications** (on some instances this is found under **Settings → Development** or at the `/settings/applications` path) and then click **Create New Application** (sometimes labeled **New Application**).

![Pixelfed applications settings page](../images/pixelfed-1.png)

2. Give the application a recognizable name, such as `POSSE Party`, and—if your instance asks for a redirect URI—enter the URL of your POSSE Party instance. The redirect URI is not used by POSSE Party for publishing, so any valid URL belonging to you is acceptable.

![Pixelfed application details form](../images/pixelfed-2.png)

3. Under **Scopes**, enable `write` (this includes `write:statuses` and `write:media`, which POSSE Party needs to upload images and publish posts). Leave `read` enabled if it is checked by default. Click **Create** / **Submit**.

![Pixelfed application scopes with write enabled](../images/pixelfed-3.png)

### 2. Generate an Access Token

1. After the application is created, open it from your list of applications by clicking its name.

![Pixelfed application list showing the new application](../images/pixelfed-4.png)

2. Locate the **Your Access Token** value (some instances label this **Personal Access Token** and provide a **Generate Token** button—click it if no token is shown yet). Copy the access token and keep it somewhere safe; you will paste it into POSSE Party in the next step.

![Pixelfed application credentials showing the access token](../images/pixelfed-5.png)

> **Note:** Treat your access token like a password. Anyone with it can post to your Pixelfed account. If it is ever exposed, return to this screen and revoke or regenerate it.

### 3. Add Pixelfed to POSSE Party

1. In POSSE Party, go to **Accounts** and click **Add Account**. Give the account a label and select **Pixelfed** as the platform.

2. Under **Credentials for Pixelfed**, enter:
    - `Base URL` to your Pixelfed instance URL (e.g., `https://pixelfed.social`)
    - `Access Token`

![POSSE Party Pixelfed account credentials form](../images/pixelfed-6.png)

Once saved, POSSE Party will be able to publish crossposts to your Pixelfed account using your site's feed and account settings.

Because Pixelfed posts require an image, POSSE Party will publish feed entries that include one or more images (uploading up to ten per post) and will skip entries that have no image. Video media is not yet supported and is skipped.
