

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "extensions";






CREATE SCHEMA IF NOT EXISTS "private";


ALTER SCHEMA "private" OWNER TO "postgres";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "citext" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "http" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."cleanup_note_attachments"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
    DECLARE
      payload jsonb;
      request_headers jsonb;
      auth_header text;
    BEGIN
      request_headers := coalesce(
        nullif(current_setting('request.headers', true), '')::jsonb,
        '{}'::jsonb
      );
      auth_header := request_headers ->> 'authorization';

      IF auth_header IS NULL OR auth_header = '' THEN
        IF TG_OP = 'DELETE' THEN
          RETURN OLD;
        END IF;

        RETURN NEW;
      END IF;

      payload := jsonb_build_object(
        'old_record', OLD,
        'record', NEW,
        'type', TG_OP
      );

      PERFORM net.http_post(
        url := public.get_note_attachments_function_url(),
        body := payload,
        params := '{}'::jsonb,
        headers := jsonb_build_object(
          'Content-Type',
          'application/json',
          'Authorization',
          auth_header
        ),
        timeout_milliseconds := 10000
      );

      IF TG_OP = 'DELETE' THEN
        RETURN OLD;
      END IF;

      RETURN NEW;
    END;
    $$;


ALTER FUNCTION "public"."cleanup_note_attachments"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_avatar_for_email"("email" "text") RETURNS "text"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
declare email_hash text;
declare gravatar_url text;
declare gravatar_status int8;
declare email_domain text;
declare favicon_url text;
declare domain_status int8;

begin
    -- Try to fetch a gravatar image
    email_hash = encode(extensions.digest(email, 'sha256'), 'hex');
    gravatar_url = concat('https://www.gravatar.com/avatar/', email_hash, '?d=404');

    select status from extensions.http_get(gravatar_url) into gravatar_status;

    if gravatar_status = 200 then
        return gravatar_url;
    end if;

    -- Fallback to email's domain favicon if not excluded
    email_domain = split_part(email, '@', 2);
    return get_domain_favicon(email_domain);
exception
    when others then
        return 'ERROR';
end;
$$;


