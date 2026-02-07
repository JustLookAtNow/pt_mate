# Specification: Gazelle Site Adapter Integration

## Overview
This track involves implementing a new site adapter for the Gazelle architecture within PT Mate and refactoring the existing Webview login widget to be generic. The reference site for implementation and testing is `https://mooko.org/`. The login process will utilize a generic Webview-based approach with a manual trigger for cookie capture.

## Functional Requirements
- **Generic Web Login Widget:**
    - Refactor `lib/widgets/nexusphp_web_login.dart` to remove "NexusPHP" specificity.
    - Rename the file and class (e.g., `WebLoginWidget`) to serve as a generic login interface.
    - Support configuration for different login paths and success indicators if necessary, or keep the manual "Get Cookie" trigger as the primary method for Gazelle.
- **Gazelle Adapter Implementation:**
    - Create a new `GazelleAdapter` class (likely in `lib/services/api/gazelle_adapter.dart`) that implements the `SiteAdapter` interface.
    - Register the new adapter in `SiteAdapterFactory` within `lib/services/api/site_adapter.dart`.
- **User Statistics:**
    - Fetch and display user statistics (Ratio, Upload, Download, Buffer, etc.) using the Gazelle JSON API (`action=index`).
- **Torrent Browsing & Search:**
    - Implement `searchTorrents` in `GazelleAdapter` to support browsing latest torrents and searching via the Gazelle JSON API (`action=browse`).
    - Map Gazelle search results to the application's internal `Torrent` model.
- **Torrent Interaction:**
    - Implement `genDlToken` (or equivalent) to retrieve download URLs/files for `qBittorrent`/`Transmission`.

## Non-Functional Requirements
- **Refactoring:** Ensure the `nexusphp_web_login.dart` refactoring does not break existing NexusPHP site logins.
- **TDD:** New adapter logic must be covered by unit tests.
- **Type Safety:** Strict typing for API responses.

## Acceptance Criteria
- `lib/widgets/nexusphp_web_login.dart` is successfully renamed and refactored to a generic component.
- `GazelleAdapter` is implemented and registered.
- Users can log in to `https://mooko.org/` using the refactored Webview widget.
- User stats and torrent lists from `https://mooko.org/` are correctly displayed.
- Unit tests pass for the new adapter.
