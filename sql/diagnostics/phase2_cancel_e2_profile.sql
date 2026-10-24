-- Cancel only the current E2 profile backend on the disposable report clone.
SELECT pg_cancel_backend(548);
