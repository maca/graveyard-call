-- Migration: Add download function for serving files via PostgREST RPC
-- Usage: GET /rpc/download?submission_id=123 (accepts any Accept header)

-- Create domain type for any media type handler (in graveyard schema for PostgREST visibility)
DO $$
BEGIN
    CREATE DOMAIN graveyard."*/*" AS bytea;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- Drop existing function if return type changed
DROP FUNCTION IF EXISTS graveyard.download(int);

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

    -- Set response headers for PostgREST
    PERFORM set_config('response.headers',
        format('[{"Content-Type": "%s"}, {"Content-Disposition": "attachment; filename=\"%s\""}]',
            rec.file_mime_type,
            replace(rec.file_name, '"', '\"')
        ),
        true
    );

    -- File data is stored as base64 in bytea, decode to raw binary
    RETURN decode(encode(rec.file, 'escape'), 'base64');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Only admin can download files
GRANT EXECUTE ON FUNCTION graveyard.download(int) TO admin;
