--
-- Row Level Security
-- This file declares RLS policies for all tables in atomic_crm.
--

-- Enable RLS on all tables
alter table atomic_crm.companies enable row level security;
alter table atomic_crm.contacts enable row level security;
alter table atomic_crm.contact_notes enable row level security;
alter table atomic_crm.deals enable row level security;
alter table atomic_crm.deal_notes enable row level security;
alter table atomic_crm.sales enable row level security;
alter table atomic_crm.tags enable row level security;
alter table atomic_crm.tasks enable row level security;
alter table atomic_crm.configuration enable row level security;
alter table atomic_crm.favicons_excluded_domains enable row level security;

-- Companies
create policy "Enable read access for authenticated users" on atomic_crm.companies for select to authenticated using (true);
create policy "Enable insert for authenticated users only" on atomic_crm.companies for insert to authenticated with check (true);
create policy "Enable update for authenticated users only" on atomic_crm.companies for update to authenticated using (true) with check (true);
create policy "Company Delete Policy" on atomic_crm.companies for delete to authenticated using (true);

-- Contacts
create policy "Enable read access for authenticated users" on atomic_crm.contacts for select to authenticated using (true);
create policy "Enable insert for authenticated users only" on atomic_crm.contacts for insert to authenticated with check (true);
create policy "Enable update for authenticated users only" on atomic_crm.contacts for update to authenticated using (true) with check (true);
create policy "Contact Delete Policy" on atomic_crm.contacts for delete to authenticated using (true);

-- Contact Notes
create policy "Enable read access for authenticated users" on atomic_crm.contact_notes for select to authenticated using (true);
create policy "Enable insert for authenticated users only" on atomic_crm.contact_notes for insert to authenticated with check (true);
create policy "Contact Notes Update policy" on atomic_crm.contact_notes for update to authenticated using (true);
create policy "Contact Notes Delete Policy" on atomic_crm.contact_notes for delete to authenticated using (true);

-- Deals
create policy "Enable read access for authenticated users" on atomic_crm.deals for select to authenticated using (true);
create policy "Enable insert for authenticated users only" on atomic_crm.deals for insert to authenticated with check (true);
create policy "Enable update for authenticated users only" on atomic_crm.deals for update to authenticated using (true) with check (true);
create policy "Deals Delete Policy" on atomic_crm.deals for delete to authenticated using (true);

-- Deal Notes
create policy "Enable read access for authenticated users" on atomic_crm.deal_notes for select to authenticated using (true);
create policy "Enable insert for authenticated users only" on atomic_crm.deal_notes for insert to authenticated with check (true);
create policy "Deal Notes Update Policy" on atomic_crm.deal_notes for update to authenticated using (true);
create policy "Deal Notes Delete Policy" on atomic_crm.deal_notes for delete to authenticated using (true);

-- Sales
create policy "Enable read access for authenticated users" on atomic_crm.sales for select to authenticated using (true);

-- Tags
create policy "Enable read access for authenticated users" on atomic_crm.tags for select to authenticated using (true);
create policy "Enable insert for authenticated users only" on atomic_crm.tags for insert to authenticated with check (true);
create policy "Enable update for authenticated users only" on atomic_crm.tags for update to authenticated using (true);
create policy "Enable delete for authenticated users only" on atomic_crm.tags for delete to authenticated using (true);

-- Tasks
create policy "Enable read access for authenticated users" on atomic_crm.tasks for select to authenticated using (true);
create policy "Enable insert for authenticated users only" on atomic_crm.tasks for insert to authenticated with check (true);
create policy "Task Update Policy" on atomic_crm.tasks for update to authenticated using (true);
create policy "Task Delete Policy" on atomic_crm.tasks for delete to authenticated using (true);

-- Configuration (admin-only for writes)
-- RLS on the configuration table is intentionally unchanged: anon has NO access
-- to the full `config` JSONB. Unauthenticated branding is served exclusively by
-- the `configuration_branding` view (see 03_views.sql / 06_grants.sql), which
-- projects only title/darkModeLogo/lightModeLogo and is exposed to anon via
-- `security_invoker = off` + explicit grants -- the same model as `init_state`,
-- which likewise carries no view-level RLS policy.
create policy "Enable read for authenticated" on atomic_crm.configuration for select to authenticated using (true);
create policy "Enable insert for admins" on atomic_crm.configuration for insert to authenticated with check (public.is_admin());
create policy "Enable update for admins" on atomic_crm.configuration for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- Favicons excluded domains
create policy "Enable access for authenticated users only" on atomic_crm.favicons_excluded_domains to authenticated using (true) with check (true);
