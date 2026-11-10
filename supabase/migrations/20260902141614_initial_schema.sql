-- Noote initial backend schema — mirrors the local Drift tables
-- (lib/data/database/tables/) plus an owner_id for per-user RLS.
-- See noote-plan.md §4/§5/§6.
--
-- Sync model: there is no sync server. The app keeps a local outbox of
-- changed rows and uploads them through push_changes() below; "Download"
-- reads these tables directly (RLS limits it to the caller's rows) and
-- replaces the local copy. See lib/data/sync/sync_service.dart.
--
-- Every primary key starts with owner_id. Seeded content uses fixed ids
-- ('personal', 'shared', 'grocery-list', ...) that every account has, so
-- ids are only unique per owner, never globally.
--
-- Scope: single-user ownership only (owner_id = auth.uid()). Real sharing
-- (folder_shares/note_shares) is a later, separate pass — see Build Order
-- step 7 in noote-plan.md.
--
-- Foreign keys are DEFERRABLE INITIALLY DEFERRED so one push_changes()
-- call can contain a note before the folder it points at (they're checked
-- at commit, not per statement).

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------

create table public.folders (
  owner_id uuid not null references auth.users (id) on delete cascade,
  id text not null,
  name text not null,
  parent_id text,
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false,
  primary key (owner_id, id),
  foreign key (owner_id, parent_id) references public.folders (owner_id, id)
    on delete set null (parent_id) deferrable initially deferred
);

create table public.tags (
  owner_id uuid not null references auth.users (id) on delete cascade,
  id text not null,
  name text not null,
  primary key (owner_id, id),
  unique (owner_id, name)
);

create table public.notes (
  owner_id uuid not null references auth.users (id) on delete cascade,
  id text not null,
  folder_id text,
  title text not null default '',
  title_style_json jsonb not null default '[]'::jsonb,
  body_json jsonb not null default '{"document":{"type":"page","children":[{"type":"paragraph","data":{"delta":[]}}]}}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false,
  deleted_at timestamptz,
  primary key (owner_id, id),
  foreign key (owner_id, folder_id) references public.folders (owner_id, id)
    on delete set null (folder_id) deferrable initially deferred
);

create table public.notes_tags (
  owner_id uuid not null references auth.users (id) on delete cascade,
  note_id text not null,
  tag_id text not null,
  primary key (owner_id, note_id, tag_id),
  foreign key (owner_id, note_id) references public.notes (owner_id, id)
    on delete cascade deferrable initially deferred,
  foreign key (owner_id, tag_id) references public.tags (owner_id, id)
    on delete cascade deferrable initially deferred
);

-- Primary keys already cover lookups by owner_id; these cover the
-- foreign keys' referencing side.
create index folders_parent_idx on public.folders (owner_id, parent_id);
create index notes_folder_idx on public.notes (owner_id, folder_id);
create index notes_tags_tag_idx on public.notes_tags (owner_id, tag_id);

-- ---------------------------------------------------------------------
-- Row Level Security — owner-only for this pass
-- ---------------------------------------------------------------------

alter table public.folders enable row level security;
alter table public.tags enable row level security;
alter table public.notes enable row level security;
alter table public.notes_tags enable row level security;

create policy "Owner can manage their folders" on public.folders
  for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy "Owner can manage their tags" on public.tags
  for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy "Owner can manage their notes" on public.notes
  for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy "Owner can manage their notes_tags" on public.notes_tags
  for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

revoke all on public.folders, public.tags, public.notes, public.notes_tags from anon;
grant select, insert, update, delete
  on public.folders, public.tags, public.notes, public.notes_tags
  to authenticated;

-- ---------------------------------------------------------------------
-- push_changes — the app's only write path (noote-plan.md §4: no direct
-- table writes from client code).
--
-- p_changes is a JSON array of
--   {"table": "folders"|"tags"|"notes"|"notes_tags",
--    "op": "upsert"|"delete",
--    "id": "<row id>",
--    "row": {<column>: <value>, ...}}
-- where "row" holds the full current row for upserts (and note_id/tag_id
-- for notes_tags deletes). owner_id is never read from the payload — it's
-- always auth.uid().
--
-- Runs as the caller (SECURITY INVOKER), so the RLS policies above still
-- apply. The whole call is one transaction: if any change fails, none are
-- kept and the app leaves its outbox untouched.
--
-- Notes and folders are only overwritten when the incoming updated_at is
-- at least as new as the stored one, so a device with stale data can't
-- overwrite newer edits; those are counted in the returned "skipped".
-- Deletes are real deletes (a note deleted forever on one device mustn't
-- come back into the trash on the next download). Moving a note to the
-- trash is an upsert with is_deleted = true, not a delete.
-- ---------------------------------------------------------------------

