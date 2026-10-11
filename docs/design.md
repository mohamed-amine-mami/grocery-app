# GrocerGo — Visual Design Specification

UI/UX source of truth. Read it before any Flutter screen work. It says what to build and how the screens should look. Business rules live in `orders.md` and `owner-domain.md`; general Flutter, accessibility and architecture practice lives in `CLAUDE.md` and the installed skills.

**Direction: "Liste".** A neighbourhood grocery you can read quickly: product *rows* with a clear price and action column, a few strong typographic levels, one confident use of green, and a pickup *ticket* that ends the journey. It is not a Material 3 starter and not an admin dashboard.

**How to read the labels.**
- **Rule** — what to build. Unlabelled text is a rule.
- **Today** — a fact about the current code, checked when this file was written. Nothing else in this document claims the app already looks like this.
- **Validate** — a design decision that must be confirmed in the catalogue prototype (see *Rollout*) before it is applied to other screens.
- **Candidate** — a recommendation, not decided.

Scope: the **customer** app. The owner app shares tokens and components but is not redesigned here (see *Owner app*).

---

## 1. Product and design principles

### 1.1 Product (rules)

- Pickup-only grocery app. **No delivery flow, ever.** No Delivery/Pickup switch.
- Customer journey: **Find → Add → Confirm → Pick up → Pay at store.**
- Payment is always at pickup. Never design or word anything that implies online payment.
- Customer capabilities: browse stores, browse a store's catalogue, search and filter by category, adjust quantities, cart, place an order with a *desired* pickup time, track status, read the pickup code, profile photo, sign out.
- Not built: product detail screen, cross-store search, notifications, online payment.

### 1.2 Personality

GrocerGo should feel **dependable, quick and plain-spoken**, like a good local shop whose list you can read at a glance.

| It communicates | How |
|---|---|
| Fast discovery | Dense, aligned rows; one clear price column; category tabs that stay visible |
| Readable prices and quantities | Prices are the strongest element of a row; quantities say the unit in words ("500 g", "2 pièces") |
| Confidence | One primary action per screen; totals always visible beside the action |
| Clear pickup information | A ticket with a large code, a status sentence and a tracker |
| Restrained identity | One brand colour used on purpose, a warm neutral background, generous but not empty whitespace |

### 1.3 Principles

1. **Rows, not cards.** The default container for repeated content is a row on a shared white surface separated by hairlines. A bordered card is for a *single, self-contained* summary (a total, a ticket).
2. **Hierarchy by type and position, not by borders.** If a screen needs a border to be understood, fix the type scale or spacing first.
3. **Green means "this is the brand or the next step".** It is not the default colour of every icon, outline, link and selected state (see 2.2).
4. **One focal point per screen** (see each screen in 5). Everything else is quieter than it.
5. **Never hide essential information to keep density.** Price, quantity and the add control are always visible; rows grow with the text.
6. **Status is never colour alone.** Icon + text, always.
7. **Photos are a bonus.** The layout must look finished with none.

### 1.4 Avoid

Delivery-app aesthetics · luxury or "organic/bio" cliché · gradients and blobs · shadows beyond a hairline · card-in-card · oversized decorative type · green on everything · a different style for the same thing on different screens · emojis as icons · documenting an unbuilt feature as existing · Citrus as a text, icon or border colour.

---

## 2. Color and typography

### 2.1 Tokens (unchanged — `AppColors` in `app_theme.dart`)

| Token | Hex | Role |
|---|---|---|
| Primary / Market Green | `#2F6B4F` | Brand band, primary action fill, key emphasis (see 2.2) |
| Secondary / Sage | `#4F765F` | Currently unused as a surface; available for rare supporting emphasis |
| Accent / Citrus | `#F2B84B` | **Fill only**: the cart-count badge; one "needs attention" count per screen |
| Background / Warm Cream | `#F7F6F0` | Page background |
| Surface / White | `#FFFFFF` | List surfaces, bars, sheets, fields |
| Primary Text | `#18221C` | Names, prices, headings |
| Secondary Text | `#5E6B62` | Meta, units, addresses, captions |
| Success | `#2E7D5B` | "Ouvert", "Prête à retirer" (icon + text) |
| Warning | `#8A5E00` | "Indisponible", removed lines, closed notes |
| Error | `#B54747` | Errors, destructive actions only |
| Disabled | `#A9B0AB` | Disabled controls, upcoming tracker steps |

Derived (not new): tints at 8% / 12% of a token for tiles, badges and notes; the hairline `#18221C` at 10% for dividers and card borders. No new colour, no gradient.

### 2.2 Where green is used (rule)

| Use green for | Do not use green for |
|---|---|
| The store-context **band** (catalogue and store header) | Every icon in a row |
| The **primary action** button fill (one per screen) | Outlined secondary buttons (use a neutral outline — see 4.5) |
| The **selected** category tab's underline and text | Dividers, borders, card edges |
| The `+` / stepper accent on product rows (small, one control per row) | Large surfaces repeated on the same screen |
| Completed and current steps of the tracker | Decorative icons (clock, store, pin) — these use Secondary Text |

**Rule — large green surfaces.** At most **one** large green surface per screen: the store band on store screens. Bottom action bars are **white**; only the button is green.

**Citrus.** Fill only, always with Primary Text on it (9.14:1). Allowed: the cart-count badge (**Today:** Citrus fill, Primary Text number, counts distinct products, shown only when the cart is not empty), and at most one "needs attention" count per screen. Never for buttons, selected states, status badges, banners, text, icons or borders (1.79:1 on white).

