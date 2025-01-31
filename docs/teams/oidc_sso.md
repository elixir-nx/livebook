# OIDC SSO (OpenID Connect Single Sign-On)

Livebook Teams supports OpenID Connect (OIDC) Single Sign-On, allowing you to authenticate users through your existing Identity Provider (IdP) when they access your app servers and Livebook apps.

![](images/auth_via_teams.png)

## Demo

Here's a quick demo of the feature working.

<iframe width="560" height="315" src="https://www.youtube-nocookie.com/embed/rG6OKethdJg?si=qofGf8M10F21IWd5" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>

## Configuration

To integrate Livebook Teams with your OIDC SSO provider, follow these steps.

### 1. Register with your OIDC Provider

Go to your IdP admin, and register Livebook Teams as a Relying Party (client/app). This is the info you’ll need from Livebook Teams:

- **Redirect URI**: The Livebook Teams sign-in callback URL that must be registered with your IdP: ` https://teams.livebook.dev/identity/callbacks/oidc`
- **Required OIDC scopes**: the OIDC scopes Livebook Teams requires: `openid`, `profile`, `email`, `offline_access`

Once that’s done, you should retrieve the following information from the registration process:

- **Client ID**: A unique identifier assigned to Livebook Teams by your IdP.
- **Client Secret**: A confidential key assigned to Livebook Teams by your IdP.
- **Discovery URL**: This is the OIDC metadata URL provided by your IdP. Usual format: `https://YOUR_IDP/.well-known/openid-configuration`

### 2. Configure OIDC in Livebook Teams

<iframe width="560" height="315" src="https://www.youtube-nocookie.com/embed/dNUcRD0A6kU?si=eNQ55-Aeg4I8PPgy" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>

1. Log in to Livebook Teams
2. Go to the **Authentication** panel
3. Click **Add OIDC SSO** and provide the following details:
	- **Name**: A display name for your OIDC provider (e.g., Okta, Microsoft Entra, Keycloak).
	- **Discovery URL**: Use the discovery URL retrieved from your IdP.
	- **Client ID**: Use the Client ID retrieved from your IdP.
	- **Client Secret**: Use the Client Secret retrieved from your IdP.
	- **Enable this SSO provider**: Make sure this option is enabled.
4. Save

### 3. Configure your deployment group to authenticate via Livebook Teams

To enable OIDC authentication, your deployment group must be configured to use authentication via Livebook Teams.

<iframe width="560" height="315" src="https://www.youtube-nocookie.com/embed/27GImleM3MQ?si=jlsa7cGvIgnM4xmN" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>

In order to do so, follow these steps:

1. Log in to Livebook Teams.
2. Navigate to the **Deployments** panel.
3. Click **Edit** on the deployment group where you want to enable authentication.
4. Ensure that **Authenticate via Livebook Teams** is enabled.
5. Save your changes.

### Test the integration with your OIDC IdP

To verify the integration is working, follow these steps:

1. Navigate to an application deployed in a deployment group configured for OIDC authentication.
2. The app server will redirect you to Livebook Teams for authentication.
3. On the authentication page, you will see an option to sign in using your configured OIDC provider.
4. Click the name of your OIDC SSO configuration and follow the authentication steps provided by your IdP.
5. Once authentication is complete, the IdP will redirect you back to your app server, and you will be successfully signed in.
