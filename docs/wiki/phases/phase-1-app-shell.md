# Phase 1: native app shell

## Problem

Before any knowledge or model feature can be useful, MacBrain needs a system-level home that behaves predictably beside other macOS apps.

## Treatment

The app uses SwiftUI for content and isolates AppKit panel lifecycle in `SidebarPanelController`. Geometry, edge selection, click shielding, and activation-bar behavior are modeled in focused helpers instead of implicit view layout rules.

## Verification and boundary

Panel, geometry, overlay-policy, activation-bar, and display-metric tests exercise deterministic policy. Manual multi-display, Spaces, focus, and physical shortcut acceptance remains required because those behaviors depend on the running macOS session.
