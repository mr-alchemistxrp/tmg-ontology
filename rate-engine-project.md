# Transmodal Ontology — Layer 1: Rate Engine

**Project Specification & Roadmap**

| | |
|---|---|
| Document | TG-SPEC-001 |
| Version | 1.0 |
| Date | April 22, 2026 |
| Owner | Kanav Bhalla |
| Company | Transmodal Group, Etobicoke ON |

---

## 1. Project Concept

### What this is

The Rate Engine is the foundational layer of the Transmodal Ontology, the AI-native operating system being built for Transmodal Group. It is a persistent, email-native agent that ingests, organizes, and serves all rate information across the business — contract rates, spot rates, and agent rates, spanning ocean, air, and trucking modes.

### Why it exists

Today, rates at Transmodal live in fragmented forms: contract PDFs buried in email threads, agent quotes in Outlook, spot rates checked ad-hoc in GoFreight or DAT, and tribal knowledge of who has what rate for which lane. This creates three operational problems:

1. Rahul is a central bottleneck — rate knowledge is concentrated in his inbox and head.
2. RFQs take longer than they should, because finding the best applicable rate requires manual search across multiple sources.
3. Rate validity and provenance are often unclear at quote time, weakening negotiating position.

### What it does

At its core, a single email-native agent that:

- Ingests contract rates, spot rates, and agent rate replies automatically from dedicated email addresses.
- Maintains a consolidated rate library in Supabase with full provenance, validity, and versioning.
- Serves RFQs by replying to forwarded emails with best-match quotes, sell rate recommendations, and complete rate details.
- Proactively requests rates from origin agents when library gaps exist, and follows up until rates are received.
- Logs every interaction as an auditable email thread, supporting GDP and C-TPAT documentation requirements.

### Scope boundary

This document covers Layer 1 (Rate Engine) only. The Rate Engine feeds Layer 2 (Quote Generation), Layer 3 (Quote Follow-Up), Layer 4 (Shipment Data Engine), and Layer 5 (Financial Oversight), but those layers are out of scope here and will be specified separately.

---

## 2. Architecture Overview

### 2.1 System components

Six cooperating components form the Rate Engine:

| Component | Role | Technology |
|---|---|---|
| Email Gateway | Receives inbound emails, sends outbound replies and rate requests | Gmail API (Google Workspace) |
| Workflow Orchestrator | Routes emails to the right handler, schedules polling and follow-ups | n8n |
| Reasoning Layer | Parses unstructured rate data, matches RFQs, drafts replies | Claude API |
| Rate Library | Persistent structured storage of all rates with full provenance | Supabase (Postgres) |
| Browser Agent | Scrapes rate data from portals without APIs (DAT, carrier sites) | Claude Agent SDK + Playwright |
| Activity Log | Audit trail of every agent action, quote, and decision | Supabase (separate schema) |

### 2.2 Data flow

The system operates on three primary flows:

**Flow A — Rate Ingestion.** Inbound rate data (contracts, agent quotes, spot rate updates) arrives via email or scheduled polling. Claude parses the content, extracts structured fields, and writes to the rate library. A confirmation email is sent to the forwarding team member.

**Flow B — RFQ Matching.** A team member forwards an RFQ to `quote@transmodalgroup.com`. The agent parses the RFQ, queries the rate library with ranking logic, applies sell-rate markup, and replies with a formatted quote including provenance, validity, transit time, and ETD.

**Flow C — Proactive Rate Sourcing.** Scheduled jobs identify lanes where rates are stale, missing, or expiring. The agent sends rate request emails to mapped origin agents and follows up on a defined cadence until rates are received or escalation is triggered.

### 2.3 Deployment topology

All persistent services run on hosted infrastructure, not on individual team member machines. This ensures the agent is available 24/7 and independent of any one person's laptop being open.

- **Supabase** — managed Postgres, accessible via API. Handles both rate library and activity log.
- **n8n** — self-hosted or n8n Cloud. Handles all workflow triggers and scheduling.
- **Browser agent** — containerized Playwright + Claude Agent SDK, triggered on-demand by n8n.
- **Claude API** — called directly from n8n workflows and from the browser agent.

---

## 3. Data Model

The rate library is the heart of the system. The schema below is the v1 target. It is designed to accommodate the three rate types (CON, SPOT, AGENT) across three modes (ocean, air, trucking) without proliferating tables. Specialization is handled via optional fields and mode-specific JSON columns where needed.

