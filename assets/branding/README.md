# Shadow Learner branding asset

Upload or replace your own final logo at this exact path:

`assets/branding/app_logo.png`

Requirements:
- PNG format.
- Square canvas, ideally 1024 x 1024 pixels.
- Keep the main emblem centered with safe padding so Android adaptive icons do not crop it.
- A transparent background is recommended for the emblem. The app supplies the deep navy background (`#050B18`).

After this file is added to the `main` branch, GitHub Actions automatically generates:
- Android launcher icon sizes.
- Android splash-screen artwork, including Android 12+.

You do not need to edit `pubspec.yaml` or the workflow when replacing the logo. Just replace this one PNG and commit it.
