-- =============================================================================
-- RLS Policies
-- Service role key (used by n8n) bypasses RLS automatically.
-- These policies lock down the Data API for anon/authenticated access.
-- =============================================================================

-- rate_sources: no public access
create policy "No anon access to rate_sources"
  on rate_sources for all
  to anon
  using (false);

create policy "No authenticated access to rate_sources"
  on rate_sources for all
  to authenticated
  using (false);

-- rates: no public access
create policy "No anon access to rates"
  on rates for all
  to anon
  using (false);

create policy "No authenticated access to rates"
  on rates for all
  to authenticated
  using (false);

-- activity_log: append-only, no public access
create policy "No anon access to activity_log"
  on activity_log for all
  to anon
  using (false);

create policy "No authenticated access to activity_log"
  on activity_log for all
  to authenticated
  using (false);

-- Revoke UPDATE and DELETE on activity_log from all non-superuser roles
revoke update, delete on activity_log from anon, authenticated;
