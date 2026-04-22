# Transmodal Rate Engine

Layer 1 of the Transmodal Ontology — the AI-native operating system for Transmodal Group.

The Rate Engine is a persistent, email-native agent that ingests, organizes, and serves all rate information across the business — contract rates, spot rates, and agent rates, spanning ocean, air, and trucking modes.

## Architecture

| Component | Role | Technology |
|---|---|---|
| Email Gateway | Receives/sends emails | Gmail API (Google Workspace) |
| Workflow Orchestrator | Routes emails, schedules jobs | n8n |
| Reasoning Layer | Parses rates, matches RFQs, drafts replies | Claude API |
| Rate Library | Structured rate storage with provenance | Supabase (Postgres) |
| Browser Agent | Scrapes portals without APIs | Claude Agent SDK + Playwright |
| Activity Log | Audit trail | Supabase |

## Project Structure

```
docs/               — Specifications, decision log, architecture diagrams
supabase/           — Migrations, seed data, RLS policies
n8n/                — Workflow JSON exports
prompts/            — Claude system prompts for each workflow
browser-agent/      — Playwright-based scraper agent
scripts/            — Backfill, validation, and setup scripts
tests/              — Test fixtures (sample contracts, RFQs, agent replies)
```

## Setup

1. Copy `.env.example` to `.env` and populate credentials
2. Initialize Supabase project and run migrations
3. Configure n8n instance and import workflows
4. Set up Gmail OAuth for `rates@`, `quote@`, `agent@`

See `docs/TG-SPEC-001-rate-engine-spec.md` for the full specification.

## Build Phases

1. **Foundation** — Schema + contract ingestion (Weeks 1-2)
2. **RFQ Matching** — Quote drafting from library (Weeks 3-4)
3. **Agent Rates** — Inbound/outbound agent rate handling (Weeks 5-6)
4. **Spot Rates** — Browser agent + API integrations (Weeks 7-8)
5. **Intelligence** — Outcome tracking + reporting (Weeks 9-10)
