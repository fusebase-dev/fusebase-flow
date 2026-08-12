# Release tree fingerprints

Identify the exact managed Fusebase Flow tree you hold with one command against the manifest that
is already installed in your repository; no upgrade is required:

```bash
python3 -c "import json;print(json.load(open('audit/managed-content-manifest.json'))['manifest_self_sha256'])"
```

Match the output to `manifest_self_sha256` below.

| Release / tree | `VERSION` | `manifest_self_sha256` | Managed assets | Hook-layer assets |
|---|---:|---|---:|---:|
| `v4.7.0` earlier target `664503b` | 4.7.0 | `f73edc0f6aec96176274859a98c118c6d0daf16f1bf202c0fe6fd0c9018f8149` | 279 | 134 |
| `v4.7.0` current target `bad4d92` | 4.7.0 | `d929ac3a5203199e5000260a1f7d7a828e7d6162a5e75063533f7c8ae04cd478` | 286 | 140 |
| `v4.8.0` target `20fd707` | 4.8.0 | `8d81303e329320ae8e9437394370cb9a4044f15392a3b2b96eae49cc2a0371c2` | 305 | 203 |

The two 4.7.0 rows share a `VERSION` because the `v4.7.0` tag was moved from `664503b` to
`bad4d92`. Their fingerprints distinguish the managed trees; the lookup does not itself detect a
moved tag.

This is a lookup table, not a guarantee that tags will remain immutable. The immutability policy
and its not-yet-complete enforcement are documented in
[`PUBLISHING.md`](../PUBLISHING.md#published-tag-immutability-policy).
