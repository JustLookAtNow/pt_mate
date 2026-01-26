# Implementation Plan: Improve NexusPHP Compatibility

## Phase 1: Analysis & Infrastructure
This phase focuses on gathering data and setting up the testing environment to ensure robustness.

- [ ] Task: Collect representative HTML snippets (search results and torrent details) from at least 5 different NexusPHP sites.
- [ ] Task: Create a new test utility to load these snippets and run them through the `NexusPHPAdapter`.
- [ ] Task: Identify specific parsing failures in existing adapters when applied to these snippets.
- [ ] Task: Conductor - User Manual Verification 'Analysis & Infrastructure' (Protocol in workflow.md)

## Phase 2: Parser Refinement
Refactoring the core parsing logic to be more resilient to structural changes.

- [ ] Task: Refactor `NexusPHPAdapter` to use CSS selector-based extraction for torrent list items.
- [ ] Task: Implement a more flexible date parser that handles various localizations and formats common in NexusPHP.
- [ ] Task: Update size parsing to handle different units (KB, MB, GB, TB) and thousands separators reliably.
- [ ] Task: Enhance `NexusPHPWebAdapter`'s login and cookie handling to support sites with custom login challenges.
- [ ] Task: Conductor - User Manual Verification 'Parser Refinement' (Protocol in workflow.md)

## Phase 3: Validation & Regression
Ensuring high quality and no regressions.

- [ ] Task: Run the full suite of collected snippets through the updated adapters and verify 100% success.
- [ ] Task: Verify that existing supported sites (as defined in `assets/sites/`) still function correctly.
- [ ] Task: Achieve >80% test coverage for all modified adapter logic.
- [ ] Task: Conductor - User Manual Verification 'Validation & Regression' (Protocol in workflow.md)
