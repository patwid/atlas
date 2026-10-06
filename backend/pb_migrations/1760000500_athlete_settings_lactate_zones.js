/// <reference path="../pb_data/types.d.ts" />
// Lactate zones on athlete_settings: where each of the five zones starts, in mmol/L of blood lactate.
// Not required, so rows saved before and app versions that do not know them yet keep working; a client that
// finds them empty (0) uses the defaults. See docs/adr/0035-lactate-zone-settings.md.
const FIELDS = [1, 2, 3, 4, 5].map((n) => `lactate_zone${n}_min`)

migrate(
  (app) => {
    const settings = app.findCollectionByNameOrId("athlete_settings")
    for (const name of FIELDS) {
      settings.fields.add(new NumberField({ name, min: 0.1, max: 30 }))
    }
    app.save(settings)
  },
  (app) => {
    const settings = app.findCollectionByNameOrId("athlete_settings")
    for (const name of FIELDS) settings.fields.removeByName(name)
    app.save(settings)
  },
)
