-- Create private storage bucket for path photos
insert into storage.buckets (id, name, public)
values ('path-photos', 'path-photos', false)
on conflict (id) do nothing;

-- Users can only access objects under their own user_id folder
create policy "users manage own photos"
  on storage.objects for all
  using (
    bucket_id = 'path-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  )
  with check (
    bucket_id = 'path-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
