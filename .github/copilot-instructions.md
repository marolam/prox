# Prox Copilot Safety Instructions

Before making release, build, routing, HomeShell, Prox Circle, onboarding, policy, or Pro Mode changes, run or explicitly account for:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\scripts\safe_update_gate.ps1 -CreateSnapshot -CheckLocalCanonicalApk
```

Protect the tester-approved rollback release:

- Safe rollback tag: `v1.0`
- Safe rollback APK SHA-256: `ac7c2a184cbdf73bca9681a042efcbf92d0a414a7ca8948bb36df5b37d10c023`
- Verify with:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\scripts\verify_safe_rollback_release.ps1 -CheckLocalCanonicalApk
```

Rules for AI-assisted changes:

- Do not publish, clobber, or mark a new latest release until the rollback verifier passes.
- Do not continue from unresolved Git conflicts (`git ls-files -u` must be empty).
- Keep Prox Circle/HomeShell changes small and separately verified.
- Keep Pro Mode preview gated to `marty.marola@hotmail.com`; run `R5 Pro Preview: Build + Install` before any broader install/publish when recovering Pro features.
- Prefer one focused feature, then analyzer/tests, then device install, then release only after confirmation.
- If `v1.0` must ever be replaced, require explicit user confirmation and use `-AllowOverwriteSafeRollback` intentionally.
