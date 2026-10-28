# Cloudflare Pages setup (issue #129)

Owner-only setup notes for the mayos.online web deployment (ADR 048/086). The
landing page is served at `https://mayos.online/`, the Flutter app at
`https://mayos.online/app/`, and the API at `https://api.mayos.online`.

Nothing here goes in the repository: the API token and account ID live in your
shell or password manager.

## 1. Account

1. Sign in or sign up at <https://dash.cloudflare.com>. The free plan is enough.
2. Note the **Account ID**: open **Workers & Pages**; it is shown in the right
   sidebar ("Account details"). It is also the hex segment after
   `dash.cloudflare.com/` in the address bar.

## 2. API token (Cloudflare Pages: Edit, this account only)

1. Top-right avatar → **My Profile** → **API Tokens** → **Create Token**.
2. Choose **Create Custom Token** → **Get started**.
3. Name: `mayos-pages-deploy`.
4. **Permissions:** `Account` · `Cloudflare Pages` · `Edit`. Add nothing else.
5. **Account Resources:** `Include` · your account (not "All accounts").
6. Leave Client IP filtering empty, optionally set a TTL, then
   **Continue to summary** → **Create Token**. Copy it now; it is shown once.
7. Keep it locally in `~/.config/mayos/web.env` (mode 600), the file
   `scripts/deploy_web.sh` sources, together with the other web build inputs:

   ```bash
   mkdir -p ~/.config/mayos && touch ~/.config/mayos/web.env && chmod 600 ~/.config/mayos/web.env
   # ~/.config/mayos/web.env
   CLOUDFLARE_API_TOKEN="<token>"
   CLOUDFLARE_ACCOUNT_ID="<account id>"
   GOOGLE_WEB_CLIENT_ID="<web-client-id>.apps.googleusercontent.com"
   POSTHOG_CLIENT_KEY="phc_<public-project-key>"
   ```

   Never paste it into `.env`, `fly.toml`, an issue, or a commit.

## 3. Pages project (direct upload, no Git integration)

The CLI route is exact and needs only Node (`npx` fetches wrangler):

```bash
set -a; source ~/.config/mayos/web.env; set +a
npx wrangler pages project create mayos --production-branch=main
# If the name is taken in your account, use the fallback:
# npx wrangler pages project create mayos-app --production-branch=main
```

Dashboard alternative: **Workers & Pages** → **Create** → **Pages** tab →
**Upload assets** (direct upload, not "Connect to Git") → project name `mayos`
→ **Create project**. The dashboard asks for a first upload; drop any folder
holding a one-line `index.html` placeholder. #130's deploy replaces it.

**Record the real origin.** Open the project in the dashboard and read the
`*.pages.dev` link on its page. Cloudflare adds a random suffix when the
`pages.dev` subdomain is already taken globally (e.g. `mayos-7xq.pages.dev`), so
the origin may not equal `https://<project name>.pages.dev`. Use exactly what the
dashboard shows, with `https://` and no trailing slash, in every step below.
Preview deployments (`<hash>.<project>.pages.dev`) are deliberately not added
to any allow-list.

## 4. Fly: allow the Pages origin (CORS)

The API allows browser origins from `UI_BASE_URL`, a comma-separated list
(`svc/app.py` `web_origins()`). It is not a secret, so set it in `fly.toml`:

```toml
[env]
  UI_BASE_URL = "https://mayos.online,https://www.mayos.online,https://mayos.pages.dev"
```

The first origin is also the `/register` redirect target. `fly.toml` carries
these production origins. A `UI_BASE_URL` Fly secret overrides `[env]` in
`fly.toml`, so update or unset any existing secret during deployment.

Check it from any terminal; the response must echo the apex origin:

```bash
curl -si -X OPTIONS https://api.mayos.online/healthz \
  -H "Origin: https://mayos.online" \
  -H "Access-Control-Request-Method: GET" | grep -i access-control-allow-origin
# access-control-allow-origin: https://mayos.online
```

## 5. Google Cloud (#112): add the owned web origin

In the project that owns the web OAuth client:

1. **Google Auth Platform → Clients** → the *Web application* client →
   **Authorized JavaScript origins**: add `https://mayos.online`. Keep
   `https://mayos.pages.dev` through the transition release; remove it after.
2. **Google Auth Platform → Branding** → **Authorized domains**: add
   `mayos.online`; remove the Pages domain after the transition release.

Origin changes can take a few minutes to reach sign-in.

## 6. Close the loop

The transition Pages origin `https://mayos.pages.dev` remains allowed during the
transition release; `https://mayos.online` is the primary production origin.

## 7. Host redirects (Cloudflare dashboard)

Create an account-level **Bulk Redirect** list entry: source `mayos.pages.dev`,
target `https://mayos.online`, status 301. Turn **Preserve query string**,
**Subpath matching**, and **Preserve path suffix** on; leave **Include
subdomains** off so `*.mayos.pages.dev` previews stay available.

In the `mayos.online` zone, add a **Redirect Rule** with condition hostname
equals `www.mayos.online` and dynamic target
`concat("https://mayos.online", http.request.uri.path)`. Set status 301 and
preserve the query string. These are dashboard rules, not Pages `_redirects`
entries, which cannot match on hostname.

## 8. Fly custom domain for the API

The owner has attached `api.mayos.online` to Fly and issued its certificate. For
reference, the Fly steps are `fly certs add api.mayos.online` and DNS-only A/AAAA
records pointing to the Fly app's assigned addresses. Keep the records
DNS-only; Cloudflare proxying can prevent Fly certificate validation.