ALTER FUNCTION "public"."get_avatar_for_email"("email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_domain_favicon"("domain_name" "text") RETURNS "text"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
declare domain_status int8;

begin
    if exists (select from favicons_excluded_domains as fav where fav.domain = domain_name) then
        return null;
    end if;

    return concat(
        'https://favicon.show/',
        (regexp_matches(domain_name, '^(?:https?:\/\/)?(?:[^@\/\n]+@)?(?:www\.)?([^:\/?\n]+)', 'i'))[1]
    );
end;
$$;


ALTER FUNCTION "public"."get_domain_favicon"("domain_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_note_attachments_function_url"() RETURNS "text"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
    DECLARE
      issuer text;
      function_url text;
    BEGIN
      issuer := coalesce(
        nullif(current_setting('request.jwt.claim.iss', true), ''),
        (
          coalesce(
            nullif(current_setting('request.jwt.claims', true), ''),
            '{}'
          )::jsonb ->> 'iss'
        )
      );
      issuer := nullif(issuer, '');
      IF issuer IS NOT NULL THEN
        issuer := rtrim(issuer, '/');
        IF right(issuer, 8) = '/auth/v1' THEN
          function_url :=
            left(issuer, length(issuer) - 8) || '/functions/v1/delete_note_attachments';

          IF function_url LIKE 'http://127.0.0.1:%' THEN
            RETURN replace(
              function_url,
              'http://127.0.0.1:',
              'http://host.docker.internal:'
            );
          END IF;

          IF function_url LIKE 'http://localhost:%' THEN
            RETURN replace(
              function_url,
              'http://localhost:',
              'http://host.docker.internal:'
            );
          END IF;

          RETURN function_url;
        END IF;
      END IF;

      RETURN 'http://host.docker.internal:54321/functions/v1/delete_note_attachments';
    END;
    $$;


ALTER FUNCTION "public"."get_note_attachments_function_url"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_id_by_email"("email" "text") RETURNS TABLE("id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
BEGIN
  RETURN QUERY SELECT au.id FROM auth.users au WHERE au.email = $1;
END;
$_$;


ALTER FUNCTION "public"."get_user_id_by_email"("email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_company_saved"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
declare company_logo text;

begin
    if new.logo is not null then
        return new;
    end if;

    company_logo = get_domain_favicon(new.website);
    if company_logo is null then
        return new;
    end if;

    new.logo = concat('{"src":"', company_logo, '","title":"Company favicon"}');
    return new;
end;
$$;


ALTER FUNCTION "public"."handle_company_saved"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_contact_note_created_or_updated"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  update public.contacts set last_seen = new.date where contacts.id = new.contact_id and contacts.last_seen < new.date;
  return new;
end;
$$;


ALTER FUNCTION "public"."handle_contact_note_created_or_updated"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_contact_saved"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$declare contact_avatar text;
declare emails_length int8;
declare item jsonb;

begin
    if new.avatar is not null then
        return new;
    end if;

    select coalesce(jsonb_array_length(new.email_jsonb), 0) into emails_length;

    if emails_length = 0 then
        return new;
    end if;

    for item in select jsonb_array_elements(new.email_jsonb)
    loop
        select public.get_avatar_for_email(item->>'email') into contact_avatar;
        if (contact_avatar is not null) then
            exit;
        end if;
    end loop;

    if contact_avatar is null then
        return new;
    end if;

    new.avatar = concat('{"src":"', contact_avatar, '"}');
    return new;
end;$$;


ALTER FUNCTION "public"."handle_contact_saved"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  sales_count int;
begin
  select count(id) into sales_count
  from public.sales;

  insert into public.sales (first_name, last_name, email, user_id, administrator)
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


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_update_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  update public.sales
  set
    first_name = coalesce(new.raw_user_meta_data ->> 'first_name', new.raw_user_meta_data -> 'custom_claims' ->> 'first_name', 'Pending'),
    last_name = coalesce(new.raw_user_meta_data ->> 'last_name', new.raw_user_meta_data -> 'custom_claims' ->> 'last_name', 'Pending'),
    email = new.email
  where user_id = new.id;

  return new;
end;
$$;


ALTER FUNCTION "public"."handle_update_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_admin"() RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  return exists (
    select 1 from public.sales where user_id = auth.uid() and administrator = true
  );
end;
$$;


ALTER FUNCTION "public"."is_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."lowercase_email_jsonb"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NEW.email_jsonb IS NOT NULL THEN
    NEW.email_jsonb = COALESCE((
      SELECT jsonb_agg(
        jsonb_set(elem, '{email}', to_jsonb(LOWER(elem->>'email')))
      )
      FROM jsonb_array_elements(NEW.email_jsonb) AS elem
    ), '[]'::jsonb);
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."lowercase_email_jsonb"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."merge_contacts"("loser_id" bigint, "winner_id" bigint) RETURNS bigint
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
DECLARE
  winner_contact contacts%ROWTYPE;
  loser_contact contacts%ROWTYPE;
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
  -- Fetch both contacts
  SELECT * INTO winner_contact FROM contacts WHERE id = winner_id;
  SELECT * INTO loser_contact FROM contacts WHERE id = loser_id;

  IF winner_contact IS NULL OR loser_contact IS NULL THEN
    RAISE EXCEPTION 'Contact not found';
  END IF;

  -- 1. Reassign tasks from loser to winner
  UPDATE tasks SET contact_id = winner_id WHERE contact_id = loser_id;

  -- 2. Reassign contact notes from loser to winner
  UPDATE contact_notes SET contact_id = winner_id WHERE contact_id = loser_id;

  -- 3. Update deals - replace loser with winner in contact_ids array
  FOR deal_record IN
    SELECT id, contact_ids
    FROM deals
    WHERE contact_ids @> ARRAY[loser_id]
  LOOP
    UPDATE deals
    SET contact_ids = (
      SELECT ARRAY(
        SELECT DISTINCT unnest(
          array_remove(deal_record.contact_ids, loser_id) || ARRAY[winner_id]
        )
      )
    )
    WHERE id = deal_record.id;
  END LOOP;

  -- 4. Merge contact data

  -- Get email arrays
  winner_emails := COALESCE(winner_contact.email_jsonb, '[]'::jsonb);
  loser_emails := COALESCE(loser_contact.email_jsonb, '[]'::jsonb);

  -- Merge emails with deduplication by email address
  -- Build a map of email -> email object, then convert back to array
  email_map := '{}'::jsonb;

  -- Add winner emails to map
  IF jsonb_array_length(winner_emails) > 0 THEN
    FOR i IN 0..jsonb_array_length(winner_emails)-1 LOOP
      email_map := email_map || jsonb_build_object(
        winner_emails->i->>'email',
        winner_emails->i
      );
    END LOOP;
  END IF;

  -- Add loser emails to map (won't overwrite existing keys)
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

  -- Convert map back to array
  merged_emails := (SELECT jsonb_agg(value) FROM jsonb_each(email_map));
  merged_emails := COALESCE(merged_emails, '[]'::jsonb);

  -- Get phone arrays
  winner_phones := COALESCE(winner_contact.phone_jsonb, '[]'::jsonb);
  loser_phones := COALESCE(loser_contact.phone_jsonb, '[]'::jsonb);

  -- Merge phones with deduplication by number
  phone_map := '{}'::jsonb;

  -- Add winner phones to map
  IF jsonb_array_length(winner_phones) > 0 THEN
    FOR i IN 0..jsonb_array_length(winner_phones)-1 LOOP
      phone_map := phone_map || jsonb_build_object(
        winner_phones->i->>'number',
        winner_phones->i
      );
    END LOOP;
  END IF;

  -- Add loser phones to map (won't overwrite existing keys)
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

  -- Convert map back to array
  merged_phones := (SELECT jsonb_agg(value) FROM jsonb_each(phone_map));
  merged_phones := COALESCE(merged_phones, '[]'::jsonb);

  -- Merge tags (remove duplicates)
  merged_tags := ARRAY(
    SELECT DISTINCT unnest(
      COALESCE(winner_contact.tags, ARRAY[]::bigint[]) ||
      COALESCE(loser_contact.tags, ARRAY[]::bigint[])
    )
  );

  -- 5. Update winner with merged data
  UPDATE contacts SET
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

  -- 6. Delete loser contact
  DELETE FROM contacts WHERE id = loser_id;

  RETURN winner_id;
END;
$$;


ALTER FUNCTION "public"."merge_contacts"("loser_id" bigint, "winner_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_sales_id_default"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NEW.sales_id IS NULL THEN
    SELECT id INTO NEW.sales_id FROM sales WHERE user_id = auth.uid();
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."set_sales_id_default"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."companies" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "name" "text" NOT NULL,
    "sector" "text",
    "size" smallint,
    "linkedin_url" "text",
    "website" "extensions"."citext",
    "phone_number" "text",
    "address" "text",
    "zipcode" "text",
    "city" "text",
    "state_abbr" "text",
    "sales_id" bigint,
    "context_links" "json",
    "country" "text",
    "description" "text",
    "revenue" "text",
    "tax_identifier" "text",
    "logo" "jsonb"
);


ALTER TABLE "public"."companies" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."contact_notes" (
    "id" bigint NOT NULL,
    "contact_id" bigint NOT NULL,
    "text" "text",
    "date" timestamp with time zone DEFAULT "now"(),
    "sales_id" bigint,
    "status" "text",
    "attachments" "jsonb"[]
);


ALTER TABLE "public"."contact_notes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."contacts" (
    "id" bigint NOT NULL,
    "first_name" "text",
    "last_name" "text",
    "gender" "text",
    "title" "text",
    "background" "text",
    "avatar" "jsonb",
    "first_seen" timestamp with time zone,
    "last_seen" timestamp with time zone,
    "has_newsletter" boolean,
    "status" "text",
    "tags" bigint[],
    "company_id" bigint,
    "sales_id" bigint,
    "linkedin_url" "text",
    "email_jsonb" "jsonb",
    "phone_jsonb" "jsonb"
);


ALTER TABLE "public"."contacts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."deal_notes" (
    "id" bigint NOT NULL,
    "deal_id" bigint NOT NULL,
    "type" "text",
    "text" "text",
    "date" timestamp with time zone DEFAULT "now"(),
    "sales_id" bigint,
    "attachments" "jsonb"[]
);


ALTER TABLE "public"."deal_notes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."deals" (
    "id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "company_id" bigint,
    "contact_ids" bigint[],
    "category" "text",
    "stage" "text" NOT NULL,
    "description" "text",
    "amount" bigint,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "archived_at" timestamp with time zone,
    "expected_closing_date" "date",
    "sales_id" bigint,
    "index" smallint
);


ALTER TABLE "public"."deals" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."activity_log" WITH ("security_invoker"='on') AS
 SELECT (('company.'::"text" || "c"."id") || '.created'::"text") AS "id",
    'company.created'::"text" AS "type",
    "c"."created_at" AS "date",
    "c"."id" AS "company_id",
    "c"."sales_id",
    "to_json"("c".*) AS "company",
    NULL::"json" AS "contact",
    NULL::"json" AS "deal",
    NULL::"json" AS "contact_note",
    NULL::"json" AS "deal_note"
   FROM "public"."companies" "c"
UNION ALL
 SELECT (('contact.'::"text" || "co"."id") || '.created'::"text") AS "id",
    'contact.created'::"text" AS "type",
    "co"."first_seen" AS "date",
    "co"."company_id",
    "co"."sales_id",
    NULL::"json" AS "company",
    "to_json"("co".*) AS "contact",
    NULL::"json" AS "deal",
    NULL::"json" AS "contact_note",
    NULL::"json" AS "deal_note"
   FROM "public"."contacts" "co"
UNION ALL
 SELECT (('contactNote.'::"text" || "cn"."id") || '.created'::"text") AS "id",
    'contactNote.created'::"text" AS "type",
    "cn"."date",
    "co"."company_id",
    "cn"."sales_id",
    NULL::"json" AS "company",
    NULL::"json" AS "contact",
    NULL::"json" AS "deal",
    "to_json"("cn".*) AS "contact_note",
    NULL::"json" AS "deal_note"
   FROM ("public"."contact_notes" "cn"
     LEFT JOIN "public"."contacts" "co" ON (("co"."id" = "cn"."contact_id")))
UNION ALL
 SELECT (('deal.'::"text" || "d"."id") || '.created'::"text") AS "id",
    'deal.created'::"text" AS "type",
    "d"."created_at" AS "date",
    "d"."company_id",
    "d"."sales_id",
    NULL::"json" AS "company",
    NULL::"json" AS "contact",
    "to_json"("d".*) AS "deal",
    NULL::"json" AS "contact_note",
    NULL::"json" AS "deal_note"
   FROM "public"."deals" "d"
UNION ALL
 SELECT (('dealNote.'::"text" || "dn"."id") || '.created'::"text") AS "id",
    'dealNote.created'::"text" AS "type",
    "dn"."date",
    "d"."company_id",
    "dn"."sales_id",
    NULL::"json" AS "company",
    NULL::"json" AS "contact",
    NULL::"json" AS "deal",
    NULL::"json" AS "contact_note",
    "to_json"("dn".*) AS "deal_note"
   FROM ("public"."deal_notes" "dn"
     LEFT JOIN "public"."deals" "d" ON (("d"."id" = "dn"."deal_id")));


ALTER TABLE "public"."activity_log" OWNER TO "postgres";


ALTER TABLE "public"."companies" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."companies_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE OR REPLACE VIEW "public"."companies_summary" AS
SELECT
    NULL::bigint AS "id",
    NULL::timestamp with time zone AS "created_at",
    NULL::"text" AS "name",
    NULL::"text" AS "sector",
    NULL::smallint AS "size",
    NULL::"text" AS "linkedin_url",
    NULL::"extensions"."citext" AS "website",
    NULL::"text" AS "phone_number",
    NULL::"text" AS "address",
    NULL::"text" AS "zipcode",
    NULL::"text" AS "city",
    NULL::"text" AS "state_abbr",
    NULL::bigint AS "sales_id",
    NULL::"json" AS "context_links",
    NULL::"text" AS "country",
    NULL::"text" AS "description",
    NULL::"text" AS "revenue",
    NULL::"text" AS "tax_identifier",
    NULL::"jsonb" AS "logo",
    NULL::bigint AS "nb_deals",
    NULL::bigint AS "nb_contacts";


ALTER TABLE "public"."companies_summary" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."configuration" (
    "id" integer DEFAULT 1 NOT NULL,
    "config" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    CONSTRAINT "configuration_singleton" CHECK (("id" = 1))
);


ALTER TABLE "public"."configuration" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."configuration_branding" WITH ("security_invoker"='off') AS
 SELECT "c"."id",
    ("c"."config" ->> 'title'::"text") AS "title",
    ("c"."config" ->> 'darkModeLogo'::"text") AS "darkModeLogo",
    ("c"."config" ->> 'lightModeLogo'::"text") AS "lightModeLogo"
   FROM "public"."configuration" "c"
  WHERE ("c"."id" = 1);


ALTER TABLE "public"."configuration_branding" OWNER TO "postgres";


ALTER TABLE "public"."contact_notes" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."contactNotes_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE "public"."contacts" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."contacts_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE OR REPLACE VIEW "public"."contacts_summary" AS
SELECT
    NULL::bigint AS "id",
    NULL::"text" AS "first_name",
    NULL::"text" AS "last_name",
    NULL::"text" AS "gender",
    NULL::"text" AS "title",
    NULL::"text" AS "background",
    NULL::"jsonb" AS "avatar",
    NULL::timestamp with time zone AS "first_seen",
    NULL::timestamp with time zone AS "last_seen",
    NULL::boolean AS "has_newsletter",
    NULL::"text" AS "status",
    NULL::bigint[] AS "tags",
    NULL::bigint AS "company_id",
    NULL::bigint AS "sales_id",
    NULL::"text" AS "linkedin_url",
    NULL::"jsonb" AS "email_jsonb",
    NULL::"jsonb" AS "phone_jsonb",
    NULL::"text" AS "email_fts",
    NULL::"text" AS "phone_fts",
    NULL::"text" AS "company_name",
    NULL::bigint AS "nb_tasks";


ALTER TABLE "public"."contacts_summary" OWNER TO "postgres";


ALTER TABLE "public"."deal_notes" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."dealNotes_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE "public"."deals" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."deals_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."favicons_excluded_domains" (
    "id" bigint NOT NULL,
    "domain" "text" NOT NULL
);


ALTER TABLE "public"."favicons_excluded_domains" OWNER TO "postgres";


ALTER TABLE "public"."favicons_excluded_domains" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."favicons_excluded_domains_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."sales" (
    "id" bigint NOT NULL,
    "first_name" "text" DEFAULT 'Pending'::"text" NOT NULL,
    "last_name" "text" DEFAULT 'Pending'::"text" NOT NULL,
    "email" "extensions"."citext" NOT NULL,
    "administrator" boolean NOT NULL,
    "user_id" "uuid" NOT NULL,
    "avatar" "jsonb",
    "disabled" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."sales" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."init_state" WITH ("security_invoker"='off') AS
 SELECT "count"("sub"."id") AS "is_initialized"
   FROM ( SELECT "sales"."id"
           FROM "public"."sales"
         LIMIT 1) "sub";


ALTER TABLE "public"."init_state" OWNER TO "postgres";


ALTER TABLE "public"."sales" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."sales_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."tags" (
    "id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "color" "text" NOT NULL
);


ALTER TABLE "public"."tags" OWNER TO "postgres";


ALTER TABLE "public"."tags" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."tags_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."tasks" (
    "id" bigint NOT NULL,
    "contact_id" bigint NOT NULL,
    "type" "text",
    "text" "text",
    "due_date" timestamp with time zone,
    "done_date" timestamp with time zone,
    "sales_id" bigint
);


