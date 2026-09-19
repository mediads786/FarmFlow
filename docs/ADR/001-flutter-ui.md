# ADR 001 — Flutter Web application UI

**Status:** Accepted; recorded retrospectively (September 2026).

## Context
FarmFlow needs consistent operational screens for intake, induction, inventory, animal out, reporting and farm administration. It is used in a browser and distributed as a portable Windows browser-hosted package. A separate portfolio showcase must retain the visual design without depending on production data.

## Decision
Use Flutter Web for the application interface. Preserve the working screens when creating the showcase, rather than reimplementing them in a second UI framework. Deliver browser builds as static web assets.

## Alternatives considered
A separate React/JavaScript showcase could offer more flexibility for documentation and static hosting, but would require duplicating presentation and could drift from the application being demonstrated. A completely native desktop implementation would add an independent client with different deployment requirements. Neither was adopted for V1.

## Consequences
The same UI technology supports the browser and the Windows package. A Flutter Web build is required when source or asset files change. Compiled artifacts are suitable for static hosting; they do not replace production source or backend services. Showcase source is maintained separately to prevent accidental production changes.

## Evidence and limitations
The standalone showcase passed its Flutter tests and was opened in Chrome before publication. That does not establish equivalent behavior for every production workflow.
