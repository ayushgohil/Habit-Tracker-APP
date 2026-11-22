# Releasing Ember

Releases are built by GitHub Actions. Nothing is built or published when you push to `main`; a release happens when you push a version tag.

## Cut a release

1. Pick the version, for example `0.2.0`, and set it in `pubspec.yaml`:

   ```yaml
   version: 0.2.0+1
   ```

   The part after `+` is replaced by the workflow run number, so only the `0.2.0` has to be right.
2. Merge that change to `main`.
3. Tag the merge commit and push the tag:

   ```bash
   git checkout main && git pull
   git tag v0.2.0
   git push origin v0.2.0
   ```
4. Watch the **Release** run in the Actions tab. It checks that the tag matches `pubspec.yaml`, runs `flutter analyze` and `flutter test`, builds three signed APKs (`arm64-v8a`, `armeabi-v7a`, `x86_64`), writes `SHA256SUMS.txt` and publishes a GitHub Release with notes generated from the merged pull requests.
5. Open the release and edit the notes if you want to highlight the best changes.

A tag with a dash, such as `v0.3.0-beta.1`, is published as a pre-release.

If a release run fails, fix the problem, delete the tag (`git push origin :refs/tags/v0.2.0` and `git tag -d v0.2.0`) and tag again. If you already have a draft or half-published release, delete it first.

## Signing

Android only lets an APK update an installed app when both are signed with the same key. Every release must use the same key, so a new APK installs over the old one and keeps people's habits. The key lives in the repository's Actions secrets; it is never committed.

One-time setup:

1. Actions tab -> **Create signing key** -> **Run workflow**.
2. When it finishes, download the `ember-signing-key` artifact. It holds `ember-signing.jks` (the key) and `ember-signing-secrets.txt`.
3. Repo **Settings -> Secrets and variables -> Actions -> New repository secret**. Add four secrets, copying each value from `ember-signing-secrets.txt`: `ANDROID_KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.
4. Keep a copy of `ember-signing.jks` and the passwords somewhere safe, such as a password manager. If they are lost, installed copies can never be updated. Then delete the artifact from the workflow run.

The release run prints the certificate fingerprint of each APK. It must be identical for every release.

To sign a build on your own computer, put the same four values in `android/key.properties` (never commit it):

```properties
storeFile=/absolute/path/to/ember-signing.jks
storePassword=...
keyAlias=ember
keyPassword=...
```

## Notes

- Release workflows run on GitHub's servers; forks cannot read your secrets, so a fork cannot publish a release signed with your key.
- Anyone who forks Ember should create their own signing key and change the application id (`com.nextlyr.ember`) if they publish their own build.
