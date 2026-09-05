CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$ BEGIN
  CREATE TYPE user_role AS ENUM ('user', 'gym_admin', 'admin');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE friendship_status AS ENUM ('pending', 'accepted', 'blocked');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE meetup_status AS ENUM ('open', 'full', 'cancelled', 'finished');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE review_status AS ENUM ('pending', 'approved', 'rejected');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  openid text UNIQUE NOT NULL,
  nickname varchar(32) NOT NULL DEFAULT '岩友',
  avatar_url text,
  bio varchar(120),
  profile_completed boolean NOT NULL DEFAULT true,
  role user_role NOT NULL DEFAULT 'user',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Existing accounts stay complete. Auth endpoints explicitly mark new accounts
-- incomplete when the identity provider did not provide usable profile data.
ALTER TABLE users ADD COLUMN IF NOT EXISTS profile_completed boolean NOT NULL DEFAULT true;

-- Monthly summaries become public only after their owner explicitly shares.
-- Keep revocation state for idempotent retries; sharing again rotates the token.
-- Account deletion cascades immediately to every shared monthly summary.
CREATE TABLE IF NOT EXISTS monthly_record_shares (
  token varchar(43) PRIMARY KEY CHECK (token ~ '^[A-Za-z0-9_-]{43}$'),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  month date NOT NULL CHECK (extract(day FROM month)=1),
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  UNIQUE(user_id,month)
);

CREATE TABLE IF NOT EXISTS gym_brands (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name varchar(80) UNIQUE NOT NULL,
  logo_url text,
  description text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS gyms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name varchar(80) NOT NULL,
  city varchar(40) NOT NULL,
  province varchar(40) NOT NULL DEFAULT '广东省',
  district varchar(40),
  brand_id uuid REFERENCES gym_brands(id) ON DELETE SET NULL,
  address varchar(160) NOT NULL,
  latitude numeric(10,7),
  longitude numeric(10,7),
  cover_url text,
  description text,
  verified boolean NOT NULL DEFAULT false,
  source_name text,
  source_url text,
  source_external_id text,
  canonical_venue_id varchar(120),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- A shareable visit-card is user generated until a gym admin connects a real
-- point-of-sale / redemption workflow.  It intentionally carries no payment
-- state, so a card cannot be mistaken for an official membership product.
CREATE TABLE IF NOT EXISTS gym_visit_cards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id uuid NOT NULL REFERENCES gyms(id) ON DELETE CASCADE,
  creator_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title varchar(80) NOT NULL,
  visits_total integer NOT NULL CHECK (visits_total BETWEEN 1 AND 100),
  visits_remaining integer NOT NULL CHECK (visits_remaining BETWEEN 0 AND 100),
  expires_on date,
  note varchar(200),
  status varchar(16) NOT NULL DEFAULT 'open' CHECK (status IN ('open','claimed','expired','cancelled')),
  claimed_by uuid REFERENCES users(id) ON DELETE SET NULL,
  claimed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (visits_remaining <= visits_total)
);

CREATE TABLE IF NOT EXISTS gym_admins (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  gym_id uuid NOT NULL REFERENCES gyms(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(user_id, gym_id)
);

ALTER TABLE gyms ADD COLUMN IF NOT EXISTS district varchar(40);
ALTER TABLE gyms ADD COLUMN IF NOT EXISTS province varchar(40) NOT NULL DEFAULT '广东省';
ALTER TABLE gyms ADD COLUMN IF NOT EXISTS brand_id uuid REFERENCES gym_brands(id) ON DELETE SET NULL;
ALTER TABLE gyms ADD COLUMN IF NOT EXISTS source_name text;
ALTER TABLE gyms ADD COLUMN IF NOT EXISTS source_url text;
ALTER TABLE gyms ADD COLUMN IF NOT EXISTS source_external_id text;
ALTER TABLE gyms ADD COLUMN IF NOT EXISTS canonical_venue_id varchar(120);

CREATE TABLE IF NOT EXISTS route_sets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id uuid NOT NULL REFERENCES gyms(id) ON DELETE CASCADE,
  name varchar(80) NOT NULL,
  starts_on date NOT NULL,
  ends_on date,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS routes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id uuid NOT NULL REFERENCES gyms(id) ON DELETE CASCADE,
  route_set_id uuid REFERENCES route_sets(id) ON DELETE SET NULL,
  name varchar(80) NOT NULL,
  grade varchar(8) NOT NULL CHECK (grade ~ '^V([0-9]|1[0-7])$'),
  color varchar(24) NOT NULL,
  wall_zone varchar(40),
  cover_url text,
  setter_name varchar(40),
  points jsonb NOT NULL DEFAULT '[]'::jsonb,
  published boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sends (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  route_id uuid NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
  attempts integer NOT NULL DEFAULT 1 CHECK (attempts > 0),
  video_url text,
  caption varchar(300),
  visibility varchar(12) NOT NULL DEFAULT 'public' CHECK (visibility IN ('public','friends','private')),
  sent_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, route_id)
);

