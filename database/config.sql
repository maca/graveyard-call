-- Database configuration settings
-- This file contains sensitive configuration that should not be committed to version control

-- Set JWT secret as a database configuration parameter
-- This should match the jwt-secret in PostgREST configuration
ALTER DATABASE graveyard SET app.jwt_secret = 'DL+P8+muauKgOSqRKqIKMkjcUpLZ5ajXScgA965i/Bg=';
