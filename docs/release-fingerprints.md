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
| `v4.7.1` | 4.7.1 | `bd281972043d1eb9f9f42a65d2f7759e831ec0c06ec2e7d54d215c05dba7ce6d` | 287 | `5f77a4eefae40466ad02d904a0253c56b6c3a61f184376881da1e2c292447213` | 141 |
| `v4.8.0` target `20fd707` | 4.8.0 | `8d81303e329320ae8e9437394370cb9a4044f15392a3b2b96eae49cc2a0371c2` | 305 | `df4a04f7cc5b673725feed031870fa53dcc46e592f93a2abe6976a36f2a5e787` | 156 |
| `v4.9.0` | 4.9.0 | `d514dd1c1888c76ec15cd711826231a25bfdf4239bf6a87dbcbfe9733e55b348` | 313 | `3a4881fe01bec0ad4439e3c5a1c17097151ceb352001eb55f1eee9b232830e35` | 164 |
| `v4.9.1` | 4.9.1 | `ed4fc0cd755fa10707d5de8b6480dda2086840db5ecd3c30e4e56617ef644120` | 314 | `8e561250d35f3cb9a8aa8ab90f0cad454bfa60967a25a73e4c7ece5de1f27be7` | 165 |
| `v4.9.2` | 4.9.2 | `57cae17b7db4ed1cd7e3ac17b4120062abb85e5804f2a386f60c2ba0791c6513` | 315 | `a38e92abaccdeade5ad25a8f3ce16c697f98152654a12c4eccd62c916e4966c2` | 166 |
| `v4.10.0` | 4.10.0 | `fa7bb5cf4a4fefd8e86f35e24555f0dc82daf47e498f24c8b888e5b3fff10f65` | 323 | `faf2199c81ca9c816cb203a4f71892fd8c5353cb931a45d16f33032d70cafbe5` | 174 |
| `v4.10.1` | 4.10.1 | `1e0b4fbab00a6c8578d2773c91c2f370eb2eebc8e57c416237283d9b61b6b2dd` | 323 | `665de96876ad5137f467e8ce247728726e8568a76864708e22b2a4933f55db01` | 174 |
| `v4.11.0` | 4.11.0 | `c0bd8faad60785a62cadce5626e92baa606fbb09547e4352b5fa0ae67a667a82` | 326 | `343031372b215473a388c87c544e308b84e63103ee3e7af6b8c20fde66ca9aca` | 177 |
| `v4.12.0` | 4.12.0 | `cdf2f1470a1f911b6beda7d4a2cdc42f79de947a97d8e1fc4607a70491fef272` | 330 | `e3e1de0bceb53da3eaf6d64e0389e307ff589c026b25652f12d65a9698b199bf` | 181 |

`v4.9.0`, `v4.9.1` and `v4.10.0` are unpublished tagged trees: their release workflows failed
(2026-08-12, 2026-08-13 and 2026-08-15) and published nothing. Each row identifies an immutable tag
target; none is evidence of publication. No tag was moved — `v4.9.2` superseded the first two, and
`v4.10.1` supersedes `v4.10.0`. A tree cloned from `main` during any of those windows is identifiable
here rather than absent from the table.

`v4.10.0` failed for a reason worth recording, because it was self-inflicted: the fingerprint-row
check added in `v4.9.2` read a tag's target with
`--format='%(*objectname)%(objectname)'`, which CONCATENATES the commit and the tag object for an
**annotated** tag. Its self-reference exemption compared that 80-character field against a
40-character `HEAD` and never matched, so the tag being cut always looked like a missing row and no
release could pass its own gate. Its test passed because the fixture built a lightweight tag — a
shape this project never ships. Fixed in `v4.10.1` (prefix comparison, annotated + lightweight rows).

Every value above is read from the tagged tree, never transcribed by hand. Regenerate them with
`hooks/local/print-release-fingerprints.sh <ref>…`; a hand-typed hook-layer count in the first
revision of this table was wrong (203 instead of 156) and a consumer propagated it.

The two 4.7.0 rows share a `VERSION` because the `v4.7.0` tag was moved from `664503b` to
`bad4d92`. Their fingerprints distinguish the trees; the lookup does not itself detect a moved tag.

This is a lookup table, not a guarantee that tags will remain immutable. The immutability policy
and its not-yet-complete enforcement are documented in
[`PUBLISHING.md`](../PUBLISHING.md#published-tag-immutability-policy).