ALTER TABLE "public"."tasks" OWNER TO "postgres";


ALTER TABLE "public"."tasks" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."tasks_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE ONLY "public"."companies"
    ADD CONSTRAINT "companies_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."configuration"
    ADD CONSTRAINT "configuration_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."contact_notes"
    ADD CONSTRAINT "contactNotes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."deal_notes"
    ADD CONSTRAINT "dealNotes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."deals"
    ADD CONSTRAINT "deals_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."favicons_excluded_domains"
    ADD CONSTRAINT "favicons_excluded_domains_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales"
    ADD CONSTRAINT "sales_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tags"
    ADD CONSTRAINT "tags_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tasks"
    ADD CONSTRAINT "tasks_pkey" PRIMARY KEY ("id");



CREATE INDEX "contact_notes_contact_id_idx" ON "public"."contact_notes" USING "btree" ("contact_id");



CREATE INDEX "contacts_company_id_idx" ON "public"."contacts" USING "btree" ("company_id");



CREATE INDEX "deal_notes_deal_id_idx" ON "public"."deal_notes" USING "btree" ("deal_id");



CREATE INDEX "deals_company_id_idx" ON "public"."deals" USING "btree" ("company_id");



CREATE UNIQUE INDEX "uq__sales__user_id" ON "public"."sales" USING "btree" ("user_id");



