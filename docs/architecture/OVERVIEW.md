# FarmFlow architecture and process flow

## Full V1 runtime

```text
Flutter UI (browser / portable Windows package)
         |
         v
Supabase Auth + PostgreSQL APIs/RPCs
         |
         +-- users / roles and RLS
         +-- batches + animals + configured tag formatting
         +-- induction + corrections
         +-- shipments + mortality + costs
         +-- dashboard / live inventory / reporting
```

### Business lifecycle

```text
Purchase batch and animal intake
    -> tag validation / canonical tagging
    -> induction
    -> live inventory
    -> shipment OR mortality
    -> reports / operational summaries
```

Database constraints and appropriate transactional RPCs protect the full application's persistent business rules. UI-side validation provides immediate feedback but does not replace database integrity. Consult `backend/FarmFlow_V1/BACKEND_AUTHORITATIVE_MAP.md` for the actual object inventory; the authoritative SQL source was consolidated September 2026.

## Public showcase runtime

```text
GitHub-hosted compiled Flutter Web files -> static hosting (Vercel planned)
                 |
                 v
         fictional packaged data
                 |
                 v
         read-only presentation
```

No backend API, authentication service, payment API, production farm database, or persistent transaction writes are exposed by the showcase. UI controls and data-layer write attempts are restricted. This is a portfolio display, not a multi-user production simulation.

## Deployment boundary

The Windows V1 launcher serves compiled web assets via a local loopback HTTP server; those assets can communicate with the configured Supabase project over the internet. The public showcase instead runs as a static website with its own demo data and no production Supabase connection.
