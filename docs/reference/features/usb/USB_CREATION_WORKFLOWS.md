# USB Creation Workflows Contract

## Core Rule

Start path is destructive and must require explicit confirmation.
Workflow selection must respect analyzed compatibility flags.

## Workflow Families

- Standard `createinstallmedia` path
- Legacy restore-style path
- Mavericks restore path
- PPC dedicated formatting/restore path
- Catalina and Sierra dedicated handling where required
- Linux raw-copy path (`dd`)

Linux raw-copy stages:
- `linux_unmount_target` — target USB unmount (indeterminate stage),
- `linux_raw_copy` — raw image copy to whole disk (`/dev/rdiskX`) with progress + write speed,
- `cleanup_temp` — deterministic temp cleanup,
- `finalize` — terminal state transition.

## Helper and Privilege Invariants

- Privileged operations must run through helper (`SMAppService + XPC`).
- No terminal fallback privileged execution path.
- Stage progression shown in UI must remain deterministic.
- Linux raw-copy must target whole-disk device, never a partition node.

## Power Management Invariant

- Idle sleep is blocked for the full USB creation runtime.
- Sleep blocker is activated at creation process start.
- Sleep blocker is released on every terminal path: success, failure, and cancellation.

## Logging and Diagnostics

Creation workflow logs should include:
- branch selection reason,
- stage transitions,
- helper progress mapping,
- cancellation/failure shaping,
- critical command outcomes used for diagnosis.

Linux workflow logs should additionally include:
- source image path and size,
- resolved target whole-disk identifier,
- raw-copy progress and speed metrics,
- terminal result (`success/fail/cancel`) and failed stage when present.

## Update Trigger

Update when stage sequencing, branching, or helper interaction semantics change.
