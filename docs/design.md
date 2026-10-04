# Design Source of Truth

UI/UX reference for this app. Read before implementing any Flutter screen. Reuse what's here before inventing anything new — colors, type, spacing, radii, icons, components.

Not covered here: general Flutter/Dart/accessibility/architecture practice — that's in `CLAUDE.md` and the installed skills.

## Product & flow

Pickup-only grocery app. **No delivery flow, ever.**

Customer journey: **Find → Add → Confirm → Pick up → Pay at store**

- Customer: browse, search/filter, product detail, adjust quantity, place order, track order status, get pickup info, pay in-store.
- Owner: manage products, view/confirm orders, mark ready, hand over, mark uncollected. The order contract (lifecycle, rules) is `orders.md`.
- V1 payment is always at pickup — never design or imply online payment.

## Direction: "Fresh Market Utility"

Personality: fresh · simple · reliable · human · fast. A practical shopping tool, optimized for fast scanning, fast quantity changes, clear order/pickup status, large touch targets, consistency.

**Avoid:** food-delivery aesthetics, luxury/premium styling, generic SaaS look, organic/bio clichés, decorative Dribbble-style UI, unneeded visual complexity.

## Color

| Role | Hex |
|---|---|
| Primary / Market Green | `#2F6B4F` |
| Secondary / Sage | `#4F765F` |
| Accent / Citrus | `#F2B84B` |
| Background / Warm Cream | `#F7F6F0` |
| Surface / White | `#FFFFFF` |
| Primary Text | `#18221C` |
| Secondary Text | `#5E6B62` |
| Success | `#2E7D5B` |
| Warning | `#8A5E00` |
| Error | `#B54747` |
| Disabled | `#A9B0AB` |

Green is the primary brand color, not a fill-everything color. Citrus is accent-only. Prefer neutral surfaces and whitespace. No new brand colors without a concrete reason. No unnecessary gradients.

## Typography

Font: **Inter**, weights 400/500/600/700.

| Style | Size/Weight |
|---|---|
| Display | 28 / 700 |
| H1 | 24 / 700 |
| H2 | 20 / 700 |
| H3 | 18 / 600 |
| Body | 16 / 400 |
| Body Strong | 16 / 600 |
| Secondary | 14 / 400 |
| Label | 14 / 500 |
| Caption | 12 / 500 |
| Price | 20–24 / 700 |

Keep the scale limited — don't add new styles ad hoc.

## Shape

Principle: **soft, not bubbly.**

| Element | Radius |
|---|---|
| Card | 16 |
| Button | 12 |
| Input | 12 |
| Sheet/Dialog | 20 |
| Chip | 999 |
| Badge | 8 |

Subtle borders and restrained elevation over heavy shadows.

## Spacing

Scale: `4 · 8 · 12 · 16 · 20 · 24 · 32 · 40` — no arbitrary values.

- Page padding (mobile): 16
- Component spacing: 12–16
- Section spacing: 24–32
- Primary CTA min height: 48px

## Navigation

Customer: **Home · Categories · Search · Orders · Profile**. Cart always easily reachable. No Delivery/Pickup switch — pickup is the only mode.

Owner: same visual system, denser and more operational.

## Core patterns

**ProductCard** (core component)
- Before adding to cart: `Ajouter` button.
- After adding: `− quantity +` stepper, adjustable directly in the card/list context.
- Hierarchy: name 16/600 · unit metadata 13–14 · price 18–20/700.

**Search** — primary interaction: prominent search bar, suggestions/corrections where useful, filters with visible active-filter state, fast result scanning.

**Cart** — show products, quantity, prices, subtotal, pickup info, payment info. State "Payment: at pickup" clearly. Primary action reads as confirmation, e.g. `Confirm order` — never styled like an online checkout.

**Pickup status** — show store, requested pickup time (advisory, not a slot), order status. Lifecycle (statuses in `orders.md`):
`Order received → Confirmed → Ready for pickup → Collected`, or `Cancelled` (while received or confirmed), or `Uncollected` (after ready). There is no "Preparing" step.
"Ready for pickup" must read unambiguously. "Uncollected" is a calm, distinct state — not styled as an aggressive error. Don't imitate delivery-tracking UI.

## Customer vs Owner

One shared design language, two densities:
- Customer: shopping-first, spacious, visual, product-focused, large touch targets.
- Owner: operations-first, information-dense, status-focused, fast actions, compact lists.

Never split into two separate visual identities.

## Icons & imagery

Icons: Material Symbols Rounded, consistent outlined/lightweight style. Don't mix icon families. No emojis as primary UI icons.

Product imagery: clean, centered, bright, simple, neutral/light background, product-focused. Product cards use product photography; hero/banner imagery (optional) can be lifestyle.

## Motion

Functional only, not decorative. Appropriate: add→quantity transition, cart badge update, order-status transition, skeleton loading. Target ~150–200ms transitions. No decorative/excessive animation.

## States

Every relevant component/screen considers: Loading · Empty · Error · Success · Warning · Disabled · Ready · Uncollected · Cancelled. Never communicate an important state through color alone.

## Accessibility

WCAG 2.2 as the practical guardrail: sufficient contrast, readable type, adequate touch targets, semantic (not color-only) status, keyboard/focus handling where relevant.

## Anti-patterns

Green everywhere · excessive cards / card-in-card nesting · gradients/blobs · oversized decorative type · excessive animation · delivery UI · online-payment framing · too many colors or type styles · arbitrary spacing/radii · mixed icon families · emojis as primary icons · one-off component variants · giant promo banners pushing products below the fold.

## How to use this file

1. Treat this as the UI/UX source of truth before any Flutter screen work.
2. Reuse existing visual language and shared components before creating new ones.
3. Don't invent new colors/type/spacing/radii/icon styles without a concrete reason.
4. Keep customer and owner UI visually consistent.
5. Prioritize grocery usability over decoration.
6. Never introduce delivery or online-payment UX.
7. If a product/UX requirement is unclear, ask — don't invent it.
8. If a new design decision should become permanent, update this file (don't create other design docs).
