/// <reference path="../pb_data/types.d.ts" />
// Pace zones on athlete_settings: the threshold pace and where each of the five zones starts, in seconds per km
// (zone 1 is the slowest). Not required, so rows saved before and app versions that do not know them yet keep
// working; a client that finds them empty (0) uses the defaults. See docs/adr/0036-pace-zone-settings.md.
const FIELDS = ["threshold_pace_s", ...[1, 2, 3, 4, 5].map((n) => `pace_zone${n}_start_s`)]

migrate(
  (app) => {
    const settings = app.findCollectionByNameOrId("athlete_settings")
    for (const name of FIELDS) {
      // 2:00 to 15:00 per km
      settings.fields.add(new NumberField({ name, min: 120, max: 900, onlyInt: true }))
    }
    app.save(settings)
  },
  (app) => {
    const settings = app.findCollectionByNameOrId("athlete_settings")
    for (const name of FIELDS) settings.fields.removeByName(name)
    app.save(settings)
  },
)
