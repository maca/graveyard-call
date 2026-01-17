-- +goose Up
-- +goose StatementBegin
DO $$
BEGIN
    CREATE DOMAIN graveyard."*/*" AS bytea;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;
-- +goose StatementEnd

-- +goose StatementBegin
CREATE OR REPLACE FUNCTION graveyard.download(submission_id int)
RETURNS graveyard."*/*" AS $$
DECLARE
    rec record;
BEGIN
    SELECT file, file_name, file_mime_type
    INTO rec
    FROM graveyard.submissions
    WHERE id = submission_id;

    IF NOT FOUND THEN
        RAISE SQLSTATE 'PGRST' USING
            message = '{"code": "PGRST404", "message": "File not found", "details": "No submission with this ID", "hint": null}',
            detail = '{"status": 404, "headers": {}}';
    END IF;

    PERFORM set_config('response.headers',
        format('[{"Content-Type": "%s"}, {"Content-Disposition": "attachment; filename=\"%s\""}]',
            rec.file_mime_type,
            replace(rec.file_name, '"', '\"')
        ),
        true
    );

    -- File is already binary (decoded on insert), return directly
    RETURN rec.file;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- +goose StatementEnd

-- +goose Down
DROP FUNCTION IF EXISTS graveyard.download(int);
DROP DOMAIN IF EXISTS graveyard."*/*";
