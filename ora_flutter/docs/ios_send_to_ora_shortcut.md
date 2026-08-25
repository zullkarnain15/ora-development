# Apple Shortcut: Send to ORA

`Send to ORA` is installed once on an iPhone. Afterwards the daily flow is:

`Strava → Share → Send to ORA → SHARED ACTIVITY → SAVE ACTIVITY`

The Shortcut must be published as an iCloud Shortcut by the ORA publisher. Do not place an ORA NIK, PIN, session token, or backend secret in it.

## Create the Shortcut

1. Create a new Shortcut named **Send to ORA**.
2. Open its details, enable **Show in Share Sheet**, and accept **Images**, **URLs**, and **Text**.
3. Read **Shortcut Input**. Keep the shared text, extract the first URL when present, and select the first image when present.
4. If there is an image, use **Resize Image** (maximum width 1280 px), **Convert Image** to JPEG (approximately 50% quality), then **Base64 Encode** it without line breaks.
5. Create a Dictionary with these keys:

   - `action`: `createImportToken`
   - `sharedText`: the text from Shortcut Input
   - `sharedUrl`: the first URL from Shortcut Input
   - `sourceHint`: `STRAVA`
   - `imageBase64`: Base64 JPEG, only when an image exists
   - `imageMimeType`: `image/jpeg`, only when an image exists
   - `imageName`: `activity.jpg`, only when an image exists

6. Add **Get Contents of URL** with method **POST**, request body **JSON**, and this final ORA backend endpoint:

   `https://script.google.com/macros/s/AKfycbyD2oOTr39col6dqHTd721TFNizut4-Gi9jSe5CLYaTwMqx1mlQT1jD-JK8fqHSVWsn/exec`

7. Read `data.importToken` from the JSON response. If it is empty, show **ORA IMPORT COULD NOT START** and stop.
8. Add **URL Encode** for that token, then add **Open URLs** with:

   `https://zullkarnain15.github.io/ora-development/#/import?t=<TOKEN>`

9. Test once from Strava, then publish the Shortcut and distribute its iCloud Shortcut URL. Configure that URL in the iPhone-only ORA Settings button when it is available.

Creating an import token does not save an activity. ORA opens `SHARED ACTIVITY`, performs OCR locally, and only saves after the user selects a date/start time and presses **SAVE ACTIVITY**.