CREATE OR REPLACE VIEW "public"."contacts_summary" WITH ("security_invoker"='on') AS
 SELECT "co"."id",
    "co"."first_name",
    "co"."last_name",
    "co"."gender",
    "co"."title",
    "co"."background",
    "co"."avatar",
    "co"."first_seen",
    "co"."last_seen",
    "co"."has_newsletter",
    "co"."status",
    "co"."tags",
    "co"."company_id",
    "co"."sales_id",
    "co"."linkedin_url",
    "co"."email_jsonb",
    "co"."phone_jsonb",
    ("jsonb_path_query_array"("co"."email_jsonb", '$[*]."email"'::"jsonpath"))::"text" AS "email_fts",
    ("jsonb_path_query_array"("co"."phone_jsonb", '$[*]."number"'::"jsonpath"))::"text" AS "phone_fts",
    "c"."name" AS "company_name",
    "count"(DISTINCT "t"."id") FILTER (WHERE ("t"."done_date" IS NULL)) AS "nb_tasks"
   FROM (("public"."contacts" "co"
     LEFT JOIN "public"."tasks" "t" ON (("co"."id" = "t"."contact_id")))
     LEFT JOIN "public"."companies" "c" ON (("co"."company_id" = "c"."id")))
  GROUP BY "co"."id", "c"."name";