### 3.1 Core tables

**`rate_sources`** — Master record for anything that provides rates: a carrier contract, a spot rate feed, an origin agent, or an internal cost model. Every rate in the library links to a source. Key fields: source type, carrier/agent name, contract number, amendment number, mode, scope, term start/end, governing terms (free time, detention, FSC methodology), document URL, status (active/superseded/expired), superseded_by reference.

**`rates`** — The individual rate line. One row per lane per equipment type per validity window. This is the table queried during RFQ matching. Key fields: source_id, mode, origin and destination, equipment type, commodity type, base rate, currency, FSC method (flat/percentage/indexed), FSC value and index source, surcharges (jsonb), transit days, route type, free time days, validity window, validity status, completeness score, raw source excerpt for audit, ingested_at, last_verified_at.

**`customers`** — Customer account master with quote formatting preferences and carrier restrictions. Links to Monday.com accounts board. Key fields: monday_account_id, legal name, quote_template_id, preferred carriers, excluded carriers, commodity restrictions, default markup percentage, credit terms.

**`quote_templates`** — Per-customer quote layouts. Used to render the final email body in the customer's preferred format. Key fields: template name, email subject template, email body template (with variable placeholders), fields to show, default flag.

**`rfq_log`** — Every RFQ received, how it was handled, and the outcome. This is the basis for the learning loop. Key fields: received_at, forwarded_by, customer_id, RFQ raw content, extracted lanes, quote sent timestamp, quote message ID, rates used, sell rate total, buy rate total, margin percentage, outcome (pending/won/lost/no_response/withdrawn), outcome_noted_at, actual_shipment_id (links to GoFreight if booked).

**`agent_requests`** — Outbound rate requests sent to origin agents. Tracks cadence, responses, and agent performance. Key fields: agent_source_id, requested_at, requested_by, lanes requested, reminders sent count, last reminder at, responded_at, response quality score, escalated_to, status (open/responded/escalated/abandoned).

### 3.2 Activity log

Separate from operational tables, the `activity_log` captures every action the agent takes for audit purposes. This is critical for GDP compliance. Key fields: timestamp, actor (agent or human), actor email, action type, target table, target id, email thread id, input hash, output hash, model used, tokens used, cost in USD.

### 3.3 Storage

Source documents are stored in Supabase Storage buckets, referenced by `document_url` in rate_sources. This preserves the original for audit and re-parsing if schema evolves.

- `contracts/` — carrier contract PDFs and amendments
- `agent-rates/` — agent rate emails and attachments
- `rfqs/` — inbound RFQ emails and attachments
- `quotes/` — outbound quote emails sent

---

## 4. Email Interface

The agent is email-native. All human-to-agent interaction happens through three dedicated inbound addresses, each mapped to a handler workflow in n8n.

### 4.1 Inbound addresses

| Address | Purpose | Handler |
|---|---|---|
| `rates@transmodalgroup.com` | Contract rates, agent rate replies, carrier surcharge updates | Rate Ingestion |
| `quote@transmodalgroup.com` | Team-forwarded RFQs requiring a quote reply | RFQ Matching |
| `agent@transmodalgroup.com` | General agent queries from team (status, lookups, admin) | Query handler |

### 4.2 Outbound identity

The agent signs outbound email as "TMG Rate Agent" with the sending address matching the inbound channel. For all v1 flows, outbound replies go only to internal team members. External customer-facing quotes are drafted and returned to the forwarding team member, who reviews and sends onward from their own inbox.

### 4.3 Reply threading

All agent replies use the Message-ID and In-Reply-To headers to thread correctly with the original email. This keeps each interaction as a searchable, attributable thread in the team's inbox and provides automatic audit trail.

### 4.4 Confirmation pattern

For rate ingestion, the agent always replies with a structured confirmation so the forwarder knows what was captured. Example after a contract forward:

```
Subject: Re: CMA CGM Amendment 10 - Rates Filed

Filed to rate library:
  Source: CMA CGM Contract 25-4942-9, Amendment 10
  Mode: Ocean
  Term: May 1, 2026 - Jul 31, 2026
  Lanes captured: 47
  Equipment types: 20GP, 40GP, 40HC, 40HC-RF
  Free time: 10 days (ISC -> USEC)
  FSC methodology: indexed to BAF quarterly

Source ID: rs_9f2c...
Full contract stored at: [link]

2 lanes flagged incomplete (missing surcharges):
  - NHAVA SHEVA -> HOUSTON, 20GP
  - MUNDRA -> SAVANNAH, 40HC-RF

Reply to this thread if corrections are needed.
```

