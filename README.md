# clinic_q

ClinicQ uses Supabase for authentication, data access, and realtime updates.

## Environment variables

Create a `.env` file for local development using `.env.example` as a template.

Required values:

- `SUPABASE_URL`: your Supabase project URL
- `SUPABASE_ANON_KEY`: your Supabase public anon key
- `BASE_URL`: the public base URL of the app

Example:

```env
SUPABASE_URL=https://your-project-id.supabase.co
SUPABASE_ANON_KEY=your-public-anon-key
BASE_URL=https://your-app.vercel.app
```

## Which token the app needs

The frontend must use the Supabase `anon` key only. Do not put the Supabase service role key in a Flutter web app.

At runtime the app initializes Supabase with:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

After a user logs in, Supabase returns and manages the user session tokens automatically:

- `access_token`
- `refresh_token`

Those user session tokens are not manually supplied anywhere in this codebase.

## Login flow

- Email/password login calls Supabase auth directly.
- Google login uses OAuth and redirects back to `/auth/callback`.

If Google login works locally but fails on Vercel, make sure these URLs are allowed in Supabase Auth settings:

- `http://localhost:3000/auth/callback`
- `https://your-app.vercel.app/auth/callback`
- optionally `https://*.vercel.app/auth/callback` for preview deployments

Also set the Supabase site URL to your production app URL.

## Vercel note

This app reads values from a physical `.env` file at build/runtime startup. For Vercel deployments, the build script generates that file automatically from Vercel environment variables before running the Flutter build.

If you deploy from source on Vercel, generate `.env` during the build before running `flutter build web`.

Example build step:

```sh
echo "SUPABASE_URL=$SUPABASE_URL" > .env
echo "SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY" >> .env
echo "BASE_URL=$BASE_URL" >> .env
flutter build web
```

## Fix for `exit code 127` on Vercel

`127` means the command was not found. In this case, Vercel could not find `flutter` in the build image.

Use one of these approaches:

- Deploy prebuilt output: run `flutter build web` locally/CI and deploy `build/web`.
- Let Vercel install Flutter and build from source (scripted in this repo).

Example Vercel build command (bash):

```sh
git clone https://github.com/flutter/flutter.git --depth 1 -b stable
export PATH="$PWD/flutter/bin:$PATH"
flutter config --no-analytics
flutter --version
flutter pub get
flutter build web \
	--dart-define=SUPABASE_URL=$SUPABASE_URL \
	--dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
	--dart-define=BASE_URL=$BASE_URL
```

Because the app now supports both `.env` and `--dart-define`, this command works without creating a `.env` file in Vercel.

### Repo-ready Vercel setup

This repository includes [scripts/vercel-build.sh](scripts/vercel-build.sh) and [vercel.json](vercel.json) is configured to call it. The script writes a temporary `.env` from `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `BASE_URL`, then builds the web app.

In Vercel project settings, set:

- Framework Preset: `Other`
- Build Command: leave empty (uses `vercel.json`)
- Output Directory: leave empty (uses `vercel.json`)
- Environment Variables:
	- `SUPABASE_URL`
	- `SUPABASE_ANON_KEY`
	- `BASE_URL`

After this, redeploy. The script installs Flutter, runs `flutter pub get`, and builds `build/web`.
