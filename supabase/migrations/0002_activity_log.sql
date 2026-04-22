-- Migration: 0002_activity_log
-- Description: Immutable audit trail for all agent actions (GDP compliance)
-- Date: 2026-04-22

create table activity_log (
  id              uuid primary key default uuid_generate_v4(),
  timestamp       timestamptz not null default now(),
  actor           text not null check (actor in ('agent', 'human')),
  actor_email     text,
  action_type     text not null,              -- e.g. "rate_ingested", "rfq_matched", "quote_sent", "rate_requested"
  target_table    text,                       -- e.g. "rate_sources", "rates", "rfq_log"
  target_id       uuid,
  email_thread_id text,
  input_hash      text,                       -- SHA-256 of input for dedup/audit
  output_hash     text,                       -- SHA-256 of output
  model_used      text,                       -- e.g. "claude-sonnet-4-6"
  tokens_used     int,
  cost_usd        numeric(8,4),
  metadata        jsonb default '{}',
  created_at      timestamptz not null default now()
);

-- Activity log is append-only. No update or delete by application users.
-- RLS policies will enforce this at the Supabase level.

create index idx_activity_log_timestamp on activity_log(timestamp);
create index idx_activity_log_actor on activity_log(actor);
create index idx_activity_log_action on activity_log(action_type);
create index idx_activity_log_target on activity_log(target_table, target_id);
create index idx_activity_log_thread on activity_log(email_thread_id);
