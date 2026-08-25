# settings_spotlight_mockup

A category-first redesign of Debrify Settings in the same Spotlight language as
the new onboarding flow.

Open `index.html` directly in a browser. The wide frame is interactive:

- click a category to switch panes;
- use `Up` / `Down` in the rail, `Right` to enter the pane, and `Left` to return;
- press `/` or click Search to open the search treatment;
- switch between TV/desktop and phone with the controls above the frame.

The mock uses the shipped Spotlight palette (`#0D1420` ground, `#151D2A`
raised surface, `#E23D4C` accent) and borrows onboarding's mono eyebrow,
inverse focus, low-contrast cards, and stable left-side hierarchy. It changes
information architecture rather than settings behavior: existing destinations
remain represented, but the phone root no longer renders every control in one
very long page.

## Intent

| Current settings | This mock |
|---|---|
| Purple ambient wash over generic grouped lists | Spotlight navy room with hueless translucent surfaces |
| Long phone page containing every setting | Category dashboard, then a short detail page |
| TV rail and content read as separate legacy panels | One continuous stage with the same hierarchy as onboarding |
| Every row has equal visual weight | Connection health and the active Look get summary treatment |
| Focus relies on borders and accent tint | White inverse focus with lift and soft specular glare |

This is a design artifact only; it does not change Flutter production code.