---

## 5. Core Workflows

### 5.1 Contract rate ingestion

Triggered when an email arrives at `rates@` with an attachment or rate content in the body.

1. n8n detects inbound email, downloads attachments to staging.
2. Attachments classified: PDF, DOCX, XLSX, image, inline-body.
3. Document passed to Claude with contract-parsing system prompt.
4. Claude returns structured JSON: header metadata + lane list. Lane parsing is lazy for contracts over 20 lanes — header stored immediately, lanes parsed on first query and cached.
5. Completeness check runs: flags missing validity, FSC methodology, or equipment types.
6. If the contract supersedes a prior version (same carrier + contract number, higher amendment), the prior rate_source is marked status = superseded.
7. Confirmation email drafted and sent to forwarder.
8. Activity log entry written.

### 5.2 Agent rate ingestion

Triggered when an email arrives at `rates@` that is a reply from a known origin agent (sender matches an agent_name in rate_sources).

1. n8n detects reply, matches sender against known agents.
2. If matching an open agent_requests entry, the entry is updated and the response parsed.
3. If no open request but sender is a known agent, treated as unsolicited rate update.
4. Claude parses the email body for structured rate data. Agent emails are typically free-form prose or pasted tables.
5. Incomplete fields flagged (missing FSC, validity window, equipment type) and completeness_score computed.
6. If completeness_score below 0.6, agent reply drafted asking for missing fields, held for review.
7. If above 0.6, rates filed with completeness flag on incomplete rows.
8. Confirmation email sent.

### 5.3 RFQ matching and quote generation

Triggered when a team member forwards an RFQ to `quote@`.

1. n8n detects inbound RFQ.
2. Claude parses RFQ content to extract: customer name, lanes (origin/dest pairs), equipment, commodity, weight, ready date, validity needed.
3. Customer matched against customers table. If no match, flagged as prospect and default template used.
4. For each lane, Supabase query executed against rates table with ranking logic:
   - Exact lane match preferred over proximate match
   - Equipment exact match required (or explicitly substitutable)
   - Commodity restrictions enforced (pharma lanes require qualified carrier)
   - Validity window must include requested ETD
   - Source hierarchy: contract > recent agent quote > recent spot > stale sources
   - Customer carrier preferences applied (preferred boosted, excluded removed)
5. Top match(es) returned. If no match found, escalation reply drafted to forwarder.
6. Sell rate computed: base_rate + fsc + surcharges, then markup applied per customer default_markup_pct.
7. Quote rendered via customer's quote_template.
8. Reply email drafted and sent to forwarder. Customer is NOT cc'd directly in v1 — forwarder reviews and sends onward.
9. rfq_log entry created with outcome = pending.

### 5.4 Proactive rate sourcing

Scheduled jobs run on defined cadences:

| Job | Cadence | Action |
|---|---|---|
| Spot rate refresh (ocean) | Daily 06:00 ET | Poll configured spot feeds, update spot rates |
| Spot rate refresh (trucking) | Daily 06:00 ET | Query DAT API for key lanes, update spot rates |
| Contract expiry alert | Weekly Mondays | Flag contracts expiring within 30 days, email Kanav and Rahul |
| Agent staleness sweep | Weekly Mondays | Identify lanes where latest agent rate is >45 days old, queue rate requests |
| Rate request follow-up | Every 12 hours | Check open agent_requests: reminder at 24h, escalate at 72h |
| Churn detection | Weekly | Flag agents with no response in 40+ days |

### 5.5 Rate request outbound

When the staleness sweep or a failed RFQ match identifies a rate gap, the agent sends a rate request email to the mapped origin agent.

1. Gap identified (stale rate, missing lane, or RFQ with no match).
2. Agent mapping table consulted: which origin agent covers this lane?
3. Claude drafts rate request email in Transmodal's established tone (professional, firm, warm).
4. Email sent to agent. agent_requests entry created with status = open.
5. 24h later: if no response, reminder 1 sent.
6. 48h later: if no response, reminder 2 sent.
7. 72h later: if no response, escalation email sent to Kanav cc'ing the agent.
8. Response received: parsed and filed via the Agent Rate Ingestion workflow (5.2).

