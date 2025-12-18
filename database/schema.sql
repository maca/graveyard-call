-- Drop old login function from public schema if it exists
DROP FUNCTION IF EXISTS public.login(text, text);

-- Drop and recreate graveyard schema first (CASCADE will drop dependent objects)
DROP SCHEMA IF EXISTS graveyard CASCADE;
CREATE SCHEMA graveyard;

-- Drop existing roles if they exist
DROP ROLE IF EXISTS authenticator;
DROP ROLE IF EXISTS anonymous;
DROP ROLE IF EXISTS submitter;
DROP ROLE IF EXISTS admin;

-- Create roles
CREATE ROLE authenticator LOGIN NOINHERIT NOCREATEDB NOCREATEROLE NOSUPERUSER;
CREATE ROLE anonymous NOLOGIN;
CREATE ROLE submitter NOLOGIN;
CREATE ROLE admin NOLOGIN;

-- Create extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto CASCADE;
CREATE EXTENSION IF NOT EXISTS pgjwt CASCADE;

-- Create tables in graveyard schema
CREATE TABLE IF NOT EXISTS graveyard.users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(256) UNIQUE NOT NULL,
    password VARCHAR(256) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);


CREATE TABLE IF NOT EXISTS graveyard.submissions (
    id SERIAL PRIMARY KEY,
    email VARCHAR(256),
    name VARCHAR(256),
    comment TEXT,
    file BYTEA NOT NULL,
    jwt_token TEXT UNIQUE,
    created_at TIMESTAMP DEFAULT NOW()
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
GRANT anonymous TO authenticator;
GRANT submitter TO authenticator;
GRANT admin TO authenticator;

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
