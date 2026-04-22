-- Migration: 0001_initial_schema
-- Description: Core rate library tables — rate_sources and rates
-- Date: 2026-04-22

-- Enable UUID generation
create extension if not exists "uuid-ossp";

-- =============================================================================
-- rate_sources: Master record for anything that provides rates
-- =============================================================================
create table rate_sources (
  id            uuid primary key default uuid_generate_v4(),
  source_type   text not null check (source_type in ('CON', 'SPOT', 'AGENT')),
  carrier_name  text,
  agent_name    text,
  contract_number text,
  amendment_number int,
  mode          text not null check (mode in ('ocean', 'air', 'trucking')),
  scope         text,                        -- e.g. "ISC -> USEC", "China -> US West Coast"
  term_start    date,
  term_end      date,
  free_time_days int,
  detention_terms text,
  fsc_methodology text,                      -- e.g. "indexed to BAF quarterly", "flat $150"
  document_url  text,                        -- Supabase Storage path
  status        text not null default 'active' check (status in ('active', 'superseded', 'expired')),
  superseded_by uuid references rate_sources(id),
  notes         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index idx_rate_sources_status on rate_sources(status);
create index idx_rate_sources_mode on rate_sources(mode);
create index idx_rate_sources_carrier on rate_sources(carrier_name);
create index idx_rate_sources_agent on rate_sources(agent_name);
create index idx_rate_sources_contract on rate_sources(contract_number, amendment_number);

-- =============================================================================
-- rates: Individual rate lines — one per lane/equipment/validity window
-- =============================================================================
create table rates (
  id                uuid primary key default uuid_generate_v4(),
  source_id         uuid not null references rate_sources(id),
  mode              text not null check (mode in ('ocean', 'air', 'trucking')),

  -- Origin / Destination
  origin_port       text,                    -- port code or city
  origin_country    text,
  origin_region     text,                    -- e.g. "ISC", "China", "US Midwest"
  destination_port  text,
  destination_country text,
  destination_region text,

  -- Equipment & commodity
  equipment_type    text,                    -- e.g. "20GP", "40HC", "40HC-RF", "53FT"
  commodity_type    text,                    -- e.g. "FAK", "pharma", "hazmat"

  -- Pricing
  base_rate         numeric(12,2) not null,
  currency          text not null default 'USD',
  fsc_method        text check (fsc_method in ('flat', 'percentage', 'indexed')),
  fsc_value         numeric(10,2),           -- flat amount or percentage
  fsc_index_source  text,                    -- e.g. "CMA BAF Q2 2026"
  surcharges        jsonb default '{}',      -- {"THC": 250, "ISPS": 15, "DOC": 75}

  -- Service
  transit_days      int,
  route_type        text,                    -- "direct", "transshipment", "intermodal"
  free_time_days    int,

  -- Validity
  valid_from        date,
  valid_to          date,
  validity_status   text not null default 'current' check (validity_status in ('current', 'expiring', 'expired')),

  -- Quality
  completeness_score numeric(3,2) default 0.0 check (completeness_score between 0.0 and 1.0),
  raw_source_excerpt text,                   -- original text for audit

  -- Timestamps
  ingested_at       timestamptz not null default now(),
  last_verified_at  timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index idx_rates_source on rates(source_id);
create index idx_rates_mode on rates(mode);
create index idx_rates_lane on rates(origin_port, destination_port);
create index idx_rates_origin_region on rates(origin_region);
create index idx_rates_dest_region on rates(destination_region);
create index idx_rates_equipment on rates(equipment_type);
create index idx_rates_validity on rates(valid_from, valid_to);
create index idx_rates_validity_status on rates(validity_status);

-- =============================================================================
-- Updated_at trigger
-- =============================================================================
create or replace function update_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger trg_rate_sources_updated_at
  before update on rate_sources
  for each row execute function update_updated_at();

create trigger trg_rates_updated_at
  before update on rates
  for each row execute function update_updated_at();