### 2.3 Typography

Font: **Inter** (bundled, weights 400/500/600/700). Use **tabular figures** (`FontFeature.tabularFigures()`) for every amount, quantity and code so columns line up.

Sizes come from the existing scale (12, 14, 16, 18, 20, 24, 28). **Weights are assigned by purpose**, not inherited from the default text style. Roles map to existing `TextTheme` slots with a weight override where noted; no new slots are required.

| Role | Size / weight | Colour | Slot (+ override) |
|---|---|---|---|
| Store name — band | 24 / 700 | White | `headlineSmall` |
| Store name — store row | 18 / 600 | Primary Text | `titleMedium` |
| Section heading (category, "Produits") | 16 / 700, count in 14 / 400 Secondary | Primary Text | `bodyLarge` + w700 |
| Product name | 16 / **500** | Primary Text (Secondary when unavailable) | `bodyLarge` + w500 *(Validate: today 600)* |
| Brand | 12 / 500 | Secondary | `labelSmall` |
| **Price** (amount) | 18 / **700**, tabular | Primary Text | `titleMedium` + w700 *(Validate: today 600)* |
| Unit price and unit (`/ pièce`, `/ kg`) | 12 / 400 | Secondary | `labelSmall` + w400 |
| Quantity value ("500 g", "2 pièces") | 14 / 600, tabular | Primary Text | `labelLarge` + w600 |
| Quantity / availability meta ("Min. 250 g", "Indisponible") | 12 / 500 | Secondary / Warning | `labelSmall` |
| Order status | 12 / 600 in a badge | status colour | badge (see 4.4) |
| Pickup code | 28 / 700, tabular, +1.5 letter spacing | Primary Text | `displaySmall` |
| Total (estimated or final) | 20 / 700, tabular | Primary Text | `titleLarge` |
| Supporting description / address | 14 / 400 | Secondary | `bodySmall` |
| Body text | 16 / 400 | Primary Text | `bodyLarge` |
| Button label | 16 / 600 | on fill | button theme |
| Screen title (app bar) | 20 / 700 | Primary Text | app bar theme |

**Weight rules.**
- 400: running text, descriptions, addresses, units.
- 500: product names, brands, captions, labels.
- 600: quantity values, badge labels, button labels, store names in rows.
- 700: prices, totals, section headings, the code, band store name.
- A row has **one** 700 element (its price) and **one** 500–600 name. Never make the whole row semibold.

**Today:** `bodyMedium` (the default for unstyled `Text`) is 16/600, so unstyled text is semibold. Rule: every text in a customer screen sets a role; none relies on the default. The open decision for that slot is in 8.

---

## 3. Spacing, surfaces and dividers

### 3.1 Spacing (tokens unchanged)

Scale `4 · 8 · 12 · 16 · 20 · 24 · 32 · 40`. No arbitrary values.

| Where | Value |
|---|---|
| Page padding | 16 |
| Row: vertical padding | 12 |
| Row: horizontal padding | 16 (the list surface is full-bleed inside the page padding) |
| Row: thumbnail ↔ text | 12 |
| Row: name ↔ meta lines | 4 |
| Between sections | 24 |
| Band: padding | 16, 8 between its lines |
| Action bar padding | 16 |

### 3.2 Surfaces

| Surface | Spec |
|---|---|
| Page | Cream `#F7F6F0` |
| **List surface** | White, radius 16 (Card), 1 px hairline border, no elevation; rows inside separated by 1 px hairline dividers inset 16 (aligned with the text, not the thumbnail). One list surface per section. |
| **Summary block** | A single white card with the same radius and border, for self-contained summaries only: total, ticket, payment. |
| Tile | Primary 8% fill, radius 12 — thumbnails and placeholders. |
| Store band | Primary fill, flat bottom edge *(Validate: flat vs. 16 bottom radius)*; content in white. |
| Bar | White, hairline top divider, no shadow. |
| Notice | Icon + text on an 8% tint of the status colour with a 30% border of the same colour, radius 12. One pattern for closed store, cart problems and warnings. |

**Rules.** No card inside a card. No border on a row. No shadow. A section heading sits **above** its list surface, not inside it.

### 3.3 Radii and touch targets (unchanged)

Card 16 · Button 12 · Input 12 · Sheet/Dialog 20 · Chip 999 · Badge 8 · Tile 12.
Touch targets: **48** for buttons and tappable rows; **44 × 44** is the floor for in-row controls (add button, stepper buttons). A control may look smaller than its target; its hit area may not.

---

## 4. Reusable components

### 4.1 Product row (catalogue)

One row = thumbnail slot · one text column. The text column holds the name, its meta lines, and — directly beneath — one **price line**: the price at the left edge, the control at the right edge.

```
┌────────────────────────────────────────────┐
│ ┌──────┐  Boisson au jus ananas 20 cl      │
│ │ 56px │  Délice                           │
│ │ tile │  2,000 DT                    ( + )│
│ └──────┘  / pièce                          │
├─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─┤
│  ┌────┐   Sel                              │
│  │48px│   1,200 DT                   ( + )│
│  └────┘   / pièce                          │
└────────────────────────────────────────────┘
```

- **Thumbnail slot:** always 56 px wide and top-aligned, so every row's text starts at the same x.
  - A product with a **photo**: a 56 × 56 tile (Primary 8%), radius 12, the whole picture shown (`contain`), decoded at slot size.
  - A product **without** a photo (or whose photo failed): a quieter **48 × 48** tile in the same slot — the same tint, with a smaller (20 px), lower-contrast (Primary 40%) basket icon. It never imitates a photo.
