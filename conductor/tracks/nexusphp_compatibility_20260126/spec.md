# Track Specification: Improve NexusPHP Compatibility

## Overview
The goal of this track is to make PT Mate's NexusPHP site adapters more robust and compatible with a wider range of NexusPHP-based websites. Currently, variations in HTML structure, CSS classes, and metadata presentation across different sites can lead to parsing failures.

## Objectives
1. **Flexible Parsing**: Transition from rigid table-index-based parsing to more flexible CSS selector or attribute-based extraction.
2. **Diverse Metadata Support**: Handle various date formats, file size representations, and promotional status (e.g., Free, 2x) accurately.
3. **Pagination Handling**: Improve detection and execution of pagination across different site skins.
4. **Test-Driven Robustness**: Establish a comprehensive test suite using actual HTML snippets from multiple NexusPHP sites to ensure continued compatibility.

## Scope
- `lib/services/api/nexusphp_adapter.dart`
- `lib/services/api/nexusphp_web_adapter.dart`
- Corresponding unit tests in `test/`

## Requirements
- Support sites with different table column orders.
- Correctly extract Torrent ID, Title, Description, Size, Seeders, Leechers, and Download URL.
- Handle "Passkey" vs "RSS Token" authentication differences where applicable in the adapters.
- Maintain existing M-Team compatibility.
