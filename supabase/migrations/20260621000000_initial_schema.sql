-- PathRecorder initial schema
-- Mirrors the local model: RecordedPath > PathSegment > GPSLocation, PathPhoto

-- ============================================================
-- Tables
-- ============================================================

create table if not exists paths (
  id          uuid primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  name        text not null,
  created_at  timestamptz not null default now()
);

create table if not exists path_segments (
  id       uuid primary key,
  path_id  uuid not null references paths(id) on delete cascade
);

create table if not exists gps_locations (
  id          uuid primary key,
  segment_id  uuid not null references path_segments(id) on delete cascade,
  latitude    double precision not null,
  longitude   double precision not null,
  timestamp   timestamptz not null
);

create table if not exists path_photos (
  id            uuid primary key,
  user_id       uuid not null references auth.users(id) on delete cascade,
  location_id   uuid not null references gps_locations(id) on delete cascade,
  timestamp     timestamptz not null,
  storage_path  text not null  -- key into the 'path-photos' Storage bucket
);

-- ============================================================
-- Indexes
-- ============================================================

create index if not exists path_segments_path_id_idx   on path_segments(path_id);
create index if not exists gps_locations_segment_id_idx on gps_locations(segment_id);
create index if not exists path_photos_location_id_idx  on path_photos(location_id);

-- ============================================================
-- Row-Level Security
-- ============================================================

alter table paths          enable row level security;
alter table path_segments  enable row level security;
alter table gps_locations  enable row level security;
alter table path_photos    enable row level security;

create policy "users manage own paths"
  on paths for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "users manage own segments"
  on path_segments for all
  using (
    path_id in (select id from paths where user_id = auth.uid())
  )
  with check (
    path_id in (select id from paths where user_id = auth.uid())
  );

create policy "users manage own locations"
  on gps_locations for all
  using (
    segment_id in (
      select ps.id from path_segments ps
      join paths p on p.id = ps.path_id
      where p.user_id = auth.uid()
    )
  )
  with check (
    segment_id in (
      select ps.id from path_segments ps
      join paths p on p.id = ps.path_id
      where p.user_id = auth.uid()
    )
  );

create policy "users manage own photos"
  on path_photos for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ============================================================
-- Storage bucket for photo binaries
-- ============================================================
-- Run this once in the Supabase dashboard or via the Management API,
-- since storage buckets cannot be created in SQL migrations:
--
--   insert into storage.buckets (id, name, public)
--   values ('path-photos', 'path-photos', false);
--
--   create policy "users manage own photos"
--     on storage.objects for all
--     using  (bucket_id = 'path-photos' and auth.uid()::text = (storage.foldername(name))[1])
--     with check (bucket_id = 'path-photos' and auth.uid()::text = (storage.foldername(name))[1]);
--
-- Objects are stored at: {user_id}/{photo_id}.jpg