- **Text column (flexible):**
  1. Product name — up to 3 lines then an ellipsis. Above 1.3× text the limit is lifted and the name is shown whole (never an ellipsis without a line limit, which would cut it to one line).
  2. Brand, when there is one (12/500).
  3. `Min. 250 g`, only when the minimum is not one base unit (12/500).
  4. **No empty slot:** a product with no brand and no minimum has its price line directly under the name (8 px). Nothing is reserved for metadata that is not there.
- **Price line:**
  - Price block at the left: the amount (18/700, tabular) over its unit (`/ pièce`, `/ kg`, `/ L`, 12/400) — always two short lines, so the unit never wraps by accident. Read aloud as "2,000 DT par pièce".
  - Control at the right edge, vertically centred on the price block. The block is as tall as the 44 px control (taller with large text).
  - **Narrow screens / large text:** when the text column cannot hold the price block and the *widest* state of the control (the stepper at its minimum, current or maximum quantity) side by side, the control goes **under** the price, right-aligned. The decision is measured, not guessed, and is the same for the `+` and the stepper of a given row — so adding a product never changes the row's height or arrangement.
- **Row height is not fixed.** It follows content: a plain row is about 100 px; a name on several lines grows it.
- **Thumbnail at large text:** hidden above 1.6× so the column keeps the width.
- **Unavailable product:** thumbnail at 45% opacity, name in Secondary Text, `Indisponible` (Warning, icon + text) in the control's place. No add control. The price stays visible.
- **Closed store:** no controls on any row; the closed notice sits under the band.
- **Tap target:** the row itself is not tappable (no product detail screen). Only the control is.

### 4.2 Add control and quantity stepper

| State | Spec |
|---|---|
| Not in cart | A **filled circle**, 44 × 44, Primary fill, white `+` icon. Tooltip and semantics: "Ajouter {produit}". No `Ajouter` label. |
| In cart | An inline `− quantité +` stepper, same 44 px height, right-aligned at the same place. Quantity is the formatted quantity ("500 g", "2 pièces"), tabular, between two 44 px buttons (the existing component). |
| At minimum | `−` becomes a red trash icon that removes the line (tooltip "Retirer {produit} du panier"). |
| At maximum | `+` disabled with tooltip "Quantité maximale atteinte pour {produit}". |

- One filled control per row, small and at the same x in every row: green is used for the *one* thing to do. It is a rule, not a decoration: no other green fill appears in a row.
- **Validate:** whether the stepper needs a visible 1 px outline to read as one control. On the iPhone 17 it reads clearly with the trash/plus glyphs and the quantity between them.

Quantity steps, minimums, maximums and cart totals are unchanged business rules (`product-rules.ts`, the cart view model); the visual spec never changes them.

### 4.3 Store row

```
┌────────────────────────────────────────────┐
│ ┌──────┐  Menzah Market       ● Ouvert    ›│
│ │ 64px │  12 Rue de la Liberté, Tunis       │
│ │ tile │  Épicerie de quartier              │
│ └──────┘  Panier en cours                   │
└────────────────────────────────────────────┘
```

- **Thumbnail:** 64 × 64 tile. With a photo: the photo, `cover`, radius 12. Without: the tile with the store's **initial** (24/700, Primary at 60%), the same tint and tone as the product placeholder.
- **Text block:** name (18/600) · open state as icon + text (4.4) · address (14/400, one line, ellipsis) · description (14/400, up to 2 lines) · optional `Panier en cours` marker (12/500, Secondary, with a cart icon).
- The placeholder address `Adresse à renseigner` is not shown.
- **Affordance:** trailing chevron; the whole row is the 48 px+ target, with `Voir le catalogue` as its semantics hint.
- **No banner photo.** A large photo must never dominate the list; store photos are thumbnails.
- Order: **open stores first**, then closed, name order inside each group (unchanged).

### 4.4 Badges, status and open state

- Open/closed: `Ouvert` (Success, check icon) / `Fermé` (Secondary, lock-clock icon). Icon + text.
- Order status badge: 8 radius, 12% tint, 16 px icon + 12/600 label. Colours (unchanged): `En attente` Warning · `Confirmée` Primary · `Prête à retirer` Success · `Terminée`, `Annulée`, `Non retirée` Secondary. Cancelled and uncollected are **calm**, not red.
- On the store band, the open/closed badge uses white text on a white 16% fill (derived), still with its icon.

### 4.5 Buttons

| Role | Spec | Where |
|---|---|---|
| Primary | Filled Primary, white label 16/600, 48 min height, radius 12. **One per screen.** | Commander, Confirmer la commande, Voir les magasins |
| Secondary | Outlined, **neutral** border (Secondary Text) and Primary Text label *(Validate: exact border alpha)* | Continuer mes achats, Se déconnecter |
| Destructive | Outlined Error | Annuler la commande |
| Text | Primary label 14/500 | Effacer les filtres, Réessayer, Corriger la quantité |

Loading: a 20 px spinner inside the same button; disabled: Disabled fill.

### 4.6 Bottom action bar

```
┌────────────────────────────────────────────┐ ← 1 px top divider
│ Total estimé        ┌──────────────────────┐│
│ 2,000 DT            │      Commander        ││
│                     └──────────────────────┘│
└────────────────────────────────────────────┘
```

