# Changelog

## [1.0.5] - 2026-11-18

### Changed
- Picks up game-common 1.17.0 (a board redraw fix used by chess, binairo and
  tatami; no change in this game).

## [1.0.4] - 2026-11-12

### Changed
- Picks up game-common 1.16.0: games for two readers (new Two readers
  category) and the shared Start / Join dialog.

## [1.0.3] - 2026-11-04

### Fixed
- The tool no longer crashes when an outdated plugin is installed alongside:
  shared modules left behind by an older plugin are replaced by this
  plugin's own copy instead of being used as they are.

## [1.0.2] - 2026-11-04

### Changed
- Uses less memory: the tool loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unused.

## [1.0.1] - 2026-11-03

### Fixed
- Always listed under Tools → Games → Party & quiz, never under "Other",
  whichever game's copy of the shared category table the reader loaded.

## [1.0.0] - 2026-11-03

### Added
- First release: coin flip, random number in a range, pick a name, turn order, balanced teams (2–6) and a raffle without replacement, with large results for the whole table.
- Saved lists of names (create, edit, rename, delete), and import of the Score sheets players.
- Draws seeded from the system's entropy each time the screen opens; history and raffle in progress kept across sessions.
- Rules in English and French; interface in English, French, Spanish and German.
