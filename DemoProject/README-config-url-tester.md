# Config URL Tester — preview a test config on iOS

The demo app's **Config URL** tab loads a test config you published from the Mobile tab and
renders it with this SDK's own consent banner, so you can check the layout and copy on a real
iOS screen before you publish it live. Nothing is saved or sent anywhere: the banner's Save and
Dismiss only update a status line.

## Requirements

- macOS with **Xcode 16** and an iOS simulator (or a device you can sign for).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.

## Build and run

From the repository root:

```sh
./launch_demo.sh          # generate the project, build, install and launch on a simulator
./launch_demo.sh --clean  # clean build first
```

The app opens on the **Config URL** tab. The Universal Consent demo is the second tab
(see [README-uc-demo.md](README-uc-demo.md)).

## Load a test config

1. In the Mobile tab of your consent container, publish a test config, then right-click its
   **View config** link and copy the link address.
2. Get the link onto the simulator or device (for the simulator, copy it on the Mac and use
   **Edit → Paste** in the simulator, or the app's **Paste** button).
3. Tap **Paste**, then **Load**.
4. Tap **Show banner** (modal) or **Show full screen**. You can reopen the banner as often as you
   like.

## What the version lines mean

| Line | Meaning |
|---|---|
| SDK library version | The SDK version this app was built from. |
| SDK schema version | The config schema this SDK can render (for example `v1`). |
| Config schema | The schema of the config you loaded, read from the link (`config.v1.json` → `v1`). A legacy `config.json` link shows as unversioned and is treated as `v1`. |
| Artifact | `test` for a Mobile-tab test config, `live` for a published one. |
| Expires | When the link stops working, on this device's clock. |

## Errors

| Message | What happened | What to do |
|---|---|---|
| Not a valid config URL | The text isn't a full `https://` link. | Copy the whole link again. |
| Test URL expired | The link is older than 15 minutes. | Reload the test config panel in the Mobile tab and copy the new link. |
| URL was changed or cut off | The signature doesn't match, usually because the link was truncated. | Copy the whole link again. |
| Config not found | The test config was deleted (after 7 days) or access was denied. | Publish a new test config. |
| Couldn't reach the config | No network connection, or the request timed out. | Check the connection and try again. |
| Unsupported schema version | The config's schema isn't one this app renders. | Pick a matching target in the Mobile tab, or use a test app built for that schema. |
| Config couldn't be read | The file isn't a config this SDK can parse. | Report it to support with the versions shown in the app. |

Test links are valid for **15 minutes**; test configs themselves are deleted after **7 days**.
