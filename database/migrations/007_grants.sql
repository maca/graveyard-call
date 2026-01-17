-- +goose Up
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
GRANT SELECT (name) ON graveyard.submissions TO anonymous;

-- Submitter role permissions for submissions table
GRANT INSERT ON graveyard.submissions TO submitter;
GRANT SELECT (name) ON graveyard.submissions TO submitter;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA graveyard TO submitter;

-- Admin role permissions - full access to all tables in graveyard schema
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA graveyard TO admin;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA graveyard TO admin;
GRANT EXECUTE ON FUNCTION graveyard.download(int) TO admin;

-- Set default privileges for future tables in graveyard schema
ALTER DEFAULT PRIVILEGES IN SCHEMA graveyard GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA graveyard GRANT USAGE, SELECT ON SEQUENCES TO admin;

-- +goose Down
ALTER DEFAULT PRIVILEGES IN SCHEMA graveyard REVOKE SELECT, INSERT, UPDATE, DELETE ON TABLES FROM admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA graveyard REVOKE USAGE, SELECT ON SEQUENCES FROM admin;

REVOKE EXECUTE ON FUNCTION graveyard.download(int) FROM admin;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA graveyard FROM admin;
REVOKE ALL ON ALL TABLES IN SCHEMA graveyard FROM admin;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA graveyard FROM submitter;
REVOKE ALL ON graveyard.submissions FROM submitter;
REVOKE ALL ON graveyard.submissions FROM anonymous;
REVOKE USAGE ON SCHEMA graveyard FROM anonymous, submitter, admin;
REVOKE EXECUTE ON FUNCTION graveyard.submission_jwt() FROM anonymous;
REVOKE EXECUTE ON FUNCTION graveyard.login(text, text) FROM anonymous;
REVOKE admin FROM authenticator;
REVOKE submitter FROM authenticator;
REVOKE anonymous FROM authenticator;
