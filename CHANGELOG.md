# Changelog

Each push to `main` bumps the patch version (`1.0.N`) and gets a matching `vX.Y.Z` tag.

## 1.0.2 (2026-09-25)

- `list`, `generate` and `setup` look up account roles in parallel (up to 16 at once), which cuts `list` from about 30 seconds to about 5 for 42 accounts.
- Roles are listed in name order within each account, so the output is the same on every run.

## 1.0.1 (2026-09-22)

- Documented custom profile aliases and how to convert a SAML tool's role map.

## 1.0.0 (2026-09-21)

- First release: `setup`, `login`, `list`, `generate` and `verify`, with docs for migrating from SAML tools and using profiles with other tools.
