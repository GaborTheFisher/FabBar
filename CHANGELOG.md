# Changelog

All notable changes to FabBar will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Adaptive bottom/leading/trailing placement following the system's preferred
  vertical edge on iOS 27.1, with bottom fallback on earlier supported runtimes.
- A 50pt vertical destination rail, short-rail destination chooser and separate
  primary action, with measured per-edge safe-area clearances.
- Regression coverage for compact-to-rail round trips, RTL selection and native
  accessibility activation. The merged package passes 63 tests on each of iOS 26
  and Duo 27.1; consuming-app and physical-device qualification remain separate.

### Changed

- Keep native `UISegmentedControl` glass selection horizontally and neutral
  custom glass selection vertically, with accent icons in both presentations.
- Preserve compact horizontal inline labels and content-hugging sizing alongside
  Duo placement; changing axes restores the selected horizontal presentation.
- Require the iOS 27.1 build SDK for automatic side placement; public UI remains
  available from iOS 26.

### Fixed

- Keep hosted primary content attached and centered across bar replacement,
  including late layout from an obsolete host and rotated chooser-button layout.
- Preserve variable-width compact tab hit routing, including logical RTL order.
- Keep secondary menus reachable, correctly anchored and fully removed on
  collapse, resize or teardown, including accessibility escape.

## [1.1.0] - 2026-02-24

### Changed
- Accent color now clips to the glass indicator position in real time, matching native tab bar behavior during drag

## [1.0.2] - 2026-02-24

### Changed
- Inject content views directly into segment subtrees for proper Liquid Glass magnification, replacing the overlay-based tab rendering
- Support dynamic tab changes (count, order, identity)
- Leading-align tabs with fixed segment width when fewer than 3 tabs, matching native tab bar behavior
- Improved alignment and font weight for more accurate reproduction of the native tab bar

## [1.0.1] - 2026-01-26

### Fixed
- Fix tab staying dimmed after sheet dismissal

## [1.0.0] - 2026-01-23

Initial release.
