-- Noote initial backend schema — mirrors the local Drift tables
-- (lib/data/database/tables/) plus an owner_id added for per-user RLS.
-- See noote-plan.md §4/§5/§6 and the "Online sync + Auth" plan for context.
--
-- Scope: single-user ownership only (owner_id = auth.uid()). Real sharing
-- (folder_shares/note_shares) is a later, separate pass — see Build Order
-- step 7 in noote-plan.md.

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------

create table public.folders (
  id text primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  parent_id text references public.folders (id) on delete set null,
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false
);

create table public.tags (
  id text primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  unique (owner_id, name)
);

create table public.notes (
  id text primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  folder_id text references public.folders (id) on delete set null,
  title text not null default '',
  title_style_json jsonb not null default '[]'::jsonb,
  body_json jsonb not null default '{"document":{"type":"page","children":[{"type":"paragraph","data":{"delta":[]}}]}}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false,
  deleted_at timestamptz
);

-- `id` (not a composite `(note_id, tag_id)` key) because PowerSync's Table
-- schema requires a single-column primary key on every synced table — see
-- lib/data/sync/powersync_schema.dart. It's deterministic
-- (`note_id || '::' || tag_id`, stamped by attach_tag below), so it still
-- can't collide or duplicate the way an arbitrary generated id could.
create table public.notes_tags (
  id text primary key,
  note_id text not null references public.notes (id) on delete cascade,
  tag_id text not null references public.tags (id) on delete cascade,
  owner_id uuid not null references auth.users (id) on delete cascade
);

create index notes_owner_id_idx on public.notes (owner_id);
create index notes_folder_id_idx on public.notes (folder_id);
create index folders_owner_id_idx on public.folders (owner_id);
create index tags_owner_id_idx on public.tags (owner_id);
create index notes_tags_owner_id_idx on public.notes_tags (owner_id);

-- ---------------------------------------------------------------------
-- Row Level Security — owner-only for this pass
-- ---------------------------------------------------------------------

alter table public.folders enable row level security;
alter table public.tags enable row level security;
alter table public.notes enable row level security;
alter table public.notes_tags enable row level security;

create policy "Owner can manage their folders" on public.folders
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy "Owner can manage their tags" on public.tags
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy "Owner can manage their notes" on public.notes
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy "Owner can manage their notes_tags" on public.notes_tags
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- ---------------------------------------------------------------------
-- Stored procedures — the only way client code writes these tables
-- (noote-plan.md §4: "no direct table writes from the client"). Each
-- re-checks/stamps owner_id from auth.uid() itself rather than trusting
-- a client-supplied value.
-- ---------------------------------------------------------------------

create or replace function public.upsert_folder(
  p_id text,
  p_name text,
  p_parent_id text,
  p_updated_at timestamptz
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.folders (id, owner_id, name, parent_id, updated_at)
  values (p_id, auth.uid(), p_name, p_parent_id, p_updated_at)
  on conflict (id) do update set
    name = excluded.name,
    parent_id = excluded.parent_id,
    updated_at = excluded.updated_at
  where public.folders.owner_id = auth.uid();
end;
$$;

create or replace function public.delete_folder(p_id text) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.folders
  set is_deleted = true, updated_at = now()
  where id = p_id and owner_id = auth.uid();
end;
$$;

create or replace function public.upsert_note(
  p_id text,
  p_folder_id text,
  p_title text,
  p_title_style_json jsonb,
  p_body_json jsonb,
  p_created_at timestamptz,
  p_updated_at timestamptz
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notes
    (id, owner_id, folder_id, title, title_style_json, body_json, created_at, updated_at)
  values
    (p_id, auth.uid(), p_folder_id, p_title, p_title_style_json, p_body_json, p_created_at, p_updated_at)
  on conflict (id) do update set
    folder_id = excluded.folder_id,
    title = excluded.title,
    title_style_json = excluded.title_style_json,
    body_json = excluded.body_json,
    updated_at = excluded.updated_at
  where public.notes.owner_id = auth.uid();
end;
$$;

create or replace function public.delete_note(p_id text) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.notes
  set is_deleted = true, deleted_at = now(), updated_at = now()
  where id = p_id and owner_id = auth.uid();
end;
$$;

create or replace function public.upsert_tag(p_id text, p_name text) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.tags (id, owner_id, name)
  values (p_id, auth.uid(), p_name)
  on conflict (id) do update set
    name = excluded.name
  where public.tags.owner_id = auth.uid();
end;
$$;

create or replace function public.attach_tag(p_note_id text, p_tag_id text) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notes_tags (id, note_id, tag_id, owner_id)
  values (p_note_id || '::' || p_tag_id, p_note_id, p_tag_id, auth.uid())
  on conflict (id) do nothing;
end;
$$;

create or replace function public.detach_tag(p_note_id text, p_tag_id text) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.notes_tags
  where id = p_note_id || '::' || p_tag_id and owner_id = auth.uid();
end;
$$;

-- Callers need EXECUTE on the functions themselves — SECURITY DEFINER
-- only bypasses RLS *inside* the function body, it doesn't grant the
-- privilege to invoke it in the first place.
grant execute on function
  public.upsert_folder(text, text, text, timestamptz),
  public.delete_folder(text),
  public.upsert_note(text, text, text, jsonb, jsonb, timestamptz, timestamptz),
  public.delete_note(text),
  public.upsert_tag(text, text),
  public.attach_tag(text, text),
  public.detach_tag(text, text)
to authenticated;

-- ---------------------------------------------------------------------
-- PowerSync wiring — replication role + publication it reads from.
-- See PowerSync's Supabase integration guide for the full connection
-- setup (this migration only covers the Postgres-side prerequisites).
-- ---------------------------------------------------------------------

create publication powersync for table public.notes, public.folders, public.tags, public.notes_tags;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'powersync_role') then
    create role powersync_role with replication login password 'powersync_local_dev_password';
  end if;
end
$$;

grant usage on schema public to powersync_role;
grant select on public.notes, public.folders, public.tags, public.notes_tags to powersync_role;

-- The replication connection has no JWT context (it's not going through
-- PostgREST), so auth.uid() resolves to null for it — without BYPASSRLS,
-- the owner_id = auth.uid() policies above would match nothing and
-- replication would silently see zero rows. Sync rules (see
-- powersync/config/sync-config.yaml) are what actually apply the
-- per-user filtering when serving data to clients.
alter role powersync_role bypassrls;
