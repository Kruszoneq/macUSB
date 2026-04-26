# Touch Bar Contract

## Goal

The `macUSB` Touch Bar must always display exactly one branding element:
- app icon,
- bold `macUSB` name,
- separator `-`,
- full slogan shared with the `WelcomeView` screen.

## Runtime Contract

- The Touch Bar layout is global for the main app window and pinned to the left side.
- The Touch Bar content does not change between views or workflow stages.
- No additional buttons, actions, or dynamic elements are rendered.

## Implementation

- Module: `macUSB/Shared/UI/TouchBar/TouchbarSupport.swift`
- Attachment point: `WindowConfigurator` in `macUSB/App/ContentView.swift`
- Shared branding text source: `macUSB/Features/Welcome/AppBranding.swift`
