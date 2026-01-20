-- +goose Up
-- +goose StatementBegin
DO $$
BEGIN
    CREATE ROLE authenticator LOGIN NOINHERIT NOCREATEDB NOCREATEROLE NOSUPERUSER;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
-- +goose StatementEnd

-- +goose StatementBegin
DO $$
BEGIN
    CREATE ROLE anonymous NOLOGIN;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
-- +goose StatementEnd

-- +goose StatementBegin
DO $$
BEGIN
    CREATE ROLE submitter NOLOGIN;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
-- +goose StatementEnd

-- +goose StatementBegin
DO $$
BEGIN
    CREATE ROLE admin NOLOGIN;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
-- +goose StatementEnd

-- +goose Down
DROP ROLE IF EXISTS admin;
DROP ROLE IF EXISTS submitter;
DROP ROLE IF EXISTS anonymous;
DROP ROLE IF EXISTS authenticator;
