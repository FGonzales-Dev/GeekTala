-- Folder order, for drag-to-reorder in the app: a folder's position among
-- the folders with the same parent, ascending. A fraction, so a folder
-- dropped between two others gets the midpoint without renumbering its
-- siblings (see FoldersRepository.moveFolder in the app).

alter table public.folders
  add column sort_order double precision not null default 0;

-- Same as in the initial migration, plus sort_order. An upsert from an
-- older app version that doesn't send sort_order keeps the stored value.
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
          (owner_id, id, name, parent_id, sort_order, updated_at, is_deleted)
        values (
          v_uid,
          v_id,
          v_row ->> 'name',
          v_row ->> 'parent_id',
          coalesce((v_row ->> 'sort_order')::double precision, 0),
          (v_row ->> 'updated_at')::timestamptz,
          coalesce((v_row ->> 'is_deleted')::boolean, false)
        )
        on conflict (owner_id, id) do update set
          name = excluded.name,
          parent_id = excluded.parent_id,
          sort_order = case when v_row ? 'sort_order'
                         then excluded.sort_order else f.sort_order end,
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
