# Plan for publishing Errol

This is a working checklist for shipping Errol to the public: a signed and notarized DMG with a drag-to-Applications window, automatic updates through Sparkle, a release workflow in GitHub Actions, download links on the website, and a way to test all of it before anyone else installs it. Tick items off as they land, and add notes under them when something changes.

Started on September 26, 2026.

## How a release works now

1. Push a tag like `v1.0.0` from `main`. The release workflow runs the contract tests, archives the app with Developer ID, notarizes and staples it, packs the ZIP for Sparkle and the DMG for people, notarizes the DMG, checks both with `scripts/verify-artifact.sh`, writes the update feed, and publishes all of it as a **prerelease** on GitHub.
2. Installed copies don't see it. They read `https://errol.chat/appcast.xml`, which the site redirects to the feed in the latest release, and GitHub never counts a prerelease as the latest.
3. Try the update on a real Mac by pointing a copy of Errol at the prerelease's own feed (`defaults write com.t7m8.Errol SUFeedURL https://github.com/tmarkovski/errol/releases/download/v1.0.0/appcast.xml`), choosing Check for Updates, and confirming the Accessibility grant survived and a relay runs. Then `defaults delete com.t7m8.Errol SUFeedURL`.
4. Approve the publish job in the `release-publish` environment. It makes the prerelease the latest release, and from then on every installed copy is offered the update. The job checks that `errol.chat/appcast.xml` offers the new build.

`scripts/release/release.py` does the work in each step, so every step can also be run on this Mac. Run by hand from the Actions tab, the workflow is a dry run: it signs ad hoc, needs no credentials, and keeps the builds as workflow artifacts.

## What I needed from you (done)

All five secrets are set, the Developer ID Application identity is in the login keychain, and the `errol-notary` profile works.

1. **A Developer ID Application certificate** for TM Code & Co. LLC (team `JN3SN725AZ`). In Xcode, open Settings → Accounts, select the team, click Manage Certificates, then + → Developer ID Application. The team already has one from September 1, but its private key isn't on this Mac, and a new one is fine: a Developer ID signature ties the app's identity to the team, not to one certificate. Export it with its private key as a `.p12` (right-click it in the same dialog → Export Certificate, or Keychain Access → My Certificates → Export). Keep the `.p12` and its password in your password manager, and store them as two repository secrets:

   ```bash
   base64 -i DeveloperID.p12 | gh secret set DEVELOPER_ID_CERT_P12
   ```

   ```bash
   gh secret set DEVELOPER_ID_CERT_PASSWORD
   ```

2. **An App Store Connect API key for notarization.** In App Store Connect, go to Users and Access → Integrations → App Store Connect API → Team Keys and generate a key with the Developer role. The `.p8` file can be downloaded only once. The Issuer ID is shown above the list of keys, and the Key ID is in the key's row.

   ```bash
   gh secret set NOTARY_ISSUER_ID
   ```

   ```bash
   gh secret set NOTARY_KEY_ID
   ```

   ```bash
   base64 -i AuthKey_XXXXXXXXXX.p8 | gh secret set NOTARY_KEY_P8
   ```

   For notarizing on this Mac, save the same key into the keychain under the profile name the release script uses:

   ```bash
   xcrun notarytool store-credentials errol-notary --key AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer YOUR-ISSUER-ID
   ```

No provisioning profile is needed. A Developer ID app only needs one for restricted capabilities like iCloud, push notifications, or app groups. Errol's entitlements come from its build settings: the hardened runtime and microphone input, and neither needs a profile. The installer certificates in Xcode's menu are for `.pkg` installers, which Errol doesn't use.

## Decisions

- [x] **The feed lives at `https://errol.chat/appcast.xml`**, a URL we own, which the site redirects to the feed in the latest GitHub release.
- [x] **The first release is 1.0.0.** The build number is the commit count, and that's what Sparkle compares.
- [x] **The Sparkle key stays.** You have the private key saved outside the GitHub secret.
- [x] **You approve releases.** The `release-publish` environment exists with you as its required reviewer, and only `v*` tags can deploy to it.

## Steps

### 1. The DMG

- [x] Build the DMG with `dmgbuild`, run through uv, which writes the Finder window's layout directly, so it works on a CI runner. This is `release.py dmg`.
- [x] Draw a background that shows where to drag the app, rendered at 1× and 2× from `scripts/release/dmg/background.html` by `render_background.py`, and give the volume the app's icon.
- [x] Try it on this Mac with a Release build signed for development. The window opens with the app, the arrow, and Applications in place, and the app inside the image passes `codesign --verify --deep --strict`.

  Notes from building it:

  - Finder always draws icon labels in black over a background picture, even in Dark Mode, so the background has to stay light. It uses the brand's cream rather than the site's charcoal.
  - The window's height includes the 32-point title bar, so the window is 432 points tall and the picture is 420, which leaves room for a shorter title bar.
  - dmgbuild's `hide_extensions` marks the bundle with Finder information, and `codesign --strict` then rejects the app, so the script doesn't use it.
  - On macOS 27, `hdiutil` prints warnings saying its `create`, `attach`, and `convert` commands are deprecated in favor of `diskutil image`. They still work, and dmgbuild will need to move eventually.

