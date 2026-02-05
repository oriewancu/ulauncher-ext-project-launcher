# Changelog

All notable changes to the **Project Launcher** extension will be documented in this file.

## [1.0.1] - 2026-02-05

### Added
- **Support Multiple Terminal**: gnome-terminal, konsole, xfce4-terminal and konsole.
- **Define Run Sonar Coverage**: Choose preference sonar 8.9 LTS or latest.

## [1.0.0] - 2026-02-04

### Added
- **Initial Release**: Dynamic Java project folder scanning.
- **IDE Launchers**: Built-in integration for IntelliJ IDEA and VS Code.
- **SonarQube Support**: Automated Maven commands for SonarQube scans (LTS 8.9 & Latest).
- **Git Tool Integration**: Launch external Git management scripts in a new terminal session.
- **Dynamic Config**: All URLs, Tokens, and Paths are now configurable via Ulauncher UI Preferences.
- **Path Expansion**: Implemented support for `~/` and `$HOME` path formats.

### Fixed
- Prevented zombie processes by implementing `start_new_session=True` for spawned IDEs and terminals.
- Added path validation to prevent crashes when the base project directory is missing.

### Technical Details
- Built for **Ulauncher API v2.0.0**.
- Utilizes the `versions.json` method with `commit: main` for streamlined updates.