CREATE OR REPLACE VIEW "public"."companies_summary" WITH ("security_invoker"='on') AS
 SELECT "c"."id",
    "c"."created_at",
    "c"."name",
    "c"."sector",
    "c"."size",
    "c"."linkedin_url",
    "c"."website",
    "c"."phone_number",
    "c"."address",
    "c"."zipcode",
    "c"."city",
    "c"."state_abbr",
    "c"."sales_id",
    "c"."context_links",
    "c"."country",
    "c"."description",
    "c"."revenue",
    "c"."tax_identifier",
    "c"."logo",
    "count"(DISTINCT "d"."id") AS "nb_deals",
    "count"(DISTINCT "co"."id") AS "nb_contacts"
   FROM (("public"."companies" "c"
     LEFT JOIN "public"."deals" "d" ON (("c"."id" = "d"."company_id")))
     LEFT JOIN "public"."contacts" "co" ON (("c"."id" = "co"."company_id")))
  GROUP BY "c"."id";



CREATE OR REPLACE TRIGGER "10_lowercase_contact_emails" BEFORE INSERT OR UPDATE ON "public"."contacts" FOR EACH ROW EXECUTE FUNCTION "public"."lowercase_email_jsonb"();



CREATE OR REPLACE TRIGGER "20_contact_saved" BEFORE INSERT OR UPDATE ON "public"."contacts" FOR EACH ROW EXECUTE FUNCTION "public"."handle_contact_saved"();



