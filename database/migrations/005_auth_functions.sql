-- +goose Up
-- +goose StatementBegin
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
-- +goose StatementEnd

-- +goose StatementBegin
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
-- +goose StatementEnd

-- +goose Down
DROP FUNCTION IF EXISTS graveyard.submission_jwt();
DROP FUNCTION IF EXISTS graveyard.login(text, text);