---

## 6. Parsing Logic

Parsing is the hardest part of the system. Rate data arrives in a wide variety of formats and the agent must be robust to all of them.

### 6.1 Input types

- **Structured PDF** — Carrier contracts with clear tables (CMA CGM, ONE, Hapag). Most reliable to parse.
- **Semi-structured PDF** — Agent rate sheets, often with merged cells, mixed units, footnotes.
- **XLSX** — Common for carrier contracts and agent rate sheets. Column layouts vary.
- **DOCX** — Less common but occurs for agent agreements and rate confirmations.
- **Email body prose** — Free-form agent replies like "Shanghai to LA $2,800 per 40HC valid through June, 14 days free". Hardest category.
- **Email body table** — Pasted HTML tables or plain-text tables in the email body.
- **Image / screenshot** — Forwarded screenshots of rate portals or carrier emails. Require vision model.
- **Reply with reference** — "Same as last month" or "per attached from March 15". Requires context lookup.

### 6.2 Parsing strategy

Each input type has a dedicated preprocessing step before Claude is called:

- **PDF.** Text extraction first. If low content (scanned), fall back to rasterization and pass page images to Claude vision. For multi-page contracts, first pass extracts header metadata only; lane-level parsing deferred.
- **XLSX.** Parsed to structured JSON: sheet name, headers, data rows. Merged cells unmerged. Passed to Claude with sheet context.
- **DOCX.** Text extraction via python-docx. Tables preserved as structured data.
- **Email body prose.** Passed to Claude with a prompt emphasizing: extract only what is explicitly stated, flag assumed values, return null for missing fields. Completeness score computed from field coverage.
- **Reply with reference.** Claude detects reference language and is given the agent's prior rate history from the library. Agent confirms or is asked to re-send if reference cannot be resolved.

### 6.3 Contract parsing: hybrid approach

For contracts specifically, the agent uses a hybrid parse strategy:

1. On ingestion, parse only the header metadata: carrier, contract number, amendment, term dates, scope, governing terms.
2. Store contract document in Supabase Storage with reference.
3. On first RFQ query touching this contract's scope, parse the relevant lanes fully and cache them in the rates table.
4. Background job slowly parses all lanes over time for analytics and expiry alerts.

This balances ingestion speed (header parse is fast) with RFQ responsiveness (lanes cached on first use), and avoids parsing hundreds of lanes that may never be quoted.

### 6.4 Quality controls

- Every parsed rate is stored with a `raw_source_excerpt` field containing the original text or cell reference. This allows audit and re-parsing.
- Completeness score flags rates missing critical fields.
- Duplicate detection: same source + lane + equipment + validity triggers a merge-or-update decision.
- Cross-check: when a new spot rate is significantly below the latest contract rate for the same lane (>30% delta), flag for human review.

---

## 7. Sell Rate and Markup Logic

### 7.1 Markup components

Sell rate = base rate + FSC + surcharges + markup.

Markup applied as:
1. Start with `customer.default_markup_pct` (set per account, typical range 8–15%).
2. Apply lane-type multiplier: premium on pharma and regulated commodities, standard on general cargo.
3. Apply service-level multiplier: higher on complex multi-leg routes and time-critical air.
4. Apply minimum margin floor: never quote below a defined absolute margin.

### 7.2 Human approval tiers

Per the three-tier agentic framework:

| Scenario | Agent Authority | Human Role |
|---|---|---|
| Standard RFQ, known customer, library match | Fully autonomous: drafts and sends reply | Review after |
| Unknown customer / new prospect | Proposes quote, flags for approval | Approves before send |
| Strategic account (APAR, Sun Pharma, top 10) | Proposes quote only | Always reviews and sends |
| Quote value above threshold (e.g. $50k) | Proposes quote only | Always reviews and sends |
| No library match found | Drafts escalation email | Leads response |
| Margin below floor | Proposes at floor, flags | Approves adjustment |

### 7.3 Override authority

The following team members have markup override authority, logged to activity_log when used:

- **Kanav** — full override on any rate
- **Rahul** — override up to defined delta from default
- **Viren, Aditya** — override on their assigned strategic accounts
- **Others** — no override, must escalate to Rahul

---

## 8. Build Sequence