- White surface, hairline top divider, safe-area padding, 16 padding.
- Left: label (12/500 Secondary) and the total (20/700 tabular). Right: the primary button (flexible width, ≥ 48 high).
- **Large text or narrow width (text scale > 1.3 or width < 360):** the total sits above the button, both full width.
- Variants:
  - Catalogue: left `1 produit` / total, button `Voir le panier` (shown once the cart has items).
  - Cart: left `Total estimé`, button `Commander`.
  - Checkout: left `Total estimé`, button `Confirmer la commande` (or `Réessayer l’envoi`).
  - Order detail: no total; a separate destructive outlined `Annuler la commande` while the order can be cancelled.
- The total in the bar is the same number as the total card above it ("one number").
- **Today:** the bars are white with the total as trailing text inside the full-width primary button; the beside-the-button layout is a Target to validate.

### 4.7 Product image and placeholder

- **Fit:** `contain` in the 56 px tile (whole picture, never cropped or stretched); decoded at slot size × device pixel ratio.
- **Loading:** the placeholder holds the space until the first frame. No spinner, no fade.
- **Error / no photo:** the same placeholder — Primary 8% tile with a basket icon in Primary at 60%. One generic placeholder; **it is the tile itself**, so a photo and a placeholder share the same background. In a catalogue row the photo-less tile is the quiet 48 px variant (icon 20 px, Primary 40%) in the 56 px slot (4.1); in cart and checkout lines the placeholder keeps the 56 px tile.
- **Semantics:** the image is decorative in cart and checkout (the name is read); in the catalogue it is labelled "Image du produit".
- **Today:** this treatment exists in `ProductImage` (`tile: true`, and `quiet: true` for the photo-less catalogue row). Photo coverage is data, not a UI promise.
- **Candidate (not approved):** per-category placeholder icons.

### 4.8 Search and category navigation (catalogue)