CREATE OR REPLACE TRIGGER "company_saved" BEFORE INSERT OR UPDATE ON "public"."companies" FOR EACH ROW EXECUTE FUNCTION "public"."handle_company_saved"();



CREATE OR REPLACE TRIGGER "on_contact_notes_attachments_updated_delete_note_attachments" AFTER UPDATE ON "public"."contact_notes" FOR EACH ROW WHEN (("old"."attachments" IS DISTINCT FROM "new"."attachments")) EXECUTE FUNCTION "public"."cleanup_note_attachments"();



CREATE OR REPLACE TRIGGER "on_contact_notes_deleted_delete_note_attachments" AFTER DELETE ON "public"."contact_notes" FOR EACH ROW EXECUTE FUNCTION "public"."cleanup_note_attachments"();



CREATE OR REPLACE TRIGGER "on_deal_notes_attachments_updated_delete_note_attachments" AFTER UPDATE ON "public"."deal_notes" FOR EACH ROW WHEN (("old"."attachments" IS DISTINCT FROM "new"."attachments")) EXECUTE FUNCTION "public"."cleanup_note_attachments"();



CREATE OR REPLACE TRIGGER "on_deal_notes_deleted_delete_note_attachments" AFTER DELETE ON "public"."deal_notes" FOR EACH ROW EXECUTE FUNCTION "public"."cleanup_note_attachments"();



CREATE OR REPLACE TRIGGER "on_public_contact_notes_created_or_updated" AFTER INSERT ON "public"."contact_notes" FOR EACH ROW EXECUTE FUNCTION "public"."handle_contact_note_created_or_updated"();



CREATE OR REPLACE TRIGGER "set_company_sales_id_trigger" BEFORE INSERT ON "public"."companies" FOR EACH ROW EXECUTE FUNCTION "public"."set_sales_id_default"();



CREATE OR REPLACE TRIGGER "set_contact_notes_sales_id_trigger" BEFORE INSERT ON "public"."contact_notes" FOR EACH ROW EXECUTE FUNCTION "public"."set_sales_id_default"();



CREATE OR REPLACE TRIGGER "set_contact_sales_id_trigger" BEFORE INSERT ON "public"."contacts" FOR EACH ROW EXECUTE FUNCTION "public"."set_sales_id_default"();



CREATE OR REPLACE TRIGGER "set_deal_notes_sales_id_trigger" BEFORE INSERT ON "public"."deal_notes" FOR EACH ROW EXECUTE FUNCTION "public"."set_sales_id_default"();



CREATE OR REPLACE TRIGGER "set_deal_sales_id_trigger" BEFORE INSERT ON "public"."deals" FOR EACH ROW EXECUTE FUNCTION "public"."set_sales_id_default"();



CREATE OR REPLACE TRIGGER "set_task_sales_id_trigger" BEFORE INSERT ON "public"."tasks" FOR EACH ROW EXECUTE FUNCTION "public"."set_sales_id_default"();



ALTER TABLE ONLY "public"."companies"
    ADD CONSTRAINT "companies_sales_id_fkey" FOREIGN KEY ("sales_id") REFERENCES "public"."sales"("id");



ALTER TABLE ONLY "public"."contact_notes"
    ADD CONSTRAINT "contactNotes_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."contact_notes"
    ADD CONSTRAINT "contactNotes_sales_id_fkey" FOREIGN KEY ("sales_id") REFERENCES "public"."sales"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_sales_id_fkey" FOREIGN KEY ("sales_id") REFERENCES "public"."sales"("id");



ALTER TABLE ONLY "public"."deal_notes"
    ADD CONSTRAINT "dealNotes_deal_id_fkey" FOREIGN KEY ("deal_id") REFERENCES "public"."deals"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."deal_notes"
    ADD CONSTRAINT "dealNotes_sales_id_fkey" FOREIGN KEY ("sales_id") REFERENCES "public"."sales"("id");



