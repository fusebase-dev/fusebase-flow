```text
##### S4a: 4.6.1 consumer, patched hooks/shared/command_policy.py; documented adoption = fetched 4.7.0 bootstrap-upgrade.sh #####
pre-run sha256:
88682ed62e0c67250c0965f41521524f7a77a84a6cfd8dd830de71f8723bbf36 *hooks/shared/command_policy.py

--- bash hooks/local/bootstrap-upgrade.sh --repo <local 4.7.0 repo> --ref fix/msys-v3307-hardening -- --auto-yes ---
[bootstrap-upgrade] Cloning c:/Users/Pavel/projects/fusebase-flow-publish/fusebase-flow-FuseBase CLI edition (fix/msys-v3307-hardening) -> .fusebase-flow-source/ ...
Cloning into '.fusebase-flow-source'...
warning: --depth is ignored in local clones; use file:// instead.
done.
[bootstrap-upgrade] Source VERSION: 4.7.0
[bootstrap-upgrade] synthesized the classifier base from upstream tag v4.6.1 -> audit/managed-content-manifest.json
                    (this is what upstream shipped you at 4.6.1, so the upgrade can now
                     tell YOUR edits from upstream's.)
[bootstrap-upgrade] Handing off to .fusebase-flow-source/hooks/local/upgrade.sh --auto-yes

[upgrade] Source: .fusebase-flow-source/  (HEAD 6224bbe, VERSION 4.7.0)
[upgrade] Local:  VERSION 4.6.1


[upgrade] Managed-content classification:
  current                   220 file(s)
  upstream-only              45 file(s)
  upstream-added             13 file(s)

  changed-by-both (1) — BOTH changed these — cannot be merged automatically:
    - hooks/shared/command_policy.py

[upgrade] Backups of every touched directory: *.pre-upgrade-20260729T003914Z
[upgrade] ABORTED: 'changed-by-both' paths need a human decision and
          --auto-yes must not guess. NOTHING was written.
          Reconcile the files listed above (or take upstream's copy from
          the source clone), then resume with:
    bash hooks/local/upgrade.sh
EXIT=3

--- post-run sha256 ---
88682ed62e0c67250c0965f41521524f7a77a84a6cfd8dd830de71f8723bbf36 *hooks/shared/command_policy.py
--- sentinel count (1 = preserved) ---
1
S4A_DONE_RC=0
```