- **Search field** on the cream page directly below the band: white, radius 12, search icon, clear button, autocorrect off. Hint `Rechercher un produit`.
- **Category navigation:** a horizontally scrollable strip of text tabs `Tous · Boissons · Boulangerie · …`, 14/500; the selected tab is Primary Text 14/600 with a 2 px Primary underline; others Secondary Text. Not pills. *(Validate: tabs vs. today's chips.)*
- When a **category is selected**, its section heading is **not repeated** above the rows — the tab already says it. With `Tous`, rows are grouped under `{Catégorie} · {n}`.
- No match: icon, `Aucun produit trouvé`, text action `Effacer les filtres`.

### 4.9 Notices, empty and error states

| State | Treatment |
|---|---|
| Loading | Centered circular indicator in Primary; pull-to-refresh on lists *(skeletons: Candidate)* |
| Empty | 48 px icon (Secondary), title 18/600, one explanatory line 14/400, one action when there is one |
| Load failed | Title, `Vérifiez votre connexion, puis réessayez.`, text action `Réessayer` |
| Failed refresh over content | Inline notice at the top of the list |
| Transient feedback | Snackbar |
| Closed store | Notice: `Ce magasin est fermé : vous ne pouvez pas commander pour le moment.` (cart) and the closed notice under the band (catalogue); browsing stays possible |
| Cart problem | Per-line notice (`Ce produit n’est plus disponible. Retirez-le du panier.` / `La quantité n’est plus valide pour ce produit.`) and `Corrigez votre panier avant de commander.` above the button |

Existing empty-state strings are preserved: `Aucun magasin` + `Les magasins apparaîtront ici.` · `Ce magasin n’a pas encore ajouté de produits` + `Revenez plus tard, ou découvrez un autre magasin.` with `Voir les autres magasins` · `Aucun produit pour le moment` · `Votre panier est vide` + `Choisissez un magasin pour commencer vos achats.` with `Voir les magasins` · `Aucune commande` + `Vos commandes apparaîtront ici.`

### 4.10 Navigation

Bottom `NavigationBar`, four tabs, each keeps its state: **Magasins · Panier · Commandes · Profil**, icons storefront / shopping cart / receipt / person (Material Icons **Rounded**).

- Surface white with the hairline top divider.
- **Selected tab:** Primary icon and Primary 12/600 label; indicator is a 2 px Primary line at the top of the item **instead of the filled pill** *(Validate: custom indicator vs. keeping the tinted pill)*.
- Unselected: Secondary Text icon and 12/500 label.
- **Cart badge:** Citrus fill, Primary Text number, counting products (lines), hidden when the cart is empty. Position and semantics unchanged.
- The tab bar is not shown inside a store catalogue (the catalogue is pushed on top); back returns to Magasins.
- No Home, Categories or cross-store Search tab. If one is added, record it here first.

### 4.11 Icons

Material Icons **Rounded**. Sizes: 16 in badges and status labels, 18 inside buttons, 20 in notes, 24 default, 48 in empty states. Decorative leading icons (clock, store, pin) use Secondary Text, not green. Don't mix families; no emojis as UI icons. A few `_outlined` icons remain in the code; switch them to Rounded when a screen is touched. Moving to Material Symbols would be a recorded decision — not planned.

### 4.12 Motion

Functional only, ~150–200 ms. **Today:** none beyond platform route transitions. Candidates (none approved): add → stepper transition, badge update, status-change transition, skeleton loading.

---

## 5. Screens

For each screen: first focal point · hierarchy · primary action · secondary information · scrolling · narrow and large-text behaviour. Wireframes are schematic. **Strings are the app's current French strings; store, product and price values are illustrative unless marked "observed".**

### 5.1 Store discovery (Magasins)

```
Magasins                         (app bar title)
┌────────────────────────────────────────────┐
│ ┌────┐ Menzah Market        ● Ouvert      ›│
│ │ M  │ 12 Rue de la Liberté, Tunis          │
│ └────┘ Épicerie de quartier                 │
│────────────────────────────────────────────│
│ ┌────┐ Lac Épicerie         ● Ouvert      ›│
│ │foto│ Les Berges du Lac                    │
│ └────┘ Panier en cours                      │
│────────────────────────────────────────────│
│ ┌────┐ Marché du Bardo      🔒 Fermé      ›│
│ └────┘ Avenue Habib Bourguiba               │
└────────────────────────────────────────────┘
```

- **Focal point:** the first open store's name.
- **Hierarchy:** store name → open state → address → description → cart marker.
- **Primary action:** tapping a row opens its catalogue. No button.
- **Secondary:** description, `Panier en cours`.
- **Scrolling:** the title and list scroll together; one list surface; pull to refresh.
- **Narrow / large text:** the thumbnail stays until text scale 1.6×, then is hidden; the name wraps up to 3 lines; the open badge moves under the name rather than truncating either.
- **Preserved:** open-first order, empty state `Aucun magasin`, failure/retry, closed stores remain browsable.
- **Today:** text-only bordered cards, with a 16:9 banner when a store has a photo.

### 5.2 Store catalogue

```
┌────────────────────────────────────────────┐
│ ‹  Menzah Market                            │  ← Primary band, white text
│ ● Ouvert  12 Rue de la Liberté, Tunis       │
└────────────────────────────────────────────┘
 ┌─────────────────────────────────────────┐
 │ 🔍  Rechercher un produit               │
 └─────────────────────────────────────────┘
  Tous   Boissons   Boulangerie   Épicerie ›
  ─────
 Boissons · 2
┌────────────────────────────────────────────┐
│ ┌────┐ Boisson au jus ananas 20 cl        │
│ │tile│ Délice                             │
│ └────┘ 2,000 DT                      ( + )│
│        / pièce                             │
│────────────────────────────────────────────│
│ ┌───┐  Café moulu 250 g                    │
│ │48 │  5,000 DT          ( 🗑  1 pièce  + )│
│ └───┘  / pièce                             │
└────────────────────────────────────────────┘
 Boulangerie · 2 …
┌────────────────────────────────────────────┐
│ 1 produit                                   │  ← white bar, divider
│ 7,000 DT                   [ Voir le panier ]│
└────────────────────────────────────────────┘
```

- **Focal point:** the store name in the band, then the first price.
- **Hierarchy:** band (identity + state) → search → category tabs → section heading → product rows (name → meta → price line with its control).
- **Primary action:** the filled `+` / stepper on rows; the bar's primary button once the cart has items.
- **Secondary:** brand, unit, minimum.
- **Scrolling:** the band, search and tabs scroll away with the list *(Validate: pin the tabs and search while scrolling)*; the action bar stays pinned. Rows are built lazily.
- **Narrow / large text:** the price line puts the control under the price when they do not fit side by side (4.1); names wrap whole above 1.3×; the thumbnail is hidden above 1.6×; the bar stacks (4.6). Acceptance: product names readable at 1.65× on 400 px and 2× on 320 px with price and control visible.
- **Band:** the address is not shown while it is the placeholder `Adresse à renseigner`.
- **Preserved:** search and category filter, `Aucun produit trouvé` / `Effacer les filtres`, store-with-no-products state, closed-store notice and no controls, unavailable rows, per-store cart.
- **Today (implemented):** this is the catalogue as built — the band, text tabs, single-column list with a filled circular `+`, and the white action bar. Observed on an iPhone 17 at normal text and at ~2×: no layout shift when a product is added; the stepper sits at the right edge in the same place as the `+`.

### 5.3 Cart (Panier)

```
Panier
┌────────────────────────────────────────────┐
│ Menzah Market                  ● Ouvert     │  ← summary block
│ 12 Rue de la Liberté, Tunis                 │
└────────────────────────────────────────────┘
Produits · 2
┌────────────────────────────────────────────┐
│ ┌────┐ Boisson au jus ananas     2,000 DT  │
│ │tile│ 2,000 DT / pièce                    │
│ └────┘                  [ 🗑  1 pièce  + ] │
│────────────────────────────────────────────│
│ ┌────┐ Banane                    0,900 DT  │
│ │tile│ 1,800 DT / kg                       │
│ └────┘                  [ −  500 g   +  ]  │
└────────────────────────────────────────────┘
┌────────────────────────────────────────────┐
│ Total estimé                     2,900 DT  │
│ Le total définitif est confirmé à l’envoi…  │
└────────────────────────────────────────────┘
┌────────────────────────────────────────────┐
│ Total estimé 2,900 DT          [Commander]  │
└────────────────────────────────────────────┘
```

- **Focal point:** the total.
- **Hierarchy:** store → lines → estimated total and its note → action.
- **Primary action:** `Commander` (disabled when the store is closed or the cart has problems).
- **Secondary:** unit prices, the note, `Retirer` / `Corriger la quantité` on problem lines.
- **Scrolling:** content scrolls; the bar is pinned above the tab bar.
- **Narrow / large text:** line thumbnails are hidden above 1.3×; the stepper keeps its 44 px buttons; the bar stacks.
- **Preserved:** same row as the catalogue with the **line subtotal** in the amount position and the unit price on the meta line; calculations, quantity limits, problem states, empty state `Votre panier est vide`.
- **Today:** lines are 56 px tile rows in a bordered card with the stepper right-aligned beneath; the `Commander` bar carries the total as trailing text.

### 5.4 Checkout (Valider la commande)

```
‹  Valider la commande
Retrait
┌────────────────────────────────────────────┐
│ 🕒 Heure de retrait souhaitée            › │
│    Aujourd’hui · 18:30                      │
└────────────────────────────────────────────┘
 C’est une heure souhaitée, pas un créneau réservé.
┌────────────────────────────────────────────┐
│ Paiement                 À la récupération │
└────────────────────────────────────────────┘
Votre commande
┌────────────────────────────────────────────┐
│ ┌────┐ Boisson au jus ananas     2,000 DT  │
│ │tile│ 1 pièce · 2,000 DT / pièce          │
│ └────┘                                      │
└────────────────────────────────────────────┘
 Total estimé                        2,000 DT
 Le total définitif est confirmé à l’envoi de la commande.
┌────────────────────────────────────────────┐
│ Total estimé 2,000 DT [Confirmer la commande]│
└────────────────────────────────────────────┘
```

- **Focal point:** the pickup time (the only choice the customer makes here).
- **Hierarchy:** Magasin (store name and address, secondary) → Retrait → Paiement → Votre commande → total.
- **Primary action:** `Confirmer la commande` (or `Réessayer l’envoi` after a network failure).
- **Secondary:** the store's name and address, the explanatory note.
- **Scrolling:** content scrolls; the bar is pinned and always shows the total; payment is above the order list, never below the fold.
- **Narrow / large text:** the metadata line is two pieces (`1 pièce ·` / `2,000 DT / pièce`) that wrap between them, never inside the unit price; the bar stacks.
- **Preserved:** pickup-time sheet (30-minute choices grouped by day), the "heure souhaitée, pas un créneau réservé" note, payment `À la récupération`, error banners (store closed, product unavailable, invalid pickup time), submission loading, idempotent retry, session-expired sign-out. Never styled or worded like an online checkout.

### 5.5 Orders list (Commandes)

```
Commandes
┌────────────────────────────────────────────┐
│ Menzah Market                ⏳ En attente │
│ aujourd’hui · 18:30                         │
│ K7M2QX                          2,000 DT   │
│────────────────────────────────────────────│
│ Menzah Market                ✓ Terminée    │
│ sam. 10 oct. · 16:00                        │
│ ZCM5VM                          1,200 DT   │
└────────────────────────────────────────────┘
        [ Voir plus de commandes ]
```

- **Focal point:** the store name and status of the newest order.
- **Hierarchy:** store + status → pickup date/time → code and total.
- **Primary action:** tapping a row opens the ticket.
- **Secondary:** the code as a 12/500 caption; no thumbnails.
- **Scrolling:** one list surface, newest first, paged (`Voir plus de commandes`), pull to refresh, polled while visible.
- **Narrow / large text:** the status badge wraps under the store name; the total stays right-aligned or drops under the code.
- **Preserved:** newest-first order, paging, polling pause/resume, `Aucune commande` empty state, failure retry. No grouping into active/finished (Candidate; revisit if users struggle to find a live order).
- **Today:** the code is the card title, the store name is secondary text, and a green clock icon repeats on every card.

### 5.6 Order detail — the pickup ticket

```
‹  Commande K7M2QX
┌────────────────────────────────────────────┐
│ Code de retrait               ✓ Confirmée │
│ K7M2QX                                      │  ← 28/700, letter-spaced
│ Le magasin a confirmé votre commande.       │
│ - - - - - - - - - - - - - - - - - - - - - - │  ← perforation (Validate)
│ ●────●────○────○                            │
│ Envoyée Confirmée Prête Récupérée           │
│ 🕒 Retrait souhaité                         │
│    sam. 10 oct. · 16:00                     │
│ 🏪 Menzah Market                            │
│    12 Rue de la Liberté, Tunis              │
└────────────────────────────────────────────┘
Produits · 1
┌────────────────────────────────────────────┐
│ Croissant                       1,200 DT   │
│ 1 pièce · 1,200 DT / pièce                  │
└────────────────────────────────────────────┘
┌────────────────────────────────────────────┐
│ Total                           1,200 DT   │
│ Paiement                 À la récupération │
└────────────────────────────────────────────┘
Suivi …
[ Annuler la commande ]    ← destructive, pending/confirmed only
```

- **Focal point:** the pickup code.
- **Hierarchy:** code → status badge and sentence → tracker → pickup time and store → lines → server total and payment → history.
- **Primary action:** none, except `Annuler la commande` (destructive, while `En attente` or `Confirmée`).
- **Secondary:** history (`Suivi`), removed lines (`Retirés par le magasin`, struck through with `Retiré de la commande`).
- **Scrolling:** the whole page scrolls; the cancel bar is pinned; pull to refresh; polls while the order can change and the screen is visible.
- **Tracker:** four steps `Envoyée → Confirmée → Prête → Récupérée`, a connecting line, three visible states — **completed** (filled Primary check), **current** (filled Primary with a bold label; the last reached step), **upcoming** (outlined Disabled). Cancelled and uncollected show no tracker (the badge and sentence say it; the cancellation reason shows as `Motif : …`).
- **Just placed:** while still `En attente`, a `Commande envoyée` banner (success icon, `Le magasin va la confirmer. Vous pouvez suivre son état ici.`, `Voir mes commandes`, `Continuer mes achats`) sits above the ticket. It disappears once the status moves on.
- **Status sentences:** pending `Le magasin va confirmer votre commande.` · confirmed `Le magasin a confirmé votre commande.` · ready `Votre commande est prête. Présentez votre code au magasin.` · uncollected `La commande n’a pas été retirée.`
- **Narrow / large text:** above 1.3× the tracker shows the four icons and **only the current step's name** on one line below; the code, badge and time stay inside the screen at 320 px and 2×.
- **Preserved:** lifecycle, polling and its pause, the cancellation dialog, 404 closes the screen with a message, removed lines excluded from the total, the server's total shown as final, timestamps from the server only. Presentation never invents a status or a time.
- **Validate:** the perforation divider and ticket-block treatment, and whether the code is large enough at 320 px and 2×.

### 5.7 Customer profile (Profil)

```
Profil
        ┌──────┐
        │ 96px │  (avatar, camera action)
        └──────┘
Bonjour, Amine
Vous êtes connecté en tant que client.
┌────────────────────────────────────────────┐
│ Téléphone                       90 909 090 │
└────────────────────────────────────────────┘

        [ Se déconnecter ]
```

- **Focal point:** the avatar and greeting.
- **Hierarchy:** greeting (24/700) → role sentence → one labelled info block (phone, when there is one).
- **Primary action:** none; `Se déconnecter` is a secondary (neutral outline) button at the bottom.
- **Secondary:** the role sentence and phone, labelled (12/500 label, 16/400 value).
- **Scrolling:** short page; the sign-out button stays reachable at large text (the page scrolls rather than clipping).
- **Preserved:** profile photo behaviour, sign out, session handling.
- **Today:** a 112 px avatar, greeting, role sentence, a bare phone number, and the sign-out button pinned to the bottom of a mostly empty page.

---

## 6. Responsive and accessibility requirements

### 6.1 Responsive

- Phone widths from 320 to 430 dp; text scale up to **2×** must not clip or overlap on any screen.
- Rows, bars and the tracker reflow as described above; no fixed row heights; no horizontal page scroll.
- Thumbnails in cart and checkout lines are hidden above 1.3× text, where the row needs the width. For catalogue rows the threshold is a Validate item (9).
- The catalogue's accepted large-text bars: product names readable at 1.65× on 400 px and 2× on 320 px, with price and control visible.
- The action bar stacks its total above the button at large text or under 360 dp.

### 6.2 Accessibility

**Target: WCAG 2.1 AA**, applied to a native app by analogy, alongside iOS/Android guidance. Nothing in this file is a conformance claim; compliance has not been audited.

- Text ≥ 4.5:1, large text and UI boundaries ≥ 3:1.
- Status, availability and selection are never colour alone.
- Touch targets as in 3.3. Icon buttons carry a tooltip or semantic label.
- Every control has a French label; the stepper buttons name the product (`Augmenter la quantité de {produit}`); the tracker steps read `Étape {nom} : atteinte` / `à venir`; a price reads with its unit ("2,000 DT par pièce").
- Decorative images are excluded from semantics; the cart badge's count is announced with its tab.
- Focus order follows reading order; sheets and dialogs return focus.
- Error messages say what happened and what to do, in French.

Computed from the token values (not a check of rendered screens):

| Pair | Ratio |
|---|---|
| Primary Text on white / cream | 16.35 / 15.10 |
| Secondary Text on white / cream | 5.59 / 5.16 |
| White on Primary (band, primary button) | 6.29 |
| Primary on cream | 5.81 |
| Warning on white | 5.70 |
| White on Error | 5.31 |
| Primary Text on Citrus | 9.14 |
| Citrus on white / cream | 1.79 / 1.65 |
| Success on its 12% tint | 4.26 |
| Disabled on white (input border) | 2.21 |

Known gaps (recorded decisions, not silent edits): Success text on its 12% tint is under 4.5:1 at 12 px; input and chip borders use Disabled, under 3:1. Borders for secondary buttons (4.5) and the search field must come from a token that passes 3:1 (Secondary Text does, 5.59:1) — **Validate** the exact alpha.

**Not verified:** a screen-reader pass on device, system-maximum text on every screen, focus order, contrast on rendered screens, small phones and tablets.

---

## 7. Worked examples and anti-patterns

### 7.1 Examples

**A. Catalogue rows with different units and states** *(illustrative; "Boisson au jus ananas 20 cl", "Délice" and "2,000 DT / pièce" were observed in the development store)*

```
Boissons · 2
┌────────────────────────────────────────────┐
│ [tile] Boisson au jus ananas 20 cl 2,000 DT│
│        Délice                      / pièce │
│                                    [ + ]   │
│────────────────────────────────────────────│
│ [tile] Eau minérale gazeuse 1,5 L  1,100 DT│
│        Safia · Min. 6 pièces       / pièce │
│                          [ − 6 pièces + ]  │
└────────────────────────────────────────────┘
Fruits et légumes · 2
┌────────────────────────────────────────────┐
│ [tile] Tomates rondes              2,400 DT│
│                                      / kg  │
│                           [ − 500 g  + ]   │
│────────────────────────────────────────────│
│ [tile] Fraises                     8,000 DT│
│  (dimmed, name in Secondary)        / kg   │
│                          ⚠ Indisponible    │
└────────────────────────────────────────────┘
```

**B. A long name that wraps, at large text** *(illustrative)* — the row stacks and grows; nothing is cut and the control stays reachable.

```
┌────────────────────────────────────────────┐
│ Huile d’olive extra vierge pressée à froid │
│ bouteille en verre 1 L                      │
│ Terra Delyssa                               │
│ 24,500 DT / pièce        [ − 2 pièces + ]  │
└────────────────────────────────────────────┘
```

**C. The pickup ticket for a confirmed order** *(illustrative)*

```
Code de retrait                  ✓ Confirmée
K7M2QX
Le magasin a confirmé votre commande.
- - - - - - - - - - - - - - - - - - - - - -
●────●────○────○
Envoyée Confirmée Prête Récupérée
🕒 Retrait souhaité
   sam. 10 oct. · 16:00
🏪 Menzah Market · 12 Rue de la Liberté, Tunis
```

### 7.2 Anti-patterns

| Don't | Do |
|---|---|
| A bordered card around every product | Rows on one list surface with hairlines |
| A full-width outlined "Ajouter" on every product | A compact 44 px add control in the price column |
| A green outline on every secondary button | A neutral outline; green is the primary action |
| A large store photo as the first element of a store | A 64 px thumbnail or initial tile |
| The same weight (600) for name, price, address and date | 500 name, 700 price, 400 meta |
| Hiding the price or control at large text to keep one line | Stack the row; let it grow |
| Repeating the category heading under the selected tab | Show the heading only for `Tous` |
| A green clock icon in every order row | Secondary Text icons; the status badge carries colour |
| Citrus for a button, selected tab or text | Citrus only as the cart-count fill |
| Online-payment wording at checkout | `À la récupération`, always |

---

## 8. Open decisions

- **Default text slot.** Roles in 2.3 are applied per element; `bodyMedium` (16/600) is still the default for unstyled `Text` at about 21 call sites. Decide whether to change it to 400 once the catalogue is migrated.
- **Success and Disabled contrast.** Change the tint or the text colour; choose the border colour of inputs, chips and secondary buttons.
- **WCAG target.** 2.1 AA is the working target; confirm, or move to 2.2 AA.
- **Second Citrus use.** The "needs attention" marker has no screen yet; keep or drop.
- **Candidates:** product detail, order-detail thumbnails, per-category placeholders, skeleton loading, active/finished grouping of orders.

## 9. Validate in the catalogue prototype

1. Product name 16/500 with price 18/700 reads as clearly better than today's 600/600.
2. The green store band: a calm, strong anchor or too heavy; flat vs. rounded bottom edge.
3. Category tabs (underline) vs. the current chips; pinned vs. scrolling search and tabs.
4. ~~The compact 44 px `+` control~~ — validated on device as a filled circle; whether the stepper needs a visible outline stays open.
5. The stacking threshold (~40% of row width) and the thumbnail-hiding threshold at large text; meet the 7B acceptance bars.
6. Tab-bar top-line indicator vs. the tinted pill.
7. The neutral outline for secondary buttons: contrast, and whether the screens still show a clear primary action.
8. The bar layout (total left, button right) at 320 dp and 2× text.
9. The ticket perforation and the 28/700 spaced code at 320 dp, and the open badge on green.

## 10. Rollout

1. Agree this specification.
2. Implement the **catalogue** as the representative screen.
3. Inspect it in the simulator at normal and large text, with and without photos, with a long name and each unit.
4. Decide: continue or adjust (update or close the *Validate* items).
5. Apply to the store list, cart, checkout, orders list, order detail, profile and navigation.
6. Final regression, responsive and accessibility pass.
7. Then the owner UI.

**Preserved through the redesign:** the line amount role and thumbnail tile, the checkout two-piece metadata, the Citrus badge, total and payment visible in cart/checkout bars, the compact tracker at large text, the confirmed wording, open-first store ordering, empty and filter states, semantic labels, and the customer test suites (grid-metric tests are rewritten for rows, not deleted).

---

## Owner app (not redesigned here)

Same tokens and components, denser and more operational. Navigation (**Accueil · Commandes · Catalogue · Magasin**, icons home / receipt / category / storefront) and the order lifecycle UI are unchanged by this direction.

**Catalogue rows** (store catalogue and picker) follow the same row model as 4.1:
- one row = thumbnail (`ProductImage`) + text block + one trailing control or status;
- text: name (up to two lines), brand (caption), one meta line (price per unit, then stock or category and unit, separated by `·`); "Par tranche de …" belongs in the editor;
- availability or catalogue status is icon + text, never colour alone;
- hairline dividers, no card inside a card, rows grow with text scale and never clip;
- lists stay lazy and paged.

**Today:** the store catalogue row shows a 56 px thumbnail, name, brand, price per unit, step, stock and status with an availability switch (up to six text lines); the picker shows a 48 px thumbnail, name, brand, `catégorie · unité` and an add icon or `Ajouté` / `Archivé`. Convergence on the single meta line is a Target.

---

## How to use this file

1. Read it before any Flutter screen work.
2. Reuse the tokens and the components in section 4; don't invent colours, type styles, radii or spacing.
3. Keep customer and owner UI one visual language in two densities.
4. Never introduce delivery or online-payment UX.
5. If a requirement is unclear, ask — don't invent it.
6. A decision that should become permanent goes in this file, labelled Rule, Today, Validate or Candidate, and moves when its status changes.
7. Don't document an unbuilt feature as existing.
