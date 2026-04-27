# TMG Rate Engine — Status

**Last updated:** 2026-04-27
**Current phase:** Phase 1 — Foundation (nearly complete)
**Phase status:** Core pipeline working, hardening needed

## Phase 1 Progress

### Done
- [x] Supabase project created (TMG Ontology)
- [x] Schema deployed: `rate_sources`, `rates`, `activity_log`
- [x] RLS policies applied (+ service_role access granted)
- [x] Storage buckets created: contracts, agent-rates, rfqs, quotes
- [x] n8n installed (Cloud instance at scalelab.app.n8n.cloud)
- [x] Microsoft Outlook credential connected (pricing@transmodalgroup.com)
- [x] OpenRouter credential connected (Gemini 2.5 Flash)
- [x] Contract ingestion workflow built and working end-to-end
- [x] Email trigger picks up emails from pricing@ automatically
- [x] Attachment download + inline image filtering
- [x] PDF parsing via Gemini 2.5 Flash on OpenRouter (file type)
- [x] JSON response parsing with multi-strategy error handling
- [x] Rate source inserted into Supabase
- [x] Rate lanes inserted into Supabase (13 lanes from OOCL PE254110 AM67)
- [x] Confirmation reply sent back in email thread
- [x] Data sanitization (fsc_method, route_type, country codes)
- [x] Contract parser prompt written (prompts/contract_parser.md)

### Remaining (Phase 1 hardening)
- [ ] Edge case testing (see docs/edge-case-tests.md)
- [ ] Non-contract email filter (prevent junk data)
- [ ] Duplicate contract detection
- [ ] Amendment superseding logic (mark prior amendments as superseded)
- [ ] Activity log node connection (minor — same Supabase header fix)
- [ ] Backfill contracts from last 6 months
- [ ] Deploy n8n to Mac Mini for production

## Phase 2 — RFQ Matching (next)
- [ ] Customers table populated
- [ ] Quote templates seeded
- [ ] rfq_log table deployed
- [ ] RFQ matching workflow (query rates by lane, apply markup, reply)
- [ ] Rate lookup capability (email-based or dashboard)

## Key Decisions Made
- **D1:** Email provider → Microsoft 365 (Outlook), not Gmail
- **D2:** n8n hosting → n8n Cloud for dev, Mac Mini for production later
- **D10:** Model selection → Gemini 2.5 Flash via OpenRouter for contract parsing
- Using `pricing@transmodalgroup.com` as single inbox for Phase 1
- Using OpenRouter `file` content type for PDF uploads (not Anthropic native)
- response_format: json_object for reliable JSON output

## Architecture
| Component | Status | Technology |
|-----------|--------|------------|
| Email Gateway | **Working** | Microsoft Outlook (Graph API) |
| Workflow Orchestrator | **Working** | n8n Cloud |
| Reasoning Layer | **Working** | Gemini 2.5 Flash via OpenRouter |
| Rate Library | **Working** | Supabase (Postgres) — 13 lanes ingested |
| Activity Log | Schema ready | Supabase |
| Confirmation Reply | **Working** | Outlook reply in thread |
