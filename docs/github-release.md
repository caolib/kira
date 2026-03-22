# GitHub Release Signing

This project publishes Android split APKs to GitHub Releases through
[`.github/workflows/release.yml`](../.github/workflows/release.yml).

The workflow now expects your own Android signing key in GitHub Secrets, so
release builds stay upgradeable for users.

## 1. Generate a keystore

Run this once on your machine:

```powershell
keytool -genkeypair -v `
  -keystore upload-keystore.jks `
  -alias upload `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000
```

Keep `upload-keystore.jks` somewhere safe. Back it up. Do not lose it.

## 2. Configure local signing

Create `android/key.properties` from
[`android/key.properties.example`](../android/key.properties.example):

```properties
storeFile=../upload-keystore.jks
storePassword=your-store-password
keyAlias=upload
keyPassword=your-key-password
```

With that file present, local `flutter build apk --release` uses your release
key. Without it, local builds fall back to the debug key.

## 3. Add GitHub Secrets

Add these repository secrets in GitHub:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

To create `ANDROID_KEYSTORE_BASE64` on Windows PowerShell:

```powershell
[Convert]::ToBase64String(
  [IO.File]::ReadAllBytes("C:\path\to\upload-keystore.jks")
) | Set-Content keystore.base64
```

Then copy the contents of `keystore.base64` into the GitHub secret.

## 4. Publish a release

1. Update the version in [`pubspec.yaml`](../pubspec.yaml).
2. Commit and push your changes.
3. Trigger the workflow:
   - push a tag such as `v0.1.0`, or
   - run the workflow manually from the Actions page.

The workflow will:

- restore your keystore from GitHub Secrets
- build split APKs for `arm64-v8a`, `armeabi-v7a`, and `x86_64`
- upload them to a GitHub Release

## Notes

- Android package name is `io.github.caolib.kira`.
- GitHub release builds are expected to use your release key and will fail if
  the signing secrets are missing.
- Keep the same keystore forever if you want users to install updates over
  existing versions.
