# Phase 2: activation and permissions

## Problem

The sidebar must be easy to invoke without making Accessibility, clipboard, filesystem, or other data access invisible.

## Treatment

Activation and live context use explicit models and safeguards. Security-scoped access is handled separately from ordinary connector state; context attachments are visible, bounded, removable, and limited to the relevant request. Denied permissions become recovery state, not an invitation to broaden access.

## Verification and boundary

Context safeguard, source-access, live-Mac, and clean-install tests exercise the app-level contract. TCC and Full Disk Access must be accepted, denied, revoked, and restored on a real user account before release.
