-- Run these commands periodically (e.g. every hour, or every day depending
-- on activity) to maintain database performance and detect bugs.
VACUUM;
ANALYZE;
PRAGMA integrity_check;
PRAGMA foreign_key_check;
PRAGMA optimize;
