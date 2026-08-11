-- Move CRM tables from public to atomic_crm; expose public pass-through views.
-- Prefer ALTER TABLE … SET SCHEMA to preserve data, RLS policies, and triggers.

-- Drop dependent public views before moving tables
drop view if exists public.activity_log;
drop view if exists public.companies_summary;
drop view if exists public.contacts_summary;
drop view if exists public.init_state;
drop view if exists public.configuration_branding;

create schema if not exists atomic_crm;

-- Move tables (owned sequences / indexes / policies / triggers move with them)
alter table public.companies set schema atomic_crm;
alter table public.contacts set schema atomic_crm;
alter table public.contact_notes set schema atomic_crm;
alter table public.deals set schema atomic_crm;
alter table public.deal_notes set schema atomic_crm;
alter table public.sales set schema atomic_crm;
alter table public.tags set schema atomic_crm;
alter table public.tasks set schema atomic_crm;
alter table public.configuration set schema atomic_crm;
alter table public.favicons_excluded_domains set schema atomic_crm;

-- Drop unused empty private schema leftover from Atomic CRM declarative schemas
drop schema if exists private;

-- Schema grants for invoker views / service role (not exposed via PostgREST api.schemas)
grant usage on schema atomic_crm to postgres;
grant usage on schema atomic_crm to authenticated;
grant usage on schema atomic_crm to service_role;

-- Table privileges on atomic_crm (needed for security_invoker views)
grant all on table atomic_crm.companies to authenticated, service_role;
grant all on table atomic_crm.contacts to authenticated, service_role;
grant all on table atomic_crm.contact_notes to authenticated, service_role;
grant all on table atomic_crm.deals to authenticated, service_role;
grant all on table atomic_crm.deal_notes to authenticated, service_role;
grant all on table atomic_crm.sales to authenticated, service_role;
grant all on table atomic_crm.tags to authenticated, service_role;
grant all on table atomic_crm.tasks to authenticated, service_role;
grant all on table atomic_crm.configuration to authenticated, service_role;
grant all on table atomic_crm.favicons_excluded_domains to authenticated, service_role;

-- Revoke anon from base tables (public access is via views only)
revoke all on table atomic_crm.companies from anon;
revoke all on table atomic_crm.contacts from anon;
revoke all on table atomic_crm.contact_notes from anon;
revoke all on table atomic_crm.deals from anon;
revoke all on table atomic_crm.deal_notes from anon;
revoke all on table atomic_crm.sales from anon;
revoke all on table atomic_crm.tags from anon;
revoke all on table atomic_crm.tasks from anon;
revoke all on table atomic_crm.configuration from anon;
revoke all on table atomic_crm.favicons_excluded_domains from anon;

-- Sequence grants
grant all on all sequences in schema atomic_crm to authenticated, service_role;

alter default privileges for role postgres in schema atomic_crm grant all on sequences to authenticated, service_role;
alter default privileges for role postgres in schema atomic_crm grant all on tables to authenticated, service_role;

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

create or replace view public.configuration_branding with (security_invoker = off) as
select
    c.id,
    c.config ->> 'title' as title,
    c.config ->> 'darkModeLogo' as "darkModeLogo",
    c.config ->> 'lightModeLogo' as "lightModeLogo"
from atomic_crm.configuration c
where c.id = 1;

-- View grants
grant all on table public.companies to anon, authenticated, service_role;
grant all on table public.contacts to anon, authenticated, service_role;
grant all on table public.contact_notes to anon, authenticated, service_role;
grant all on table public.deals to anon, authenticated, service_role;
grant all on table public.deal_notes to anon, authenticated, service_role;
grant all on table public.sales to anon, authenticated, service_role;
grant all on table public.tags to anon, authenticated, service_role;
grant all on table public.tasks to anon, authenticated, service_role;
grant all on table public.configuration to anon, authenticated, service_role;
grant all on table public.favicons_excluded_domains to anon, authenticated, service_role;
grant all on table public.activity_log to anon, authenticated, service_role;
grant all on table public.companies_summary to anon, authenticated, service_role;
grant all on table public.contacts_summary to anon, authenticated, service_role;
grant all on table public.init_state to anon, authenticated, service_role;
grant select on table public.configuration_branding to anon, authenticated, service_role;

