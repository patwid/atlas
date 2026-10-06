# 0034. Heart-rate zones as an explicit setting

- Status: Accepted (storage and screen); Proposed (default maximum of 190 bpm)
- Date: 2026-10-06
- Deciders: owner asked for configurable zones with defaults; agent (design)

## Context

[0015](0015-domain-core.md) computed five heart-rate zones from the maximum heart rate (50-60, 60-70, 70-80, 80-90 and 90-100 percent),
and noted that athletes who use other schemes would need a setting. Nothing stored a maximum heart rate, so the zones could not be used.
The owner asked for the zones to be explicit settings: configurable, but filled in with default values.

Settings must work offline and reach every device of the athlete, like the rest of the data ([0004](0004-offline-first-data-and-sync.md)).
A coach who sees an athlete's training ([0024](0024-coach-grants-screen.md)) should see the zones it is measured against.

## Options considered

1. **Zones as percentages of a stored maximum** — one number to set, but does not fit athletes whose zones come from a lab test or a
   threshold (Friel, Seiler), which is what "explicit" asks for.
2. **The maximum and the start of each zone in bpm** — every boundary visible and changeable; defaults are worked out from the maximum.
   Five zones are fixed, which is what Strava, Garmin and Polar show.
3. **Store them in `localStorage`** — simple, but per device and invisible to the coach.
4. **Fields on the `users` record** — synced by PocketBase, but outside the outbox and cursors, so not offline-capable.
5. **A synced `athlete_settings` collection** — goes through the outbox, cursors and membership sweep like every other record.

## Decision

We use options 2 and 5.

- **Collection `athlete_settings`** (migration `1760000400_athlete_settings.js`): `owner`, `max_hr` and `hr_zone1_min` to `hr_zone5_min`,
  all required whole numbers from 30 to 250, plus the usual `deleted`, `created` and `updated`. Rules: the owner and their coaches read it
  (coaches only while not deleted); only the owner creates and changes it; the owner cannot change; no deletes. The `base_updated` guard of
  [0011](0011-sync-conflict-guard.md) applies.
- **One row per athlete, with the athlete's user ID as its ID** (the create rule requires `id = owner = the signed-in user`). Two devices that
  save offline both create the same ID: the second gets "ID not unique", which the outbox already turns into an update, so the last save wins
  and no second row appears. For this the owner index is not unique: a unique owner index would answer with an owner error instead.
- **Zone boundaries**: each zone starts where the user says and ends one beat below the next one's start; zone 5 ends at the maximum. Starts must
  rise, and zone 5 must start at or below the maximum. A stored row that breaks these rules is skipped and the defaults apply.
- **Defaults**: until the athlete saves, the zones are those of 0015 for a maximum of **190 bpm** (95, 114, 133, 152, 171). The form is filled with
  them and says they are defaults. "Work out zones from maximum" fills the five starts from the maximum in the form with the same percentages.
- **Screen**: "Heart-rate zones" in Settings, above Coaches: the maximum, the five starts with each zone's end shown, "Save zones" and "Undo changes".
  What the user is typing is not overwritten by a sync that arrives meanwhile.
- **Code**: the zone logic moves from `units` to a new pure module `hr_zones` (defaults, zones, lookup, parsing, fields), with the section in
  `hr_zones_page`.

## Consequences

- The zones of any athlete are known on the athlete's and their coaches' devices, offline, so screens can show time or average in zone next.
  Nothing uses the zones yet.
- Further per-athlete settings can be added as fields on the same row.
- The rows are never soft-deleted, so the purge job ([0014](0014-purge-soft-deleted-rows.md)) does not handle this collection; a deleted user's
  row goes with the user (cascade).
- **Proposed**: 190 bpm is a middling default. Better would be the highest `max_hr` of the athlete's activities, or an age-based estimate;
  both make the defaults change under the athlete, so a fixed value was chosen until the owner decides.

## Addendum: lactate zones (2026-10-06)

[0035](0035-lactate-zone-settings.md) adds lactate zones to the same row. The row type moved from `hr_zones` to `athlete_settings`, and the
Settings section is now `zones_page`, titled "Training zones".