create or replace function public.push_changes(p_changes jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_change jsonb;
  v_table text;
  v_id text;
  v_row jsonb;
  v_count integer;
  v_applied integer := 0;
  v_skipped integer := 0;
begin
  if v_uid is null then
    raise exception 'push_changes: not signed in' using errcode = '42501';
  end if;
  if jsonb_typeof(p_changes) is distinct from 'array' then
    raise exception 'push_changes: p_changes must be a JSON array' using errcode = '22023';
  end if;

  for v_change in select value from jsonb_array_elements(p_changes) loop
    v_table := v_change ->> 'table';
    v_id := v_change ->> 'id';
    v_row := coalesce(v_change -> 'row', '{}'::jsonb);

    if v_change ->> 'op' = 'delete' then
      case v_table
        when 'folders' then
          delete from public.folders where owner_id = v_uid and id = v_id;
        when 'tags' then
          delete from public.tags where owner_id = v_uid and id = v_id;
        when 'notes' then
          delete from public.notes where owner_id = v_uid and id = v_id;
        when 'notes_tags' then
          delete from public.notes_tags
          where owner_id = v_uid
            and note_id = v_row ->> 'note_id'
            and tag_id = v_row ->> 'tag_id';
        else
          raise exception 'push_changes: unknown table "%"', v_table using errcode = '22023';
      end case;
      v_applied := v_applied + 1;
      continue;
    end if;

    if v_change ->> 'op' is distinct from 'upsert' then
      raise exception 'push_changes: unknown op "%"', v_change ->> 'op' using errcode = '22023';
    end if;

    case v_table
      when 'folders' then
        insert into public.folders as f
          (owner_id, id, name, parent_id, updated_at, is_deleted)
        values (
          v_uid,
          v_id,
          v_row ->> 'name',
          v_row ->> 'parent_id',
          (v_row ->> 'updated_at')::timestamptz,
          coalesce((v_row ->> 'is_deleted')::boolean, false)
        )
        on conflict (owner_id, id) do update set
          name = excluded.name,
          parent_id = excluded.parent_id,
          updated_at = excluded.updated_at,
          is_deleted = excluded.is_deleted
        where f.updated_at <= excluded.updated_at;

      when 'tags' then
        insert into public.tags as t (owner_id, id, name)
        values (v_uid, v_id, v_row ->> 'name')
        on conflict (owner_id, id) do update set name = excluded.name;

      when 'notes' then
        insert into public.notes as n
          (owner_id, id, folder_id, title, title_style_json, body_json,
           created_at, updated_at, is_deleted, deleted_at)
        values (
          v_uid,
          v_id,
          v_row ->> 'folder_id',
          coalesce(v_row ->> 'title', ''),
          coalesce(v_row -> 'title_style_json', '[]'::jsonb),
          v_row -> 'body_json',
          (v_row ->> 'created_at')::timestamptz,
          (v_row ->> 'updated_at')::timestamptz,
          coalesce((v_row ->> 'is_deleted')::boolean, false),
          (v_row ->> 'deleted_at')::timestamptz
        )
        on conflict (owner_id, id) do update set
          folder_id = excluded.folder_id,
          title = excluded.title,
          title_style_json = excluded.title_style_json,
          body_json = excluded.body_json,
          updated_at = excluded.updated_at,
          is_deleted = excluded.is_deleted,
          deleted_at = excluded.deleted_at
        where n.updated_at <= excluded.updated_at;

      when 'notes_tags' then
        insert into public.notes_tags (owner_id, note_id, tag_id)
        values (v_uid, v_row ->> 'note_id', v_row ->> 'tag_id')
        on conflict do nothing;

      else
        raise exception 'push_changes: unknown table "%"', v_table using errcode = '22023';
    end case;

    get diagnostics v_count = row_count;
    if v_count = 0 and v_table in ('folders', 'notes') then
      v_skipped := v_skipped + 1;
    else
      v_applied := v_applied + 1;
    end if;
  end loop;

  return jsonb_build_object('applied', v_applied, 'skipped', v_skipped);
end;
$$;

revoke all on function public.push_changes(jsonb) from public, anon;
grant execute on function public.push_changes(jsonb) to authenticated;
