# ADR 003 — Portable Windows browser launcher

**Status:** Accepted for full FarmFlow V1; recorded retrospectively (September 2026).

## Context
A Windows operator should be able to copy a self-contained application folder to a Windows 10/11 computer and open FarmFlow without installing Flutter, Node.js or Python. Browser-based UI assets still need an HTTP origin; full V1 connects to Supabase over the internet.

## Decision
Bundle a compiled Flutter Web `app/` directory alongside a .NET Framework launcher EXE and config. The launcher serves assets on a fixed loopback port, opens the browser, exposes a system-tray reopen/exit menu, and reuses the running local instance on repeated clicks.

## Alternatives considered
Requiring developers' runtime tooling or a command-line static server would increase installation burden. Shipping only `index.html` under `file://` would not provide a supported app origin. A native desktop rewrite would create a second UI implementation.

## Consequences
The entire distribution folder must travel together; the EXE alone is insufficient. The launcher depends on Windows and .NET Framework 4.x, while full farm operations still require network access to Supabase. Launcher upgrades need Windows compilation and test on the target environment; closing the browser does not automatically exit the tray process.

## Evidence and limitations
Repeated desktop clicks were checked against an unchanged launcher process ID on the original computer. This was not a cross-machine compatibility certification. The public static showcase does not publish this Windows package.
