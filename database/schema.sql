-- Create graveyard schema
CREATE SCHEMA graveyard;

-- Create roles
CREATE ROLE authenticator LOGIN NOINHERIT NOCREATEDB NOCREATEROLE NOSUPERUSER;
CREATE ROLE anonymous NOLOGIN;
CREATE ROLE submitter NOLOGIN;
CREATE ROLE admin NOLOGIN;

-- Create extensions
CREATE EXTENSION pgcrypto CASCADE;
CREATE EXTENSION pgjwt CASCADE;

-- Create tables in graveyard schema
CREATE TABLE graveyard.users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(256) UNIQUE NOT NULL,
    password VARCHAR(256) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);


CREATE TABLE graveyard.submissions (
    id SERIAL PRIMARY KEY,
    email VARCHAR(512),
    name VARCHAR,
    residence VARCHAR,
    story TEXT,
    file BYTEA NOT NULL,
    file_name VARCHAR NOT NULL,
    file_mime_type VARCHAR(128) NOT NULL,
    consent_given BOOLEAN NOT NULL DEFAULT FALSE,
    consent_version VARCHAR(16) NOT NULL DEFAULT 'v1.0',
    jwt_token TEXT UNIQUE,
    created_at TIMESTAMP DEFAULT NOW(),
    CONSTRAINT file_size_limit CHECK (octet_length(file) <= 31457280),
    CONSTRAINT valid_mime_type CHECK (
        file_mime_type IN (
            'image/jpeg',
            'image/png',
            'image/heic',
            'image/heif',
            'video/mp4',
            'video/quicktime',
            'model/gltf-binary',
            'audio/mpeg',
            'audio/mp4',
            'audio/x-m4a'
        )
    ),
    CONSTRAINT consent_must_be_given CHECK (consent_given = TRUE)
);


CREATE OR REPLACE FUNCTION graveyard.login(email text, password text)
RETURNS json AS $$
DECLARE
  _user graveyard.users;
  jwt_token text;
BEGIN
  SELECT * INTO _user FROM graveyard.users WHERE graveyard.users.email = login.email;

  IF _user.id IS NULL THEN
    RAISE SQLSTATE 'PGRST' USING
      message = '{"code": "PGRST401", "message": "Invalid email or password", "details": "Authentication failed", "hint": "Please check your credentials"}',
      detail = '{"status": 401, "headers": {}}';
  END IF;

  IF _user.password != crypt(login.password, _user.password) THEN
    RAISE SQLSTATE 'PGRST' USING
      message = '{"code": "PGRST401", "message": "Invalid email or password", "details": "Authentication failed", "hint": "Please check your credentials"}',
      detail = '{"status": 401, "headers": {}}';
  END IF;

  jwt_token := sign(
    json_build_object(
      'role', 'admin',
      'user_id', _user.id,
      'email', _user.email,
      'exp', extract(epoch from now() + interval '4 hours')::integer
    ),
    current_setting('app.jwt_secret')
  );

  RETURN json_build_object(
    'token', jwt_token,
    'user', json_build_object(
      'id', _user.id,
      'email', _user.email
    )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


CREATE OR REPLACE FUNCTION graveyard.submission_jwt()
RETURNS json AS $$
DECLARE
  jwt_token text;
BEGIN
  jwt_token := sign(
    json_build_object(
      'role', 'submitter',
      'jti', gen_random_uuid()::text,
      'exp', extract(epoch from now() + interval '1 hour')::integer
    ),
    current_setting('app.jwt_secret')
  );

  RETURN json_build_object('token', jwt_token);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Trigger function to capture JWT claims on insert
CREATE OR REPLACE FUNCTION graveyard.capture_jwt_token()
RETURNS TRIGGER AS $$
DECLARE
  jwt_claims text;
BEGIN
  -- Capture the JWT claims from the request context
  jwt_claims := current_setting('request.jwt.claims', true);
  -- Hash the JWT token using SHA256 before storing
  NEW.jwt_token := encode(digest(jwt_claims, 'sha256'), 'hex');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger on submissions table
CREATE TRIGGER capture_jwt_on_insert
  BEFORE INSERT ON graveyard.submissions
  FOR EACH ROW
  EXECUTE FUNCTION graveyard.capture_jwt_token();


-- Insert test user
INSERT INTO graveyard.users (email, password) VALUES ('user@example.com', crypt('password', gen_salt('bf')))
ON CONFLICT (email) DO NOTHING;


-- Grant roles to authenticator
GRANT anonymous TO authenticator WITH INHERIT FALSE, SET TRUE;
GRANT submitter TO authenticator WITH INHERIT FALSE, SET TRUE;
GRANT admin TO authenticator WITH INHERIT FALSE, SET TRUE;

-- Grant execute on functions to anonymous users
GRANT EXECUTE ON FUNCTION graveyard.login(text, text) TO anonymous;
GRANT EXECUTE ON FUNCTION graveyard.submission_jwt() TO anonymous;

-- Grant usage on graveyard schema
GRANT USAGE ON SCHEMA graveyard TO anonymous, submitter, admin;

-- Anonymous user permissions for submissions table
-- Can SELECT only the 'name' column
GRANT SELECT (name) ON graveyard.submissions TO anonymous;

-- Submitter role permissions for submissions table
-- Can INSERT new submissions and read name column
GRANT INSERT ON graveyard.submissions TO submitter;
GRANT SELECT (name) ON graveyard.submissions TO submitter;
-- Grant usage on sequences for INSERT operations
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA graveyard TO submitter;

-- Admin role permissions - full access to all tables in graveyard schema
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA graveyard TO admin;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA graveyard TO admin;

-- Set default privileges for future tables in graveyard schema
ALTER DEFAULT PRIVILEGES IN SCHEMA graveyard GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA graveyard GRANT USAGE, SELECT ON SEQUENCES TO admin;
