# Svara Web

Deploy this folder to Vercel as the web companion for the `Svara` Android app.

## What is included

- shared API base URL wired to `https://rf-snowy.vercel.app`
- Supabase-backed Jam web join page
- song share pages at `/song/[id]`
- artist pages at `/artist/[id]`
- mixed trending home feed with client-side personalization from local library/history
- env-driven branding, links, app deep link, and Jam invite URL generation

## Environment

Copy `.env.example` into your Vercel project env settings.

Important values:

- `NEXT_PUBLIC_SITE_URL`
  Set this to your final deployed domain, for example `https://svara-web.vercel.app`
- `NEXT_PUBLIC_API_BASE_URL`
  Already pointed at `https://rf-snowy.vercel.app`
- `NEXT_PUBLIC_SUPABASE_URL`
  Already pointed at your Supabase project
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
  Already pointed at your publishable key

## Build

This project is configured to build with:

```bash
npm run build
```

The build script uses Webpack for broader local compatibility.

## After deploy

1. Deploy `Svara-web`
2. Copy the live domain
3. Put that domain into `NEXT_PUBLIC_SITE_URL`
4. Redeploy
5. Then app share links can point to the web domain for Jam invites and song pages
