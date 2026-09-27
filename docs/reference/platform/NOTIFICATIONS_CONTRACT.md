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

The notification permission manager and completion-notification path do not currently emit notification-specific diagnostic lines. Permission state transitions, policy-level allow/deny decisions, and completion-notification attempts are therefore not recorded in the exported app log.

## Update Trigger

Update when permission flow, gating rules, or notification policy changes.