ALTER TABLE ONLY "public"."deals"
    ADD CONSTRAINT "deals_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."deals"
    ADD CONSTRAINT "deals_sales_id_fkey" FOREIGN KEY ("sales_id") REFERENCES "public"."sales"("id");



ALTER TABLE ONLY "public"."sales"
    ADD CONSTRAINT "sales_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."tasks"
    ADD CONSTRAINT "tasks_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id") ON UPDATE CASCADE ON DELETE CASCADE;



CREATE POLICY "Company Delete Policy" ON "public"."companies" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "Contact Delete Policy" ON "public"."contacts" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "Contact Notes Delete Policy" ON "public"."contact_notes" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "Contact Notes Update policy" ON "public"."contact_notes" FOR UPDATE TO "authenticated" USING (true);



CREATE POLICY "Deal Notes Delete Policy" ON "public"."deal_notes" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "Deal Notes Update Policy" ON "public"."deal_notes" FOR UPDATE TO "authenticated" USING (true);



CREATE POLICY "Deals Delete Policy" ON "public"."deals" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "Enable access for authenticated users only" ON "public"."favicons_excluded_domains" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Enable delete for authenticated users only" ON "public"."tags" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "Enable insert for admins" ON "public"."configuration" FOR INSERT TO "authenticated" WITH CHECK ("public"."is_admin"());



CREATE POLICY "Enable insert for authenticated users only" ON "public"."companies" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."contact_notes" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."contacts" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."deal_notes" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."deals" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."tags" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."tasks" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable read access for authenticated users" ON "public"."companies" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Enable read access for authenticated users" ON "public"."contact_notes" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Enable read access for authenticated users" ON "public"."contacts" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Enable read access for authenticated users" ON "public"."deal_notes" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Enable read access for authenticated users" ON "public"."deals" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Enable read access for authenticated users" ON "public"."sales" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Enable read access for authenticated users" ON "public"."tags" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Enable read access for authenticated users" ON "public"."tasks" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Enable read for authenticated" ON "public"."configuration" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Enable update for admins" ON "public"."configuration" FOR UPDATE TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "Enable update for authenticated users only" ON "public"."companies" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Enable update for authenticated users only" ON "public"."contacts" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Enable update for authenticated users only" ON "public"."deals" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Enable update for authenticated users only" ON "public"."tags" FOR UPDATE TO "authenticated" USING (true);



CREATE POLICY "Task Delete Policy" ON "public"."tasks" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "Task Update Policy" ON "public"."tasks" FOR UPDATE TO "authenticated" USING (true);



ALTER TABLE "public"."companies" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."configuration" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."contact_notes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."contacts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."deal_notes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."deals" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."favicons_excluded_domains" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sales" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."tags" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."tasks" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";





GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

















































































































































































































































































































































































REVOKE ALL ON FUNCTION "public"."get_user_id_by_email"("email" "text") FROM PUBLIC;
























GRANT REFERENCES,TRIGGER,TRUNCATE ON TABLE "public"."companies" TO "anon";
GRANT ALL ON TABLE "public"."companies" TO "authenticated";
GRANT ALL ON TABLE "public"."companies" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE ON TABLE "public"."contact_notes" TO "anon";
GRANT ALL ON TABLE "public"."contact_notes" TO "authenticated";
GRANT ALL ON TABLE "public"."contact_notes" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE ON TABLE "public"."contacts" TO "anon";
GRANT ALL ON TABLE "public"."contacts" TO "authenticated";
GRANT ALL ON TABLE "public"."contacts" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE ON TABLE "public"."deal_notes" TO "anon";
GRANT ALL ON TABLE "public"."deal_notes" TO "authenticated";
GRANT ALL ON TABLE "public"."deal_notes" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE ON TABLE "public"."deals" TO "anon";
GRANT ALL ON TABLE "public"."deals" TO "authenticated";
GRANT ALL ON TABLE "public"."deals" TO "service_role";



GRANT ALL ON TABLE "public"."activity_log" TO "anon";
GRANT ALL ON TABLE "public"."activity_log" TO "authenticated";
GRANT ALL ON TABLE "public"."activity_log" TO "service_role";



GRANT UPDATE ON SEQUENCE "public"."companies_id_seq" TO "anon";
GRANT UPDATE ON SEQUENCE "public"."companies_id_seq" TO "authenticated";
GRANT UPDATE ON SEQUENCE "public"."companies_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."companies_summary" TO "anon";
GRANT ALL ON TABLE "public"."companies_summary" TO "authenticated";
GRANT ALL ON TABLE "public"."companies_summary" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE ON TABLE "public"."configuration" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."configuration" TO "authenticated";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."configuration" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE ON TABLE "public"."configuration_branding" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE ON TABLE "public"."configuration_branding" TO "authenticated";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE ON TABLE "public"."configuration_branding" TO "service_role";



