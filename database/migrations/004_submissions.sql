-- +goose Up
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

-- +goose StatementBegin
CREATE OR REPLACE FUNCTION graveyard.decode_file_on_insert()
RETURNS TRIGGER AS $$
BEGIN
    NEW.file := decode(encode(NEW.file, 'escape'), 'base64');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- +goose StatementEnd

CREATE TRIGGER decode_file_before_insert
    BEFORE INSERT ON graveyard.submissions
    FOR EACH ROW
    EXECUTE FUNCTION graveyard.decode_file_on_insert();

-- +goose StatementBegin
CREATE OR REPLACE FUNCTION graveyard.capture_jwt_token()
RETURNS TRIGGER AS $$
DECLARE
    jwt_claims text;
BEGIN
    jwt_claims := current_setting('request.jwt.claims', true);
    NEW.jwt_token := encode(digest(jwt_claims, 'sha256'), 'hex');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- +goose StatementEnd

CREATE TRIGGER capture_jwt_on_insert
    BEFORE INSERT ON graveyard.submissions
    FOR EACH ROW
    EXECUTE FUNCTION graveyard.capture_jwt_token();

-- +goose Down
DROP TRIGGER IF EXISTS capture_jwt_on_insert ON graveyard.submissions;
DROP TRIGGER IF EXISTS decode_file_before_insert ON graveyard.submissions;
DROP FUNCTION IF EXISTS graveyard.capture_jwt_token();
DROP FUNCTION IF EXISTS graveyard.decode_file_on_insert();
DROP TABLE IF EXISTS graveyard.submissions;
