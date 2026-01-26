# Initial Concept
PT Mate (PT伴侣) is a mobile-centric Private Tracker (PT) client that allows users to browse, search, and manage torrents across multiple sites without requiring a self-hosted backend or additional Docker containers.

# Product Definition

## Target Audience
- **Enthusiastic PT Site Users**: Users who want a convenient, mobile-first experience to manage their private tracker accounts and downloads on the go.

## Core Goals
- **"One-Stop" Management**: Provide a unified interface for browsing latest torrents, performing aggregated searches across multiple sites, and managing remote download tasks in a single application.
- **Privacy & Simplicity**: Operates directly as a client on the user's device, communicating with PT sites and downloaders without intermediary servers.

## Key Features
- **Pure Mobile Client**: A standalone application that does not rely on any self-hosted backend service or Docker containers.
- **Unified Aggregated Search**: Search across multiple PT sites (M-Team, NexusPHP) simultaneously with a single query.
- **Integrated Download Management**: Native support for qBittorrent and Transmission, including connection testing, category/tag management, and real-time status updates.
- **Modern UI/UX**: Built with Material Design 3, offering a responsive layout and a polished user experience.
- **Secure Storage**: Sensitive credentials like Passkeys and passwords are encrypted and stored locally on the device.

## Development Priorities
- **Broad Site Support**: Expanding compatibility to include more site architectures such as Gazelle and Unit3D.
- **Enhanced NexusPHP Compatibility**: Continuously improving site adapters to support a wider range of NexusPHP-based websites and their specific configurations.
