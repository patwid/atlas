# 0036. Pace zones as an explicit setting

- Status: Accepted
- Date: 2026-10-06
- Deciders: owner asked for configurable pace zones and chose threshold pace as the reference with a 5:00 /km default; agent (design)

## Context

[0034](0034-heart-rate-zone-settings.md) and [0035](0035-lactate-zone-settings.md) made heart-rate and lactate zones settings with defaults. The owner
asked for pace zones as well. Runners often train by pace rather than heart rate, and Atlas already shows pace for activities (`units`, 0015).

Pace differs from the other two in one way: lower numbers are faster. Zone 1 is the slowest pace range and zone 5 the fastest.

## Options considered

The reference pace that fills the zones (the owner chose):

1. **Threshold pace** (about the pace one can hold for an hour) — the usual reference for pace zones (Friel and others). Zones start at
   140, 129, 114, 106 and 99 percent of its time per km: Friel's seven run-pace zones folded into five.
2. **10 km race pace** — easier to know for many runners, but less standard.
3. **Fixed values only** — no reference, no button.

## Decision

We use option 1, stored like the other zones on `athlete_settings` (one row per athlete, 0034).

- **Fields** (migration `1760000600_athlete_settings_pace_zones.js`): `threshold_pace_s` and `pace_zone1_start_s` to `pace_zone5_start_s`,
  whole seconds per km from 120 (2:00 /km) to 900 (15:00 /km). **Not required**, for the same reasons as the lactate fields: rows saved before and
  app versions still cached on devices keep working. A client that finds them empty (0) or unusable uses the pace defaults and keeps the other zones.
- **Zones**: each zone starts at the slowest pace that counts for it. A zone ends one second per km slower than the next one's start; zone 5 is
  open towards faster. Each zone must start faster than the one before. A pace slower than zone 1's start is in no zone.
- **Input**: `m:ss` (seconds with two digits) or whole minutes (`5` for 5:00), as the activity form does for times.
- **Defaults**: a threshold pace of **5:00 /km**, giving zones from **7:00, 6:27, 5:42, 5:18 and 4:57 /km** (percentages of the time per km, rounded
  down to whole seconds). "Work out zones from threshold pace" fills the starts from the threshold pace in the form. The threshold pace is stored too,
  so the form shows what the zones were worked out from.
- **Screen**: a third part, "Pace", in "Training zones" in Settings, under the same "Save zones".
- **Code**: a pure `pace_zones` module. `athlete_settings` now passes all zones as one `Zones` value (`hr`, `lactate`, `pace`) instead of a tuple.

## Consequences

- Nothing uses pace zones yet; activities have distance and time, so time in pace zone (from laps) or a zone for an activity's average pace
  can come next.
- Paces are per km only, like the rest of Atlas. Miles would need a unit setting for the whole app.
- Pace on hills and trails says little about effort; heart-rate zones remain the better guide there.