The build is sequenced to deliver visible team value at each milestone rather than waiting for a big-bang launch. Each phase ends with a usable capability.

### Phase 1 — Foundation (Weeks 1–2)

**Goal:** schema live, contract forward-to-file working.

- Supabase project created, schema (rate_sources, rates, activity_log) deployed via migration
- n8n instance stood up (self-hosted on small VPS or n8n Cloud)
- Gmail OAuth configured for rates@, quote@, agent@
- Workflow 1: Contract ingestion (rates@ inbound → Claude parse → Supabase insert → confirmation reply)
- Admin review via Supabase table editor (sufficient for v1)

**Milestone:** forward a contract email, get structured confirmation within 2 minutes. Contracts from the last 6 months backfilled.

### Phase 2 — RFQ Matching (Weeks 3–4)

**Goal:** team can forward RFQs and get quote drafts back.

- Customers table populated from Monday.com accounts board export
- quote_templates seeded with default + APAR, Sun Pharma, and top 5 customer templates
- rfq_log table deployed
- Workflow 2: RFQ matching (quote@ inbound → parse → library query with ranking → markup → render → reply)
- Initial ranking logic simple: exact match + validity + source hierarchy

**Milestone:** Rahul forwards a real RFQ for APAR or a known account, gets a usable quote draft reply. Win rate tracked manually for first 2 weeks.

### Phase 3 — Agent Rate Handling (Weeks 5–6)

**Goal:** agent rates flow in and out without manual chasing.

- Agent mapping table populated (which agents cover which origin regions)
- Workflow 3: Agent rate ingestion (parse free-form replies, handle "same as last" references)
- Workflow 4: Outbound rate request and follow-up (with 24/48/72h cadence)
- Workflow 5: Staleness sweep (scheduled weekly)

**Milestone:** agent follow-ups happen without human intervention. Stale lanes auto-refreshed.

### Phase 4 — Spot Rates and Browser Agent (Weeks 7–8)

**Goal:** library stays fresh without any human action.

- GoFreight API integration for ocean spot rates
- DAT API integration for trucking spot rates (where available)
- Browser agent deployed for sources without APIs
- Workflow 6: Daily spot refresh

**Milestone:** library reflects current market without human touch for a full week.

### Phase 5 — Intelligence and Reporting (Weeks 9–10)

**Goal:** agent learns from outcomes; team sees performance.

- Outcome tracking: won/lost status captured on rfq_log
- Agent performance scorecard: response time, completeness, rate accuracy over time
- Lightweight reporting dashboard (Supabase views or simple Retool)
- Weekly summary email to Kanav with KPIs

**Milestone:** first full week of data-driven quoting decisions.

### What is NOT in v1

Explicitly deferred:

- Customer-direct email (agent sending to external addresses). v1 is internal only.
- Quote follow-up automation. That is Layer 3 and a separate project.
- Booking handoff to GoFreight. Deferred to Layer 4 (Shipment Data Engine).
- Financial reconciliation against quoted vs actual. Deferred to Layer 5.
- Customer-facing portal or dashboard. Not planned for v1.

---

## 9. Open Decisions

These items must be resolved before or during Phase 1. They are parked here as an active register.

| # | Decision | Options | Target Phase |
|---|---|---|---|
| D1 | Email provider | Google Workspace (Gmail API) vs Microsoft 365 (Graph API) | Pre-build |
| D2 | n8n hosting | Self-hosted VPS (Hetzner / DigitalOcean) vs n8n Cloud | Phase 1 |
| D3 | Default markup tiers | Per customer defaults to be confirmed with Rahul | Phase 2 |
| D4 | Strategic account list | Define customer list requiring always-human-review | Phase 2 |
| D5 | Margin floor | Absolute minimum margin per mode (ocean/air/trucking) | Phase 2 |
| D6 | Agent mapping | Which origin agents cover which regions/lanes | Phase 3 |
| D7 | Spot rate sources | GoFreight API scope; DAT API access status | Phase 4 |
| D8 | Escalation contacts | Who receives escalations for each rate request type | Phase 3 |
| D9 | Reporting cadence | Daily / weekly / monthly views for Kanav | Phase 5 |
| D10 | Model selection | Sonnet 4.6 for parsing vs Opus 4.7 for complex matching | Phase 1 |

---

## 10. Non-Functional Requirements

