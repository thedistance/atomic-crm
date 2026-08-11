--
-- Views
-- This file declares all views in the public schema.
-- Pass-through views expose atomic_crm tables under the same public names
-- used by React Admin and edge functions. Derived views retarget sources.
--

-- Pass-through (auto-updatable) views
create or replace view public.companies with (security_invoker = on) as
select * from atomic_crm.companies;

create or replace view public.contacts with (security_invoker = on) as
select * from atomic_crm.contacts;

create or replace view public.contact_notes with (security_invoker = on) as
select * from atomic_crm.contact_notes;

create or replace view public.deals with (security_invoker = on) as
select * from atomic_crm.deals;

create or replace view public.deal_notes with (security_invoker = on) as
select * from atomic_crm.deal_notes;

create or replace view public.sales with (security_invoker = on) as
select * from atomic_crm.sales;

create or replace view public.tags with (security_invoker = on) as
select * from atomic_crm.tags;

create or replace view public.tasks with (security_invoker = on) as
select * from atomic_crm.tasks;

create or replace view public.configuration with (security_invoker = on) as
select * from atomic_crm.configuration;

create or replace view public.favicons_excluded_domains with (security_invoker = on) as
select * from atomic_crm.favicons_excluded_domains;

-- Derived views
create or replace view public.activity_log with (security_invoker = on) as
select
    ('company.' || c.id || '.created') as id,
    'company.created' as type,
    c.created_at as date,
    c.id as company_id,
    c.sales_id,
    to_json(c.*) as company,
    null::json as contact,
    null::json as deal,
    null::json as contact_note,
    null::json as deal_note
from atomic_crm.companies c
union all
select
    ('contact.' || co.id || '.created') as id,
    'contact.created' as type,
    co.first_seen as date,
    co.company_id,
    co.sales_id,
    null::json as company,
    to_json(co.*) as contact,
    null::json as deal,
    null::json as contact_note,
    null::json as deal_note
from atomic_crm.contacts co
union all
select
    ('contactNote.' || cn.id || '.created') as id,
    'contactNote.created' as type,
    cn.date,
    co.company_id,
    cn.sales_id,
    null::json as company,
    null::json as contact,
    null::json as deal,
    to_json(cn.*) as contact_note,
    null::json as deal_note
from atomic_crm.contact_notes cn
    left join atomic_crm.contacts co on co.id = cn.contact_id
union all
select
    ('deal.' || d.id || '.created') as id,
    'deal.created' as type,
    d.created_at as date,
    d.company_id,
    d.sales_id,
    null::json as company,
    null::json as contact,
    to_json(d.*) as deal,
    null::json as contact_note,
    null::json as deal_note
from atomic_crm.deals d
union all
select
    ('dealNote.' || dn.id || '.created') as id,
    'dealNote.created' as type,
    dn.date,
    d.company_id,
    dn.sales_id,
    null::json as company,
    null::json as contact,
    null::json as deal,
    null::json as contact_note,
    to_json(dn.*) as deal_note
from atomic_crm.deal_notes dn
    left join atomic_crm.deals d on d.id = dn.deal_id;

create or replace view public.companies_summary with (security_invoker = on) as
select
    c.id,
    c.created_at,
    c.name,
    c.sector,
    c.size,
    c.linkedin_url,
    c.website,
    c.phone_number,
    c.address,
    c.zipcode,
    c.city,
    c.state_abbr,
    c.sales_id,
    c.context_links,
    c.country,
    c.description,
    c.revenue,
    c.tax_identifier,
    c.logo,
    count(distinct d.id) as nb_deals,
    count(distinct co.id) as nb_contacts
from atomic_crm.companies c
    left join atomic_crm.deals d on c.id = d.company_id
    left join atomic_crm.contacts co on c.id = co.company_id
group by c.id;

create or replace view public.contacts_summary with (security_invoker = on) as
select
    co.id,
    co.first_name,
    co.last_name,
    co.gender,
    co.title,
    co.background,
    co.avatar,
    co.first_seen,
    co.last_seen,
    co.has_newsletter,
    co.status,
    co.tags,
    co.company_id,
    co.sales_id,
    co.linkedin_url,
    co.email_jsonb,
    co.phone_jsonb,
    (jsonb_path_query_array(co.email_jsonb, '$[*]."email"'))::text as email_fts,
    (jsonb_path_query_array(co.phone_jsonb, '$[*]."number"'))::text as phone_fts,
    c.name as company_name,
    count(distinct t.id) filter (where t.done_date is null) as nb_tasks
from atomic_crm.contacts co
    left join atomic_crm.tasks t on co.id = t.contact_id
    left join atomic_crm.companies c on co.company_id = c.id
group by co.id, c.name;

create or replace view public.init_state with (security_invoker = off) as
select count(sub.id) as is_initialized
from (
    select sales.id from atomic_crm.sales limit 1
) sub;

-- Anon-readable projection of the singleton configuration row exposing only the
-- branding fields needed by unauthenticated pages (login, sign-up,
-- forgot-password). `security_invoker = off` lets the view owner read the
-- underlying row while callers stay `anon`; the column projection is the
-- security boundary (the full `config` JSONB is never exposed). Same model as
-- `init_state`.
create or replace view public.configuration_branding with (security_invoker = off) as
select
    c.id,
    c.config ->> 'title' as title,
    c.config ->> 'darkModeLogo' as "darkModeLogo",
    c.config ->> 'lightModeLogo' as "lightModeLogo"
from atomic_crm.configuration c
where c.id = 1;
