# Notifications Contract

## Permission and Trigger Policy

- Notification permission prompting remains user-initiated from menu when state is not determined.
- Delivery depends on both system authorization and app policy.
- Completion notifications remain gated by app active/inactive state rules.

## Current Runtime Behavior

- Notification state/toggle are managed centrally.
- Denied/blocked states route users to system settings.
- Completion notifications fire only when inactive and policy allows.

## Logging and Diagnostics

Notification logs should include:
- permission state transitions,
- policy-level allow/deny decisions,
- emission attempts for completion notifications.

## Update Trigger

Update when permission flow, gating rules, or notification policy changes.
