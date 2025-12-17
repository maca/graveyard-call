-- Users table
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Submissions table
CREATE TABLE IF NOT EXISTS submissions (
    id SERIAL PRIMARY KEY,
    email TEXT NOT NULL,
    name TEXT NOT NULL,
    comment TEXT,
    file BYTEA,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Login function
CREATE OR REPLACE FUNCTION login(email text, password text)
RETURNS json AS $$
DECLARE
  _user users;
  jwt_token text;
BEGIN
  SELECT * INTO _user FROM users WHERE users.email = login.email;

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
      'role', 'web_anon',
      'user_id', _user.id,
      'email', _user.email,
      'exp', extract(epoch from now() + interval '4 hours')::integer
    ),
    'DL+P8+muauKgOSqRKqIKMkjcUpLZ5ajXScgA965i/Bg='
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

-- Insert test user
INSERT INTO users (email, password) VALUES ('user@example.com', crypt('password', gen_salt('bf')))
ON CONFLICT (email) DO NOTHING;

-- Grant permissions
GRANT EXECUTE ON FUNCTION login(text, text) TO web_anon;
GRANT web_anon TO authenticator;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO web_anon;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO web_anon;

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO web_anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO web_anon;