GRANT UPDATE ON SEQUENCE "public"."contactNotes_id_seq" TO "anon";
GRANT UPDATE ON SEQUENCE "public"."contactNotes_id_seq" TO "authenticated";
GRANT UPDATE ON SEQUENCE "public"."contactNotes_id_seq" TO "service_role";



GRANT UPDATE ON SEQUENCE "public"."contacts_id_seq" TO "anon";
GRANT UPDATE ON SEQUENCE "public"."contacts_id_seq" TO "authenticated";
GRANT UPDATE ON SEQUENCE "public"."contacts_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."contacts_summary" TO "anon";
GRANT ALL ON TABLE "public"."contacts_summary" TO "authenticated";
GRANT ALL ON TABLE "public"."contacts_summary" TO "service_role";



GRANT UPDATE ON SEQUENCE "public"."dealNotes_id_seq" TO "anon";
GRANT UPDATE ON SEQUENCE "public"."dealNotes_id_seq" TO "authenticated";
GRANT UPDATE ON SEQUENCE "public"."dealNotes_id_seq" TO "service_role";



GRANT UPDATE ON SEQUENCE "public"."deals_id_seq" TO "anon";
GRANT UPDATE ON SEQUENCE "public"."deals_id_seq" TO "authenticated";
GRANT UPDATE ON SEQUENCE "public"."deals_id_seq" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE ON TABLE "public"."favicons_excluded_domains" TO "anon";
GRANT ALL ON TABLE "public"."favicons_excluded_domains" TO "authenticated";
GRANT ALL ON TABLE "public"."favicons_excluded_domains" TO "service_role";



GRANT UPDATE ON SEQUENCE "public"."favicons_excluded_domains_id_seq" TO "anon";
GRANT UPDATE ON SEQUENCE "public"."favicons_excluded_domains_id_seq" TO "authenticated";
GRANT UPDATE ON SEQUENCE "public"."favicons_excluded_domains_id_seq" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE ON TABLE "public"."sales" TO "anon";
GRANT ALL ON TABLE "public"."sales" TO "authenticated";
GRANT ALL ON TABLE "public"."sales" TO "service_role";



GRANT ALL ON TABLE "public"."init_state" TO "anon";
GRANT ALL ON TABLE "public"."init_state" TO "authenticated";
GRANT ALL ON TABLE "public"."init_state" TO "service_role";



GRANT UPDATE ON SEQUENCE "public"."sales_id_seq" TO "anon";
GRANT UPDATE ON SEQUENCE "public"."sales_id_seq" TO "authenticated";
GRANT UPDATE ON SEQUENCE "public"."sales_id_seq" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE ON TABLE "public"."tags" TO "anon";
GRANT ALL ON TABLE "public"."tags" TO "authenticated";
GRANT ALL ON TABLE "public"."tags" TO "service_role";



GRANT UPDATE ON SEQUENCE "public"."tags_id_seq" TO "anon";
GRANT UPDATE ON SEQUENCE "public"."tags_id_seq" TO "authenticated";
GRANT UPDATE ON SEQUENCE "public"."tags_id_seq" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE ON TABLE "public"."tasks" TO "anon";
GRANT ALL ON TABLE "public"."tasks" TO "authenticated";
GRANT ALL ON TABLE "public"."tasks" TO "service_role";



GRANT UPDATE ON SEQUENCE "public"."tasks_id_seq" TO "anon";
GRANT UPDATE ON SEQUENCE "public"."tasks_id_seq" TO "authenticated";
GRANT UPDATE ON SEQUENCE "public"."tasks_id_seq" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT UPDATE ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT UPDATE ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT UPDATE ON SEQUENCES  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "postgres";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE ON TABLES  TO "service_role";































--
-- Dumped schema changes for auth and storage
--

CREATE OR REPLACE TRIGGER "on_auth_user_created" AFTER INSERT ON "auth"."users" FOR EACH ROW EXECUTE FUNCTION "public"."handle_new_user"();



CREATE OR REPLACE TRIGGER "on_auth_user_updated" AFTER UPDATE ON "auth"."users" FOR EACH ROW EXECUTE FUNCTION "public"."handle_update_user"();



CREATE POLICY "Attachments 1mt4rzk_0" ON "storage"."objects" FOR SELECT TO "authenticated" USING (("bucket_id" = 'attachments'::"text"));



CREATE POLICY "Attachments 1mt4rzk_1" ON "storage"."objects" FOR INSERT TO "authenticated" WITH CHECK (("bucket_id" = 'attachments'::"text"));



CREATE POLICY "Attachments 1mt4rzk_3" ON "storage"."objects" FOR DELETE TO "authenticated" USING (("bucket_id" = 'attachments'::"text"));



