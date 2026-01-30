-- +goose Up
REVOKE EXECUTE ON FUNCTION graveyard.download(int) FROM PUBLIC;

-- +goose Down
GRANT EXECUTE ON FUNCTION graveyard.download(int) TO PUBLIC;
