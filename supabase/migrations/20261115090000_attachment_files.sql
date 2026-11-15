-- Attachments can be any kind of file now (PDFs, recordings, …), not just
-- images; the app shows non-images as file blocks. Still 50 MB per file,
-- and still only the owner can read or write (policies unchanged, see
-- 20261110090000_attachments.sql).
update storage.buckets
set allowed_mime_types = null
where id = 'attachments';
