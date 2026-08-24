# Adaptive Liquid Glass Sidebar Design

## Goal

Redesign the complete Notch Brain sidebar around Apple's Liquid Glass visual system while retaining support for the current macOS 14 deployment target. macOS 26 and later use native Liquid Glass APIs; macOS 14 through 25 use adaptive system materials with matching layout and interaction behavior.

## Compatibility strategy

The package remains deployable to macOS 14. Availability-gated view modifiers select one of two rendering paths without duplicating the sidebar hierarchy:

- macOS 26+: native `glassEffect`, interactive glass treatment for controls, and shared glass grouping where neighboring custom surfaces need coherent refraction.
- macOS 14–25: SwiftUI system materials, vibrancy-friendly foreground styles, restrained strokes, and subtle shadows that preserve the same geometry and hierarchy.

No runtime path uses Cloud services, network access, or third-party UI frameworks.

## Visual hierarchy

### Sidebar shell

- Preserve the right-edge attachment, borderless right side, rounded leading corners, always-on-top panel behavior, and slide-in/slide-out transitions.
- Remove hard-coded purple and black tint overlays that suppress adaptive material behavior.
- Use one primary glass/material surface with a quiet leading-edge outline and minimal shadow.
- Let desktop content influence the material naturally while maintaining readable foreground contrast.

### Header

- Keep the Notch Brain identity, presentation toggle, and close action.
- Use native semantic foreground styles and compact icon-only controls with complete accessibility labels.
- Avoid a separately painted opaque header; rely on the shell material and a subtle separator.

### Conversation

- Keep the welcome state, scrollable conversation, loading state, and local mock responses.
- Assistant messages use a subtle secondary glass/material surface.
- User messages use a semantically tinted glass/material surface with enough contrast to remain distinct without heavy opaque fills.
- Preserve selectable message text and automatic scrolling.

### Composer

- Preserve the compact two-row structure: native text field above, edge-to-edge separator, compact action toolbar below.
- On macOS 26, use an interactive native glass surface for the composer and send control.
- On macOS 14–25, use adaptive material and a low-contrast outline with identical spacing and dimensions.
- Keep Return/Enter submission, attachment placeholder, local-only indicator, clear action, focus behavior, and the compact send button.

## Architecture

Create a focused adaptive styling layer rather than branching entire views:

- `AdaptiveGlassSurface`: view modifier or wrapper selecting native glass or material fallback.
- `AdaptiveGlassRole`: semantic role for shell, composer, assistant message, user message, and prominent action.
- Existing `SidebarView`, `ChatComposer`, and `ChatMessageBubble` apply semantic roles and remain responsible for layout only.

The styling layer owns availability checks, shape, tint, interactivity, fallback material, outline, and shadow. Chat state and message flow remain unchanged.

## Accessibility and motion

- Use semantic foreground styles and preserve readable contrast over changing desktop content.
- Keep full labels for icon-only buttons and visible keyboard focus.
- Respect Reduce Transparency by increasing fallback opacity/contrast where required.
- Respect Reduce Motion by preserving existing non-motion behavior or using opacity where large transitions would be uncomfortable.
- Keep controls compact for macOS while maintaining reliable pointer targets.

## Testing and verification

- Unit-test semantic role configuration independently from availability-specific rendering where practical.
- Verify the project still compiles with macOS 14 as its minimum deployment target.
- Run the complete Swift test suite.
- Build the `.app` bundle through `script/build_and_run.sh --bundle`.
- Launch the bundle as a foreground macOS application.
- Inspect the current runtime path visually for shell transparency, foreground contrast, composer proportions, message readability, right-edge attachment, and unchanged sidebar animation.
- Audit source for duplicated sidebar hierarchies, opaque tint overlays, Cloud/network code, and third-party UI dependencies.

## Non-goals

- No chat backend, model, retrieval, persistence, or indexing changes.
- No changes to sidebar geometry, activation-bar behavior, panel z-order, or application permissions.
- No separate modern and legacy executable targets.
- No attempt to imitate Liquid Glass with custom shaders.
