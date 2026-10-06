# 0035. Lactate zones as an explicit setting

- Status: Accepted (storage and screen); Proposed (default values)
- Date: 2026-10-06
- Deciders: owner asked for configurable lactate zones and chose zones by blood lactate in mmol/L; agent (design)

## Context

[0034](0034-heart-rate-zone-settings.md) made the heart-rate zones a setting with defaults. The owner asked for lactate zones to be configurable
as well. "Lactate zones" can mean zones by measured blood lactate (mmol/L), or heart-rate zones worked out from the lactate threshold heart rate.
The owner chose the first: five zones, each starting at a blood-lactate value, for athletes who measure lactate.

## Options considered

1. **Same row as the heart-rate zones (`athlete_settings`)** — one record to sync and one place for per-athlete settings, which 0034 foresaw.
2. **A separate collection** — another collection to pull, sweep and guard, for five numbers.

For the values: floats in the UI and the domain would need rounding care in every comparison; whole tenths of mmol/L do not.

## Decision

- **Fields** `lactate_zone1_min` to `lactate_zone5_min` on `athlete_settings` (migration `1760000500_athlete_settings_lactate_zones.js`), numbers from
  0.1 to 30.0 mmol/L. They are **not required**: rows saved before, and app versions still cached on devices that send only heart-rate fields, keep
  working. A client that finds them empty (0) or unusable uses the lactate defaults, and keeps the heart-rate zones.
- **Values**: one decimal at most, typed with a point or a comma. In the app they are whole tenths (`lactate_zones` module); the stored value is
  mmol/L. Each zone ends one tenth below the next one's start; zone 5 has no upper end. Starts must rise.
- **Defaults (Proposed)**: 1.0, 1.5, 2.5, 4.0 and 6.0 mmol/L, close to the Olympiatoppen intensity zones. 4.0 is the classic "anaerobic threshold";
  real thresholds vary a lot between athletes, which is why the zones are configurable.
- **Screen**: the Settings section becomes "Training zones" with a "Heart rate" and a "Blood lactate" part and one "Save zones". Saving writes all
  values, so a row created from the screen is always complete.
- **Code**: the row (both kinds of zones, `row_of`, `current`, `fields`) moves to `athlete_settings`; the section is `zones_page` (was `hr_zones_page`).

## Consequences

- Nothing uses lactate zones yet: activities carry no lactate values. Entering measured lactate (for example per lap or test step) is a later decision.
- Heart-rate and lactate zones are independent: the app does not derive one from the other.
