# LinkedIn Page Account Setup

This guide connects a LinkedIn Company Page to POSSE Party so it can publish posts as the Page. To post as your personal profile, see [LinkedIn Account Setup](linkedin.md). A personal account and a Page account can run side by side on the same instance.

## What POSSE Party Needs From You

- `Client ID`
- `Client Secret`
- `Access Token`
- `Organization URN` (a value like `urn:li:organization:12345678` that identifies your Page)

Posting as a Page uses LinkedIn's Community Management API, which LinkedIn grants on request to registered organizations. LinkedIn will not add it to an app that already has other products, such as Share on LinkedIn, so the Page needs a developer app of its own. You must be an admin of the Page.

## How to Set Up Your Account

1. [Create a LinkedIn app for the Page](#1-create-a-linkedin-app-for-the-page)
2. [Request the Community Management API](#2-request-the-community-management-api)
3. [Check the scope and add the redirect URL](#3-check-the-scope-and-add-the-redirect-url)
4. [Generate an access token](#4-generate-an-access-token)
5. [Find your Organization URN](#5-find-your-organization-urn)
6. [Add the Page to POSSE Party](#6-add-the-page-to-posse-party)

### 1. Create a LinkedIn App for the Page

Create a new app as in [step 1 of the personal guide](linkedin.md#1-create-a-linkedin-app), choosing your Company Page as the app's page. A super admin of the Page then verifies the app, using the verification link on the app's **Settings** tab.

### 2. Request the Community Management API

1. On the app's **Products** tab, find **Community Management API** and click **Request access**.
2. Fill in the Development Tier access form: your organization's legal name, registered address, website, privacy policy URL, and a business email.
3. Wait for LinkedIn's decision, which arrives by email. LinkedIn does not let you apply again from the same app. If it rejects the request, read the reason and apply from a new app.

### 3. Check the Scope and Add the Redirect URL

1. Once access is approved, open the app's **Auth** tab. Confirm that `w_organization_social` is listed under **OAuth 2.0 scopes**, and take note of your **Client ID** and **Client Secret**.
2. Under **Authorized redirect URLs for your app**, add `https://YOUR_IP_OR_DOMAIN/credential_renewals/linkedin`, replacing the protocol and host with the public URL of your instance. This is the same callback the personal LinkedIn account uses. LinkedIn requires an exact match, so enter the full path, not only the domain.

### 4. Generate an Access Token

Follow [step 4 of the personal guide](linkedin.md#4-generate-an-access-token) on this app, selecting the `w_organization_social` scope. Sign in as a member who is an admin of the Page.

### 5. Find Your Organization URN

Open your Page's admin view. Its address looks like `https://www.linkedin.com/company/12345678/admin/`, and the number is your organization ID. Your Organization URN is `urn:li:organization:` followed by that number, for example `urn:li:organization:12345678`.

### 6. Add the Page to POSSE Party

1. In POSSE Party, go to **Accounts** and click **Add Account**. Give the account a label and select **LinkedIn Page** as the platform.

2. Under **Credentials for LinkedIn Page**, fill:
    - `Client ID`
    - `Client Secret`
    - `Access Token`
    - `Organization URN`

Once saved, POSSE Party will publish crossposts to your Page and will remind you by email and on the **Logs** page when the access token needs renewing. Renewing sends you through LinkedIn's sign-in again, so sign in as an admin of the Page.
