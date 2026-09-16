# Recorded test inputs

- Provider envelopes are used for normalization and rendering.
- Claude/OpenAI envelopes with organization usage carry explicit `inputs.pricing`
  rates so replay never depends on a live catalog or the machine's pricing cache.
- `*-response.json` files contain recorded API responses for collector tests.
- `muse-quota.json` is an HTTP response exercised by `test_muse.py`.
- `ollama-success.json` is synthetic, based on the publicly reported usage
  response shape; it has not been recorded from a live test account.

Keep recorded bodies here and behavior assertions in `tests/python/`. Generate
synthetic configs, credentials, catalogs and session logs inside the tests.
No live account or network access is needed for these fixture tests.
