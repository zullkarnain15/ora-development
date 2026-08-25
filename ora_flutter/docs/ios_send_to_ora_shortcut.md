# Send to ORA — Apple Shortcut specification

`Send to ORA` is the iPhone bridge from the Share Sheet to the ORA PWA. It does not store an ORA NIK, PIN, session token, or backend secret. The Shortcut posts only temporary share input and then opens ORA, where the normal login and confirmation flow applies.

## Accepted Share Sheet input

Enable **Show in Share Sheet** and accept:

- URLs
- Text
- Images

The intended daily flow is: **Strava → Share → Send to ORA**. A single URL, a text summary, a screenshot, or a combination is accepted. ORA parses URL/text first and asks for manual review when image OCR is unavailable.

## Exact Shortcut actions

Create a new Shortcut named **Send to ORA**, open its Details, enable **Show in Share Sheet**, and select URLs, Text, and Images as accepted types. Add these actions in order:

1. **Set Variable** — name it `Share Input`, value `Shortcut Input`.
2. **Get URLs from Input** — input `Share Input`. Save the first result as variable `Shared URL`. If there is no URL, use an empty text value.
3. **Get Text from Input** — input `Share Input`. Save the result as variable `Shared Text`. If the share contains no text, use an empty text value.
4. **Get Images from Input** — input `Share Input`. Use only the first image.
5. In an **If** block for an available image:
   - **Resize Image** to a maximum width of 1280 px.
   - **Convert Image** to JPEG, quality about 50%.
   - **Base64 Encode** the converted image with no line breaks.
   - Set `Image Base64` to that result, `Image MIME` to `image/jpeg`, and `Image Name` to `activity.jpg`.
6. **Dictionary** with these exact keys:

   | Key | Value |
   | --- | --- |
   | `action` | `createImportToken` |
   | `sharedText` | `Shared Text` |
   | `sharedUrl` | `Shared URL` |
   | `sourceHint` | `STRAVA` |
   | `imageBase64` | `Image Base64`, only when an image exists |
   | `imageMimeType` | `Image MIME`, only when an image exists |
   | `imageName` | `Image Name`, only when an image exists |

7. **Get Contents of URL**:
   - URL: the deployed Apps Script Web App endpoint used by ORA (`ORA_BACKEND_URL`).
   - Method: `POST`.
   - Request Body: `JSON`.
   - JSON: the Dictionary from step 6.
8. From the response Dictionary, get `data`, then get `importToken`.
9. If `importToken` has no value, show **ORA IMPORT COULD NOT START** and stop the Shortcut.
10. **URL Encode** `importToken`.
11. **Open URLs** with:

    `https://zullkarnain15.github.io/ora-development/#/import?t=<URL-encoded importToken>`

The hash route is intentional: it opens correctly under the current GitHub Pages base path without requiring a server rewrite for `/import`.

## One-time ORA setup link

After the official Shortcut is created and published from an iPhone, copy its iCloud sharing URL and provide it to the release build:

```powershell
flutter build web --release --base-href /ora-development/ `
  --dart-define=ORA_IOS_SHORTCUT_URL=https://www.icloud.com/shortcuts/REPLACE_ME
```

Until that URL is configured, ORA deliberately shows the setup action as unavailable and never claims that the Shortcut is installed. A PWA cannot reliably detect Shortcut installation.

## Limits and privacy

- Temporary tokens expire after 10 minutes and are consumable once.
- Screenshot payloads are limited to 2 MB by the backend; resize/compress before Base64 encoding.
- Screenshot bytes are sent in the POST body, never in the ORA URL.
- Temporary payload creation does not create an Activity or update XP, Quests, Guilds, or leaderboards.
- ORA only saves after the user reviews the preview and presses **SAVE ACTIVITY**.
- The Shortcut must not contain NIK, PIN, ORA session tokens, or private backend secrets.

An installable `.shortcut` binary is intentionally not generated on Windows. Publish the official Shortcut from an iPhone, then configure its iCloud link as described above.
