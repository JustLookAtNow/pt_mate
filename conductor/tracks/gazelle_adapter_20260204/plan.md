# Implementation Plan: Gazelle Site Adapter & Generic Web Login

This plan outlines the steps to implement a new `GazelleAdapter` for Gazelle-based PT sites and refactor the existing Webview login widget to be generic.

## Phase 1: Infrastructure & Refactoring
Focus on making the existing Webview login widget generic and setting up the Gazelle adapter skeleton.

- [ ] Task: Refactor `lib/widgets/nexusphp_web_login.dart` to `lib/widgets/web_login_widget.dart`
    - Rename class `NexusPhpWebLogin` to `WebLoginWidget`.
    - Rename file to `web_login_widget.dart`.
    - Update all imports in the project (especially in `lib/pages/site_add_page.dart` or similar).
    - Ensure the logic remains compatible with existing NexusPHP Web logins.
- [ ] Task: Update `SiteType` enum in `lib/models/app_models.dart`
    - Add `gazelle('Gazelle', 'Gazelle 站点', 'Cookie认证', '通过网页登录获取认证信息')`.
- [ ] Task: Create `lib/services/api/gazelle_adapter.dart` skeleton
    - Define `GazelleAdapter` class implementing `SiteAdapter`.
- [ ] Task: Register `GazelleAdapter` in `SiteAdapterFactory` (`lib/services/api/site_adapter.dart`)
    - Add case for `SiteType.gazelle`.
- [ ] Task: Conductor - User Manual Verification 'Phase 1: Infrastructure & Refactoring' (Protocol in workflow.md)

## Phase 2: Gazelle Adapter Implementation (TDD)
Implement the core logic of `GazelleAdapter` using Test-Driven Development.

- [ ] Task: Implement `init` and `testConnection`
    - [ ] Write tests for initialization and basic connection check.
    - [ ] Implement `init` to store configuration.
    - [ ] Implement `testConnection` by calling `action=index` and checking for success.
- [ ] Task: Implement `fetchMemberProfile`
    - [ ] Write tests for parsing Gazelle index API response into `MemberProfile`.
    - [ ] Implement `fetchMemberProfile` using `action=index`.
- [ ] Task: Implement `searchTorrents` (Browsing & Searching)
    - [ ] Write tests for parsing Gazelle browse API response into `TorrentSearchResult`.
    - [ ] Implement `searchTorrents` to handle both browsing (no keyword) and keyword search using `action=browse`.
- [ ] Task: Implement `genDlToken`
    - [ ] Write tests for generating download URLs.
    - [ ] Implement `genDlToken` to return the appropriate download link for a torrent.
- [ ] Task: Implement remaining `SiteAdapter` methods
    - Implement `fetchTorrentDetail`, `toggleCollection`, etc. (Stubs if not immediately supported by Gazelle JSON API).
- [ ] Task: Conductor - User Manual Verification 'Phase 2: Gazelle Adapter Implementation' (Protocol in workflow.md)

## Phase 3: Integration & Manual Verification
Verify the end-to-end flow with a real site.

- [ ] Task: Add `mooko.org` configuration to `assets/site_configs.json` or as a test preset
    - Provide metadata and categories for `mooko.org`.
- [ ] Task: Verify Webview Login with `mooko.org`
    - Ensure the refactored `WebLoginWidget` correctly loads the site and allows manual cookie capture.
- [ ] Task: Verify Dashboard & Torrent List
    - Ensure user stats and torrents are correctly displayed and interactive.
- [ ] Task: Conductor - User Manual Verification 'Phase 3: Integration & Verification' (Protocol in workflow.md)
