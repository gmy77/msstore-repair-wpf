@echo off
cd /d "%~dp0"
git config user.name "Claude & Gimmy"
git config user.email "gimmy077@gmail.com"
git add -A
git commit -m "Release v3.0.0: Modern UI, font scaling, config persistence

- Complete WPF UI redesign with Windows 11 accent colors
- Color-coded RichTextBox log (green/amber/red per level)
- Font size slider (10-20px) with config.json persistence
- Cancel button to abort running operations
- Confirmation dialogs before destructive operations
- Tooltips on every button
- Live elapsed time counter in status bar
- Admin badge in header
- Professional README and updated LICENSE

Co-authored-by: Gimmy Pignolo <gimmy077@gmail.com>"
git push origin main
echo.
echo Done! Press any key to close.
pause