### Performance
- Contract ingestion confirmation: within 2 minutes of email receipt
- RFQ quote reply: within 5 minutes of email receipt for up to 10 lanes
- Library query: sub-second for any single-lane lookup

### Reliability
- System available 24/7 except for scheduled maintenance windows
- Email retry logic: 3 attempts with exponential backoff before routing to human
- Queue depth monitoring with alerts if backlog exceeds defined threshold

### Security
- Supabase row-level security enforced; production access limited to Kanav and Rahul
- API keys stored in n8n credential vault, never committed to repo
- Email attachments scanned for prompt injection patterns (white-on-white text, suspicious instruction blocks) before passing to Claude
- Activity log immutable: no UPDATE or DELETE permissions for any application user

### Compliance
- GDP alignment: audit trail covers all pharma-lane quotes with full provenance
- Data retention: rate library retained indefinitely; activity log retained minimum 7 years
- Personal data minimization: no customer PII stored beyond business contact details

### Observability
- All Claude API calls logged with model, tokens, cost
- Weekly cost report to Kanav
- Error rate dashboard: parse failures, match failures, send failures
- Agent response quality trending per origin agent

---

## 11. Repository Structure

Suggested layout for the local repository:

```
transmodal-rate-engine/
  README.md
  docs/
    TG-SPEC-001-rate-engine-spec.md   (this document)
    decision-log.md                    (ADRs for D1-D10)
    architecture-diagrams/
  supabase/
    migrations/
      0001_initial_schema.sql
      0002_activity_log.sql
    seed/
      customers.sql
      quote_templates.sql
    policies/
      rls_policies.sql
  n8n/
    workflows/
      01_contract_ingestion.json
      02_rfq_matching.json
      03_agent_rate_ingestion.json
      04_rate_request_outbound.json
      05_spot_rate_refresh.json
      06_weekly_reporting.json
    credentials/                       (gitignored)
  prompts/
    contract_parser.md
    rfq_parser.md
    rate_matcher.md
    quote_writer.md
    agent_request_writer.md
  browser-agent/
    Dockerfile
    agent.py
    scrapers/
  scripts/
    backfill_contracts.py
    validate_schema.py
    load_customer_templates.py
  tests/
    fixtures/
      sample_contracts/
      sample_rfqs/
      sample_agent_replies/
  .env.example
  .gitignore
```

### Environment variables

Defined in `.env.example` and populated locally (never committed):

```
SUPABASE_URL=
SUPABASE_SERVICE_KEY=
SUPABASE_ANON_KEY=
ANTHROPIC_API_KEY=
GOOGLE_OAUTH_CLIENT_ID=
GOOGLE_OAUTH_CLIENT_SECRET=
N8N_WEBHOOK_BASE_URL=
GOFREIGHT_API_KEY=
DAT_API_KEY=
ESCALATION_EMAIL_KANAV=
ESCALATION_EMAIL_RAHUL=
```

### First commit checklist

- Clone empty repo, add `.gitignore` (.env, node_modules, credentials, __pycache__)
- Copy this specification into `docs/`
- Create `docs/decision-log.md` and record D1–D10 as open
- Initialize Supabase project, link via supabase CLI
- Write migration 0001 covering rate_sources + rates
- Commit with message: "Initial spec and schema"

---

## 12. Glossary

| Term | Definition |
|---|---|
| CON | Contract rate. Negotiated with a carrier over a defined term. |
| SPOT | Spot rate. Current market rate, short validity, from feeds or portals. |
| AGENT | Rate provided by an origin or destination agent in response to a request. |
| FSC | Fuel Surcharge. Variable component of rate tied to fuel cost. |
| BAF | Bunker Adjustment Factor. Ocean carrier fuel surcharge mechanism. |
| THC | Terminal Handling Charge. Port-side surcharge. |
| Free time | Days allowed for container use at destination without detention charge. |
| RFQ | Request for Quote. Customer inquiry requiring a rate response. |
| Lane | A specific origin-destination pair with equipment type and commodity. |
| Ingestion | Process of bringing rate data into the library in structured form. |
| Provenance | Full traceable source of a rate: contract id, amendment, email thread. |
| Staleness | Condition where a rate's reliability has degraded due to time passed. |
| Completeness score | 0.0–1.0 rating of how many required fields a rate row has filled. |

---

## Document History

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | April 22, 2026 | Kanav Bhalla | Initial specification |
