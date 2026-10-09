# 0100. Import activities from FIT files with a decoder in Gleam

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (prefilled form, parser in Gleam, laps stored), agent

## Context

[0005](0005-wearable-data-integration.md) chose FIT import as the way in for watches without Strava, parsed on the
client so it works offline, and left the parser open. The server already accepts client-written activities with
`source = "fit"` ([0009](0009-data-model-and-api-rules.md)), and the Activities screen already labels them "From a file" and lets
their owner change them ([0025](0025-manual-activities.md)). The app build has no npm dependencies: it is Gleam only, bundled by
Lustre's dev tools ([0013](0013-app-shell-and-pwa-build.md), [0033](0033-build-and-run-with-nix.md)).

A FIT file is a binary stream of definition and data messages
([FIT protocol](https://developer.garmin.com/fit/protocol/)). An activity summary needs only three messages:
`file_id` (0), `session` (18) and `lap` (19).

## Options considered

1. **Garmin's `@garmin/fitsdk` through FFI**: it covers the whole profile. But it would bring npm into the app build
   and the Nix package, and grow the bundle by about 100 KB for three messages.
2. **A decoder in Gleam**: it uses BitArray pattern matching and reads only the messages Atlas needs, skipping all
   others by their definitions. It is pure and tested with gleeunit like the rest of the domain code
   ([0003](0003-use-gleam-lustre-frontend.md)).

## Decision

- **Decoder**: `atlas/fit` reads the header, definition messages (either byte order, developer fields skipped),
  normal and compressed-timestamp data messages, and returns the file ID, the first session and the laps. It
  treats FIT's "invalid" sentinels as missing, and only the first file of a chained file is read. It checks the
  header and that the data size fits, but not the CRC: a damaged file fails to decode or gives values the form
  then rejects.
- **Prefilled form**: "Import a .fit file" in the New activity dialog. Picking a file fills the form (day, start
  time, sport, distance, moving time, climb, average heart rate), and the user checks it and saves. Validation is
  the manual form's. The file is read in the browser through a thin FFI (`file.ffi.mjs`) and is not uploaded or kept.
- **What is stored**: `source = "fit"`, the form's values, and from the file `elapsed_time_s`, `max_hr` and `laps`
  in the shape the Strava hook writes ([0012](0012-strava-integration-hooks.md)). The exact start (with seconds),
  distance and time are kept unless the user changed that field.
- **Sport**: running (trail run when the sub-sport is trail), walking, hiking, cycling, swimming, and strength
  training map to Atlas's sports. Everything else is Other.
- **Duplicates**: `external_id` is `<serial number>-<time created>` from `file_id`, or the session start when those
  are missing, so the existing unique index on `(owner, source, external_id)` rejects a second import. The screen
  says so before saving. If the earlier import was deleted but is still on the device as a tombstone, saving
  revives that row (an edit with `deleted = false`) instead of creating a row the index would refuse.

## Consequences

- No new dependency. A FIT feature we did not expect (for example a message bigger than its definition says) makes
  the import fail with a message, not a wrong activity.
- Time-series records (GPS, heart rate per second) are skipped. Reading them later is a change to the same decoder.
- A deleted import whose tombstone is no longer on the device (for example deleted on another device that has not
  synced here yet) is still refused by the server until the purge removes it ([0014](0014-purge-soft-deleted-rows.md)).
- Several files at once (a whole watch export) would be a new flow on top of the same decoder.
