# Changelog

## [1.1.2] - 2026-02-01
This fixes a very common "Permissions denied" created on exiting game
- Add: Saved teleport data is now automatically refreshed on login and when entering houses
- Add: Teleport errors from stale data are detected and the addon automatically tries the next possibility
- Add: Teleport attempts now show which attempt you're on (e.g. "attempt 3/9")
- Add: Success message when teleport completes
- Add: Added credit to TheIceBadger on options screen
- Change: license from CC BY-NC-SA to CC BY-NC

## [1.1.1b] - 2026-02-01
- Fix zip file not extracting as folder on macOS/Linux

## [1.1.1] - 2026-01-31

Currently blizzard is not adding a cooldown to buttons outside of "My home"-teleports, which means you can use the macros as often as you want.
- Add: Message when there is cooldown remaining on house teleport.
- Fix: teleport cooldown check incorrectly blocking saved location buttons that have no cooldown
- Fix: Teleport macros now work immediately after UI reload/relog - im sure no one encountered this bug :)

## [1.1.0] - 2026-01-27

- Add global API reference (`_G.MultipleHouseTeleports`) for addon integration
- Add developer documentation (DEVELOPERS.md)

## [1.0.0] - 2026-01-26

- Initial release
- Save multiple housing plot locations
- Create teleport macros for action bar
- Home teleport macro support
- Displays neighborhood type and name
- Options panel integrated with WoW Settings
- Slash commands: /mht add, list, delete, options