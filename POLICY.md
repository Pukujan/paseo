# Policy

## Test on a separate instance before touching live (Alex, 2026-10-04)

Applies to every agent and every live service (Paseo on port 6767, the LiteLLM proxy, launchers, daemons).

1. Never apply an untested change to a live service.
2. Test every change on a separate test instance first: a different port, a separate home/config folder, and its own copies of files (not pnpm hardlinks or shared installs).
3. Copy the live config into the test instance, so config or schema changes are tested too.
4. Apply it to live only after the test instance starts cleanly and passes the checks.
5. Back up first, keep a one-step rollback, and roll back right away if live fails.
6. Stop the test instance once you're done.
