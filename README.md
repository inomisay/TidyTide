<p align="center">
  <img src="assets/icon.png" width="110" alt="Tidy Tide icon">
</p>

<h1 align="center">Tidy Tide</h1>

<p align="center">A small Windows app that turns <code>photo (12).jpg</code> into <code>12.jpg</code>.</p>

---

When you select a bunch of files in Windows and rename them all at once, Windows names them `photo (1)`, `photo (2)`, `photo (3)` and so on. If you just want `1`, `2`, `3`, you end up fixing every name by hand. Tidy Tide does that for you.

Drop the files in and check the preview. Then press **Rename**. If something looks wrong, press **Undo**.

## What it does

- Takes the number in the brackets and makes it the whole name: `photo (12).jpg` → `12.jpg`, `(7).png` → `7.png`
- Shows every change before it happens
- Can add zeros in front (`01`, `02` … `10`) so every app sorts the files in the right order
- Leaves a file alone if it has no number in brackets, if two files would end up with the same name, or if the new name is already taken. It never overwrites anything.
- Lets you undo the last rename
- Adds itself to the right-click **Send to** menu

## Install

1. Download this repo (green **Code** button → **Download ZIP**) and unzip it.
2. Double-click `Install Tidy Tide.bat`.
3. Open Tidy Tide from the desktop icon or the Start menu.

If Windows shows "Windows protected your PC", click **More info** → **Run anyway**. Windows shows this for scripts that come from the internet.

To use it from File Explorer, right-click some files or a folder and choose **Send to → Tidy Tide**. On Windows 11, **Send to** is under **Show more options**.

To remove it, run `Uninstall Tidy Tide.bat`.

## Requirements

Windows 10 or 11. Nothing else needs to be installed: it runs on the PowerShell 5.1 and .NET Framework that come with Windows.

## How it's built

It's a single PowerShell script with a Windows Forms window. The rounded buttons, gradient header and waves are drawn by hand with GDI+.

```
app/
  TidyTide.ps1   the app
  setup.ps1      installs or uninstalls it (copies to %LOCALAPPDATA%\TidyTide and makes shortcuts)
  TidyTide.ico   icon
tools/
  make_icon.py   redraws the icon (needs Python + Pillow)
```

To run it without installing:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\app\TidyTide.ps1
```

You can also pass files or folders as arguments and they'll be added to the list.

## License

MIT. See [LICENSE](LICENSE).