CREATE TABLE IF NOT EXISTS post_likes (
  send_id uuid NOT NULL REFERENCES sends(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(send_id, user_id)
);

CREATE TABLE IF NOT EXISTS comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  send_id uuid NOT NULL REFERENCES sends(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  content varchar(300) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS friendships (
  requester_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  addressee_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status friendship_status NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(requester_id, addressee_id),
  CHECK(requester_id <> addressee_id)
);

CREATE TABLE IF NOT EXISTS meetups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  gym_id uuid NOT NULL REFERENCES gyms(id) ON DELETE CASCADE,
  title varchar(80) NOT NULL,
  starts_at timestamptz NOT NULL,
  max_people integer NOT NULL DEFAULT 4 CHECK(max_people BETWEEN 2 AND 50),
  note varchar(300),
  status meetup_status NOT NULL DEFAULT 'open',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS meetup_members (
  meetup_id uuid NOT NULL REFERENCES meetups(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  joined_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(meetup_id, user_id)
);

CREATE TABLE IF NOT EXISTS route_submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  submitter_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  client_request_id uuid,
  gym_id uuid NOT NULL REFERENCES gyms(id) ON DELETE CASCADE,
  route_set_id uuid REFERENCES route_sets(id) ON DELETE SET NULL,
  name varchar(80) NOT NULL,
  grade varchar(8) NOT NULL CHECK (grade ~ '^V([0-9]|1[0-7])$'),
  color varchar(24) NOT NULL,
  wall_zone varchar(40),
  cover_url text NOT NULL,
  video_url text,
  caption varchar(300),
  visibility varchar(12) NOT NULL DEFAULT 'public' CHECK (visibility IN ('public','friends','private')),
  points jsonb NOT NULL DEFAULT '[]'::jsonb,
  status review_status NOT NULL DEFAULT 'pending',
  review_note varchar(300),
  reviewer_id uuid REFERENCES users(id) ON DELETE SET NULL,
  published_route_id uuid REFERENCES routes(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_type varchar(16) NOT NULL CHECK(target_type IN ('send','comment','user','meetup','route')),
  target_id uuid NOT NULL,
  reason varchar(32) NOT NULL,
  detail varchar(300),
  status review_status NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(reporter_id,target_type,target_id)
);

CREATE TABLE IF NOT EXISTS notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type varchar(24) NOT NULL,
  title varchar(80) NOT NULL,
  content varchar(200),
  target_path text,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE sends ADD COLUMN IF NOT EXISTS moderation_status review_status NOT NULL DEFAULT 'approved';
ALTER TABLE sends ALTER COLUMN route_id DROP NOT NULL;
ALTER TABLE sends ADD COLUMN IF NOT EXISTS image_urls text[] NOT NULL DEFAULT '{}';
ALTER TABLE comments ADD COLUMN IF NOT EXISTS moderation_status review_status NOT NULL DEFAULT 'approved';
ALTER TABLE route_submissions ADD COLUMN IF NOT EXISTS published_route_id uuid REFERENCES routes(id) ON DELETE SET NULL;
ALTER TABLE route_submissions ADD COLUMN IF NOT EXISTS client_request_id uuid;
ALTER TABLE route_submissions ADD COLUMN IF NOT EXISTS video_url text;
ALTER TABLE route_submissions ADD COLUMN IF NOT EXISTS caption varchar(300);
ALTER TABLE route_submissions ADD COLUMN IF NOT EXISTS visibility varchar(12) NOT NULL DEFAULT 'public';

DO $$ BEGIN
  ALTER TABLE route_submissions
    ADD CONSTRAINT route_submissions_visibility_check
    CHECK (visibility IN ('public','friends','private'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_routes_gym_set ON routes(gym_id, route_set_id);
CREATE INDEX IF NOT EXISTS idx_gyms_city_district_brand ON gyms(city,district,brand_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_gyms_source_external_identity
  ON gyms(source_name,source_external_id)
  WHERE source_name IS NOT NULL AND source_external_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_gyms_canonical_venue_identity
  ON gyms(canonical_venue_id)
  WHERE canonical_venue_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_gym_visit_cards_gym_status ON gym_visit_cards(gym_id,status,created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sends_user_time ON sends(user_id, sent_at DESC);
CREATE INDEX IF NOT EXISTS idx_sends_route ON sends(route_id);
CREATE INDEX IF NOT EXISTS idx_sends_public_feed_cursor
  ON sends(sent_at DESC,id DESC)
  WHERE moderation_status='approved' AND visibility='public';
CREATE INDEX IF NOT EXISTS idx_sends_approved_visibility_cursor
  ON sends(visibility,sent_at DESC,id DESC)
  WHERE moderation_status='approved';
CREATE INDEX IF NOT EXISTS idx_comments_approved_send_time
  ON comments(send_id,created_at)
  WHERE moderation_status='approved';
CREATE INDEX IF NOT EXISTS idx_meetups_gym_time ON meetups(gym_id, starts_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_friendships_pair ON friendships(LEAST(requester_id,addressee_id),GREATEST(requester_id,addressee_id));
CREATE INDEX IF NOT EXISTS idx_route_submissions_status ON route_submissions(status,created_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_route_submissions_idempotency ON route_submissions(submitter_id,client_request_id);
CREATE INDEX IF NOT EXISTS idx_gym_admins_gym ON gym_admins(gym_id,user_id);
CREATE INDEX IF NOT EXISTS idx_reports_status ON reports(status,created_at);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id,created_at DESC);