-- Retarget functions that referenced public tables
CREATE OR REPLACE FUNCTION "public"."get_domain_favicon"("domain_name" "text") RETURNS "text"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
declare domain_status int8;

begin
    if exists (select from atomic_crm.favicons_excluded_domains as fav where fav.domain = domain_name) then
        return null;
    end if;

    return concat(
        'https://favicon.show/',
        (regexp_matches(domain_name, '^(?:https?:\/\/)?(?:[^@\/\n]+@)?(?:www\.)?([^:\/?\n]+)', 'i'))[1]
    );
end;
$$;

CREATE OR REPLACE FUNCTION "public"."handle_contact_note_created_or_updated"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  update atomic_crm.contacts set last_seen = new.date where contacts.id = new.contact_id and contacts.last_seen < new.date;
  return new;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  sales_count int;
begin
  select count(id) into sales_count
  from atomic_crm.sales;

  insert into atomic_crm.sales (first_name, last_name, email, user_id, administrator)
  values (
    coalesce(new.raw_user_meta_data ->> 'first_name', new.raw_user_meta_data -> 'custom_claims' ->> 'first_name', 'Pending'),
    coalesce(new.raw_user_meta_data ->> 'last_name', new.raw_user_meta_data -> 'custom_claims' ->> 'last_name', 'Pending'),
    new.email,
    new.id,
    case when sales_count > 0 then FALSE else TRUE end
  );
  return new;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."handle_update_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  update atomic_crm.sales
  set
    first_name = coalesce(new.raw_user_meta_data ->> 'first_name', new.raw_user_meta_data -> 'custom_claims' ->> 'first_name', 'Pending'),
    last_name = coalesce(new.raw_user_meta_data ->> 'last_name', new.raw_user_meta_data -> 'custom_claims' ->> 'last_name', 'Pending'),
    email = new.email
  where user_id = new.id;

  return new;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."is_admin"() RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  return exists (
    select 1 from atomic_crm.sales where user_id = auth.uid() and administrator = true
  );
end;
$$;

CREATE OR REPLACE FUNCTION "public"."merge_contacts"("loser_id" bigint, "winner_id" bigint) RETURNS bigint
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  winner_contact atomic_crm.contacts%ROWTYPE;
  loser_contact atomic_crm.contacts%ROWTYPE;
  deal_record RECORD;
  merged_emails jsonb;
  merged_phones jsonb;
  merged_tags bigint[];
  winner_emails jsonb;
  loser_emails jsonb;
  winner_phones jsonb;
  loser_phones jsonb;
  email_map jsonb;
  phone_map jsonb;
