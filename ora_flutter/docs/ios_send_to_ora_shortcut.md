# Official Apple Shortcut: Send to ORA

The official Shortcut is created once by the ORA publisher on an iPhone and distributed with an iCloud Shortcut link. Users only install it once; daily use is **Strava -> Share -> Send to ORA**. There is no setup or import menu inside ORA.

Configure a Shortcut named **Send to ORA**:

1. Enable **Show in Share Sheet** and accept URLs, Text, and Images.
2. Read `Shortcut Input`; extract its text, first URL, and first image.
3. If an image exists, resize it to at most 1280 px wide, convert it to JPEG around 50% quality, and Base64 encode it without line breaks.
4. Create a Dictionary containing `action: createImportToken`, `sharedText`, `sharedUrl`, `sourceHint: STRAVA`, and—when present—`imageBase64`, `imageMimeType: image/jpeg`, `imageName: activity.jpg`.
5. Use **Get Contents of URL** to POST that Dictionary as JSON to the deployed ORA Apps Script web-app endpoint.
6. Read `data.importToken` from the JSON response. If absent, show `ORA IMPORT COULD NOT START` and stop.
7. URL-encode the token and use **Open URLs** with:

   `https://zullkarnain15.github.io/ora-development/#/import?t=<TOKEN>`

Publish this Shortcut from the iPhone and distribute its official iCloud link outside the app. The Shortcut must never contain an ORA NIK, PIN, session token, or backend secret. Temporary payload creation does not save an Activity; ORA only saves after the user presses **SAVE ACTIVITY** in the preview.
