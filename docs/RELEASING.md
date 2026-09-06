# Releasing a friend beta

ContextInput's free beta channel uses two stable secrets stored in the release
Mac's login Keychain:

1. **ContextInput Beta Code Signing** signs every app version. Keeping this exact
   identity is what lets macOS recognize an update as the same Accessibility app.
2. Sparkle account **contextinput-beta** signs every update archive. Its public
   key is embedded in the app, so a different private key cannot publish an update.

Back up both before depending on this channel. In Keychain Access, export the
ContextInput certificate together with its private key as an encrypted `.p12`.
Store that file and its password in separate secure locations. Export the Sparkle
private key with the official tool and immediately move the resulting sensitive
file into the same secure backup system:

```sh
./scripts/fetch-sparkle.sh
.build/dependencies/Sparkle-2.9.6/bin/generate_keys \
  --account contextinput-beta -x /a/secure/location/contextinput-sparkle-key
```

Never commit either private-key backup.

## First release on a Mac

Create the beta identity once, then package the release:

```sh
./scripts/setup-beta-signing.sh
./scripts/test.sh
./scripts/test-settings.sh
./scripts/verify-update-identity.sh
./scripts/package-beta.sh
```

The package command builds only Apple silicon artifacts:

- `dist/releases/ContextInput-0.2.0-arm64.dmg` — send this to friends.
- `dist/releases/ContextInput-0.2.0-arm64.zip` — upload as the Sparkle asset.
- `appcast.xml` — commit and push this signed update-feed entry.

Publish a GitHub prerelease tagged `v0.2.0-beta.1`, and attach both artifacts.
The asset name and tag must remain exactly as recorded in `appcast.xml`. The feed
must not be pushed without its matching ZIP being available in that release.

After the implementation commit is clean and pushed, GitHub CLI can perform that
safe draft-upload/feed-push/publish sequence automatically:

```sh
brew install gh
gh auth login
./scripts/publish-beta.sh
```

The script refuses to publish unless `gh` is authenticated as **nel-ofir**. It
uploads a draft first, commits and pushes the signed appcast, then makes the
release visible. If any step fails, it leaves the release as a safe draft.

## Subsequent beta

1. Increase both `VERSION` and `BUILD_NUMBER`; the build number must always rise.
2. Add matching Markdown notes under `packaging/release-notes/`.
3. Run the tests and `verify-update-identity.sh`.
4. Package with explicit values, for example:

   ```sh
   VERSION=0.2.1 BUILD_NUMBER=16 BETA_NUMBER=2 ./scripts/package-beta.sh
   ```

5. Create the matching GitHub prerelease and attach the ZIP/DMG.
6. Commit and push the newly generated `appcast.xml` only when the ZIP is ready.
7. Test **Check for Updates…** from the previous installed beta on another Mac.

Do not regenerate either key, change `CFBundleIdentifier`, or build a release with
an ad-hoc signature. Any of those breaks the continuity the beta channel relies
on. A real two-version update on a second Mac remains the final proof that its
macOS release preserves Accessibility approval.
