# Build 27 local validation — 2026-09-13

Status: installed locally and user-confirmed working on 2026-09-13; approved for publication.

The user's Build 25 screenshots showed zero context items in two Work task views, whereas an ordinary chat returned ten items. Those screenshots alone did not explain where extraction failed.

A local diagnostic-only Build 26 preserved the extraction behavior and added aggregate counters. In the available ChatGPT conversation, ContextInput reported 402 scanned nodes, maximum depth 24, 186 depth-limit cuts, and two context items. The node budget was not exhausted.

Build 27 increases the bounded recursion depth from 24 to 64, preserving the 1800-node budget and existing geometry filters. On the subsequent live scan, ContextInput reported 862 nodes, maximum depth 29, zero depth cuts, and 32 context items. It chose English; ABC was already selected, so this was not an actual Hebrew-to-English typing test.

Verification:

- New forty-wrapper English and Hebrew transcript fixtures fail with the old depth limit and pass with the new limit.
- Existing nested/flat, incomplete-visible-children, crowded-window, unrelated-column, and empty/draft fixtures pass.
- Diagnostic fixtures distinguish depth truncation, budget exhaustion, unavailable frames, geometry rejection, absent children, and absent windows without storing message content in the counters.
- Classifier, input-source, capability, and scrollable Settings tests pass.
- Installed Settings shows 0.2.6 (Build 27), automatic switching enabled, and Accessibility Allowed. Code-signing designated requirement matches the preceding release.

Build 26 was diagnostic-only and was not published. Version 0.2.5 is therefore skipped for release. After being asked to retry all three sessions, the user reported "works" and requested publication.
