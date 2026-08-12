# Release tree fingerprints

Identify a previously cataloged Fusebase Flow tree from a manifest already installed in your
repository. No upgrade is required.

**Self-reference limit:** a tagged tree cannot contain its own fingerprint row. Adding that row
changes the manifest digest being identified. A release's row therefore appears in the next
release and, when available, in an external index.

**Preferred — managed content:**

```bash
python3 -c "import json;print(json.load(open('audit/managed-content-manifest.json'))['manifest_self_sha256'])"
```

**Fallback — hook layer.** Use this if the command above raises `FileNotFoundError`:

```bash
python3 -c "import json;print(json.load(open('audit/hook-layer-manifest.json'))['manifest_self_sha256'])"
```

`audit/managed-content-manifest.json` can be **absent on exactly the installs this table is for**.
An upgrade performed by a pre-4.7.0 engine used a hardcoded top-level file list that omitted newly
added files, so a repository upgraded that way never received it. That was finding F1, fixed in
v4.8.0 by making the content list manifest-driven (`upgrade.sh` → `list-managed --files`) — but the
fix cannot retroactively deliver the file, and the next upgrade is what installs it.
`audit/hook-layer-manifest.json` has shipped far longer and carries the identical field, so it
resolves those installs. Reported by a consumer whose install had exactly this gap.

Match your output to either fingerprint column below; both identify the same tree.

| Release / tree | `VERSION` | managed-content `manifest_self_sha256` | assets | hook-layer `manifest_self_sha256` | assets |
|---|---:|---|---:|---|---:|
| `v4.7.0` earlier target `664503b` | 4.7.0 | `f73edc0f6aec96176274859a98c118c6d0daf16f1bf202c0fe6fd0c9018f8149` | 279 | `feb9d19ef2c890a2523ee32f08ec097d6ef8a03db6f74653f08e5712e54d16ae` | 134 |
| `v4.7.0` current target `bad4d92` | 4.7.0 | `d929ac3a5203199e5000260a1f7d7a828e7d6162a5e75063533f7c8ae04cd478` | 286 | `6595d0977ce9a983a4ce3fbc1441ae7e0f7bdbf6c22b9bd838786ea9c9cb0b91` | 140 |
| `v4.8.0` target `20fd707` | 4.8.0 | `8d81303e329320ae8e9437394370cb9a4044f15392a3b2b96eae49cc2a0371c2` | 305 | `df4a04f7cc5b673725feed031870fa53dcc46e592f93a2abe6976a36f2a5e787` | 156 |
| `v4.9.0` | 4.9.0 | `d514dd1c1888c76ec15cd711826231a25bfdf4239bf6a87dbcbfe9733e55b348` | 313 | `3a4881fe01bec0ad4439e3c5a1c17097151ceb352001eb55f1eee9b232830e35` | 164 |

`v4.9.0` is an unpublished tagged tree: its release workflow failed on 2026-08-12 and published
nothing. The row identifies the immutable tag target; it is not evidence of publication.

Every value above is read from the tagged tree, never transcribed by hand. Regenerate them with
`hooks/local/print-release-fingerprints.sh <ref>…`; a hand-typed hook-layer count in the first
revision of this table was wrong (203 instead of 156) and a consumer propagated it.

The two 4.7.0 rows share a `VERSION` because the `v4.7.0` tag was moved from `664503b` to
`bad4d92`. Their fingerprints distinguish the trees; the lookup does not itself detect a moved tag.

This is a lookup table, not a guarantee that tags will remain immutable. The immutability policy
and its not-yet-complete enforcement are documented in
[`PUBLISHING.md`](../PUBLISHING.md#published-tag-immutability-policy).