BEGIN
  SELECT * INTO winner_contact FROM atomic_crm.contacts WHERE id = winner_id;
  SELECT * INTO loser_contact FROM atomic_crm.contacts WHERE id = loser_id;

  IF winner_contact IS NULL OR loser_contact IS NULL THEN
    RAISE EXCEPTION 'Contact not found';
  END IF;

  UPDATE atomic_crm.tasks SET contact_id = winner_id WHERE contact_id = loser_id;
  UPDATE atomic_crm.contact_notes SET contact_id = winner_id WHERE contact_id = loser_id;

  FOR deal_record IN
    SELECT id, contact_ids
    FROM atomic_crm.deals
    WHERE contact_ids @> ARRAY[loser_id]
  LOOP
    UPDATE atomic_crm.deals
    SET contact_ids = (
      SELECT ARRAY(
        SELECT DISTINCT unnest(
          array_remove(deal_record.contact_ids, loser_id) || ARRAY[winner_id]
        )
      )
    )
    WHERE id = deal_record.id;
  END LOOP;

  winner_emails := COALESCE(winner_contact.email_jsonb, '[]'::jsonb);
  loser_emails := COALESCE(loser_contact.email_jsonb, '[]'::jsonb);

  email_map := '{}'::jsonb;

  IF jsonb_array_length(winner_emails) > 0 THEN
    FOR i IN 0..jsonb_array_length(winner_emails)-1 LOOP
      email_map := email_map || jsonb_build_object(
        winner_emails->i->>'email',
        winner_emails->i
      );
    END LOOP;
  END IF;

  IF jsonb_array_length(loser_emails) > 0 THEN
    FOR i IN 0..jsonb_array_length(loser_emails)-1 LOOP
      IF NOT email_map ? (loser_emails->i->>'email') THEN
        email_map := email_map || jsonb_build_object(
          loser_emails->i->>'email',
          loser_emails->i
        );
      END IF;
    END LOOP;
  END IF;

  merged_emails := (SELECT jsonb_agg(value) FROM jsonb_each(email_map));
  merged_emails := COALESCE(merged_emails, '[]'::jsonb);

  winner_phones := COALESCE(winner_contact.phone_jsonb, '[]'::jsonb);
  loser_phones := COALESCE(loser_contact.phone_jsonb, '[]'::jsonb);

  phone_map := '{}'::jsonb;

  IF jsonb_array_length(winner_phones) > 0 THEN
    FOR i IN 0..jsonb_array_length(winner_phones)-1 LOOP
      phone_map := phone_map || jsonb_build_object(
        winner_phones->i->>'number',
        winner_phones->i
      );
    END LOOP;
  END IF;

  IF jsonb_array_length(loser_phones) > 0 THEN
    FOR i IN 0..jsonb_array_length(loser_phones)-1 LOOP
      IF NOT phone_map ? (loser_phones->i->>'number') THEN
        phone_map := phone_map || jsonb_build_object(
          loser_phones->i->>'number',
          loser_phones->i
        );
      END IF;
    END LOOP;
  END IF;

  merged_phones := (SELECT jsonb_agg(value) FROM jsonb_each(phone_map));
  merged_phones := COALESCE(merged_phones, '[]'::jsonb);

  merged_tags := ARRAY(
    SELECT DISTINCT unnest(
      COALESCE(winner_contact.tags, ARRAY[]::bigint[]) ||
      COALESCE(loser_contact.tags, ARRAY[]::bigint[])
    )
  );

  UPDATE atomic_crm.contacts SET
    avatar = COALESCE(winner_contact.avatar, loser_contact.avatar),
    gender = COALESCE(winner_contact.gender, loser_contact.gender),
    first_name = COALESCE(winner_contact.first_name, loser_contact.first_name),
    last_name = COALESCE(winner_contact.last_name, loser_contact.last_name),
    title = COALESCE(winner_contact.title, loser_contact.title),
    company_id = COALESCE(winner_contact.company_id, loser_contact.company_id),
    email_jsonb = merged_emails,
    phone_jsonb = merged_phones,
    linkedin_url = COALESCE(winner_contact.linkedin_url, loser_contact.linkedin_url),
    background = COALESCE(winner_contact.background, loser_contact.background),
    has_newsletter = COALESCE(winner_contact.has_newsletter, loser_contact.has_newsletter),
    first_seen = LEAST(COALESCE(winner_contact.first_seen, loser_contact.first_seen), COALESCE(loser_contact.first_seen, winner_contact.first_seen)),
    last_seen = GREATEST(COALESCE(winner_contact.last_seen, loser_contact.last_seen), COALESCE(loser_contact.last_seen, winner_contact.last_seen)),
    sales_id = COALESCE(winner_contact.sales_id, loser_contact.sales_id),
    tags = merged_tags
  WHERE id = winner_id;

  DELETE FROM atomic_crm.contacts WHERE id = loser_id;

  RETURN winner_id;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."set_sales_id_default"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NEW.sales_id IS NULL THEN
    SELECT id INTO NEW.sales_id FROM atomic_crm.sales WHERE user_id = auth.uid();
  END IF;
  RETURN NEW;
END;
$$;