### 2. Release scripts that also run on this Mac

- [x] `scripts/release/release.py` has one command per step: `archive` (with `--signing developer-id`, `development`, or `adhoc`), `notarize`, `zip`, `dmg`, `appcast`, and `rehearse`. It downloads Sparkle's tools once, checks them against a pinned checksum, and refuses to run if the app links a different Sparkle version.
- [x] Run the whole chain with Developer ID on this Mac: `archive --signing developer-id`, `notarize` the app, `zip`, `dmg --sign`, and `notarize` the DMG, then `scripts/verify-artifact.sh` on both. Apple accepted both submissions on the first try, and Gatekeeper accepts both as "Notarized Developer ID" with their tickets stapled. The app's designated requirement checks the team ID rather than a certificate:

  ```
  anchor apple generic and identifier "com.t7m8.Errol" and (certificate leaf[field.1.2.840.113635.100.6.1.9] /* exists */ or certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = JN3SN725AZ)
  ```

### 3. Fixes to the release workflow

- [x] Run on the `xcode-27` runner and select `/Applications/Xcode_27.0.app` by path. The old workflow would have picked the 27.2 beta.
- [x] Fix the appcast. The feed now starts from the one in the latest published release, so earlier entries keep their own download links, and the delta updates are uploaded with the release.
- [x] Also upload the DMG as `Errol.dmg`, so that `releases/latest/download/Errol.dmg` always points at the newest release.
- [x] Check the Sparkle download against a checksum, and pin the actions to commit SHAs.
- [x] Make the test before publishing possible, with a prerelease and a `defaults write` instead of a draft.
- [x] Check for the published build with the element Sparkle 2 writes, `<sparkle:version>`. The old check looked for an attribute and would never have matched.
- [x] Refuse a tag that isn't on `main`, or that isn't a version like `v1.2.3`.

### 4. The feed and the website

- [x] Point `SUFeedURL` at `https://errol.chat/appcast.xml`.
- [x] Add `site/public/_redirects`: `/appcast.xml` goes to the latest release's feed, and `/download` goes to its `Errol.dmg`. Both were checked against the built site with `wrangler dev`.
- [ ] Point the site's download buttons at `/download` (`downloadUrl` in `site/lib/site-config.ts`), once 1.0.0 is published. Until then the link would lead to a missing file.
- [ ] Update the README's "Get Errol" section at the same time.

### 5. Testing

- [x] **The DMG on this Mac** (step 1).
- [ ] **A rehearsal of the update on this Mac.** `release.py rehearse OLD NEW --work DIR` takes two builds from `archive --signing development`, makes both trust a throwaway Sparkle key, writes a feed with a delta, installs the old one, and serves the feed from `127.0.0.1:8765`. It's been prepared with 1.0.0 (build 900) and 1.0.1 (build 901); the feed and its signatures check out. What's left is running it: confirm that the update is offered, installs, and relaunches; that it waits while a run is going; and that the Accessibility grant survives.
- [x] ~~A dry run of the workflow~~, skipped. A partial run on September 26 got through the checkout, uv, selecting `/Applications/Xcode_27.0.app` on the `xcode-27` runner, the contract tests, and the version step before it was cancelled. The ad hoc path it would have taken next already works on this Mac.
- [x] **v1.0.0 built as a prerelease** on September 26 (build 179, [release](https://github.com/tmarkovski/errol/releases/tag/v1.0.0)). The build job took three minutes. Checked afterwards: all five files are there; the feed's link points at the tag; the feed's signature verifies against the `SUPublicEDKey` inside the shipped app, so the GitHub secret and the app agree; `Errol.dmg` matches `Errol-1.0.0.dmg`; and with a browser's quarantine flag, Gatekeeper accepts both the DMG and the app inside as "Notarized Developer ID". `errol.chat/appcast.xml` still returns 404, as it should until publishing.
- [ ] **Try 1.0.0 as a new user would**. Download the DMG in a browser on a clean user account, so the file gets the quarantine flag, and confirm that Gatekeeper opens it without a warning, that Accessibility can be granted, and that a relay runs.
- [ ] **The first real update.** Release 1.0.1 and update to it through its prerelease feed. Confirm the Accessibility grant survives, then commit its designated requirement as `Config/designated-requirement.txt`, which the verify script will compare every later release against.
- [ ] **Publish**, and switch the site's download buttons.

## Later

- Convert the project to Xcode's JSON format (`project.xcproj`). It needs Xcode 27.2, which is still in beta, and both formats keep working in the meantime.
- Attach `Config/Release.xcconfig` to the Release configuration and remove the signing settings from `project.pbxproj`, as the file's own comment suggests.
- A Homebrew cask.
- Set the app's category (`INFOPLIST_KEY_LSApplicationCategoryType`, probably `public.app-category.productivity`). Every archive warns that it's missing.
- Stop copying `Info.plist` into the app's resources. Xcode warns that the Copy Bundle Resources phase contains it, because the synchronized folder includes it, so it ends up in `Contents/Resources/Info.plist`. Adding it as a membership exception on the folder would fix that.
- Release notes: a `docs/release-notes/<version>.md` file, when there is one, becomes both the GitHub release's text and the notes in Sparkle's update window.
