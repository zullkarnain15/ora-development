ORA Watch Face Layout Editor

1. Extract folder ini ke:
D:\ORA-Development\ora_garmin\ora_watchface\layout_editor

2. Pastikan sibling folder berikut ada:
D:\ORA-Development\ora_garmin\ora_watchface\assets_ready

3. Buka index.html.
Jika font/asset tidak tampil sempurna karena file:// restriction, jalankan:
cd D:\ORA-Development\ora_garmin\ora_watchface
python -m http.server 8000

Lalu buka:
http://localhost:8000/layout_editor/

Fitur:
- canvas 360x360
- drag layer
- edit X/Y/W/H
- preview Jersey 10 dan Press Start 2P
- toggle visible
- load PNG manual
- zoom
- safe-circle
- export/copy JSON

Setelah layout pas, copy JSON dan berikan ke Codex/ChatGPT untuk diterapkan ke Monkey C.
