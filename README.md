# Kleenova

Kleenova is a Flutter application for browsing and booking home cleaning
services.

## Run locally

Install Flutter, then run:

```sh
flutter pub get
flutter run
```

To create a local web build:

```sh
flutter build web --release
```

## Web deployment

The GitHub Actions workflow in `.github/workflows/deploy-pages.yml` builds the
Flutter web app and deploys it to GitHub Pages whenever code is pushed to
`main`. The expected URL is
`https://itsmeshion30.github.io/Kleenova/`.

In the repository settings, enable GitHub Pages with **GitHub Actions** as the
build and deployment source if Pages has not been enabled yet.

## Backend configuration

The app connects to Supabase. The Supabase URL and publishable/anonymous client
key are used by the Flutter client; privileged service-role and payment
provider secrets must only be configured as Supabase Edge Function secrets.
Never put those server secrets in Flutter code or commit them to this
repository.
