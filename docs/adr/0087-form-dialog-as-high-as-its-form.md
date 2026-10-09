# 0087. Form dialogs as high as their form

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (asked to avoid scrolling where it is not needed); agent (the details below)

## Context

[ADR 0086](0086-form-dialog-height-and-date-time-inputs.md) capped a form dialog at 40rem from 600px. The plan form
is about 41rem high there (headline, fields, Cancel and Save), so it scrolled by a few pixels on any screen, however
tall.

## Decision

This replaces ADR 0086's height: from 600px a form dialog is as high as its form, and at most the screen's height
less 4rem. It scrolls only when the screen is too short for the form. ADR 0086's date and time inputs stand.

## Consequences

On most laptop and desktop screens no form dialog scrolls; a short form gives a short dialog.
