---
name: flutter-screenshot
description: Capture and show two Flutter UI screenshots for this project: one landscape/large-screen preview and one portrait/mobile preview, without using Flutter Web.
---

# Flutter Screenshot Skill

Use this skill when the user asks to screenshot the Flutter app or a changed UI in this repository, especially when they want both desktop/large-screen and mobile/portrait previews. This project does not use Flutter Web for screenshots.

## Workflow

1. Choose the entrypoint:
   - Use `lib/main.dart` unless a narrow preview is safer.
   - If a page-specific preview is needed, create a temporary entrypoint under `/tmp` and delete it after screenshots. Do not add preview entrypoints to the repo.
2. Run the bundled script from the repository root:

   ```bash
   python3 .agents/skills/flutter-screenshot/scripts/capture_flutter_screenshots.py \
     --target lib/main.dart \
     --output-dir /tmp/pt_mate_screenshots
   ```

3. The script starts `flutter run -d linux`, locates the app window, captures:
   - `large.png` at `1280x720`
   - `mobile.png` at `393x852`
4. Open both images with `view_image` before replying. Confirm they are not blank and show the expected screen.
5. Reply in Chinese with both Markdown image links:

   ```markdown
   大屏预览：
   ![大屏预览](/tmp/pt_mate_screenshots/large.png)

   手机版预览：
   ![手机版预览](/tmp/pt_mate_screenshots/mobile.png)
   ```

## Notes

- The script requires the Linux desktop Flutter target, X11, and ImageMagick `import`.
- Run the script with escalated permissions when the sandbox blocks GUI launch or X11 capture.
- Keep screenshots in `/tmp` long enough for the user to view them; clean up temporary preview Dart files when done.
