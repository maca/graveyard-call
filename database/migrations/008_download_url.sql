-- +goose Up
ALTER TABLE graveyard.submissions ADD COLUMN download_url VARCHAR;

-- +goose StatementBegin
CREATE OR REPLACE FUNCTION graveyard.set_download_url()
RETURNS TRIGGER AS $$
DECLARE
    headers json;
    host text;
BEGIN
    IF NEW.file IS NOT NULL THEN
        headers := current_setting('request.headers', true)::json;
        host := headers->>'host';
        IF host IS NOT NULL THEN
            NEW.download_url := 'https://' || host || '/api/rpc/download?submission_id=' || NEW.id;
        ELSE
            NEW.download_url := '/api/rpc/download?submission_id=' || NEW.id;
        END IF;
    ELSE
        NEW.download_url := NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- +goose StatementEnd

CREATE TRIGGER set_download_url_on_insert
    BEFORE INSERT ON graveyard.submissions
    FOR EACH ROW
    EXECUTE FUNCTION graveyard.set_download_url();

-- +goose Down
DROP TRIGGER IF EXISTS set_download_url_on_insert ON graveyard.submissions;
DROP FUNCTION IF EXISTS graveyard.set_download_url();
ALTER TABLE graveyard.submissions DROP COLUMN IF EXISTS download_url;
