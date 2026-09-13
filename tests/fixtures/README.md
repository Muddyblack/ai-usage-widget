# Recorded test inputs

- Provider envelopes are used for normalization and rendering.
- `*-response.json` files contain recorded API responses for collector tests.
- `muse-quota.json` is an HTTP response exercised by `test_muse.py`.

Keep recorded bodies here and behavior assertions in `tests/python/`. Generate
synthetic configs, credentials, catalogs and session logs inside the tests.
No live account or network access is needed for these fixture tests.
