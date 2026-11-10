-- Attachments (images in notes). The files live in a private Storage bucket
-- under '<owner id>/<attachment id>'; a note's body refers to one as
-- 'attachment://<attachment id>' (lib/data/attachments/ in the app). Each
-- account can only read and write files in its own folder.
--
-- 50 MB per file (the free plan's limit) and images only, for now; other
-- file types are a later migration.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'attachments',
  'attachments',
  false,
  52428800,
  array['image/png', 'image/jpeg', 'image/gif', 'image/webp', 'image/bmp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Uploads use upsert, which needs select + insert + update.
create policy "Owner can read their attachments"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'attachments'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "Owner can add attachments"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'attachments'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "Owner can replace their attachments"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'attachments'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'attachments'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "Owner can delete their attachments"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'attachments'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
