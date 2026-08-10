# Prefs language combo: empty closed value + search resizes popover

**Status:** ✅


**Reported from:** `ibus-setup-sherpa-onnx` → Select model → Language  
**Package:** `ibus-sherpa-onnx` (prefs `Adw.ComboRow` in `RowComboLanguage`)

## Problem

Two separate UI bugs on the Language combo:

1. **Empty closed value** — The **closed** combo’s pull-down / selected-value
   area does not show the current language. With default English it stays
   blank; it should show **English** (or whatever is selected).

2. **Search resizes the popover** — Typing in the combo search box makes the
   **pull-down popover change size** as the list filters. Size should stay
   put while searching.

## Scope (what “fixed” means)

- **Bug 1:** Closed row’s selected-value / pull-down area always shows the
  selected language label (at least for default `en` / English). Blank = not
  fixed.
- **Bug 2:** Typing in search must not make the popover jump / shrink / grow.
  Stable size while filtering = fixed.

## What not to chase

- 🚫 Relabeling Chinese / Mandarin / ICU `display=` / `label=` (separate).
- 🚫 Search failing to filter (substring search already works).
- 🚫 Claiming fix without reinstalling
  `/usr/libexec/ibus-setup-sherpa-onnx` (PATH wrapper → libexec).

## Code

- `src/setup/RowComboLanguage.vala` — `Adw.ComboRow`

## Why current code fails these

`Adw.ComboRow` is a GTK4 list widget: the **traditional** way to paint items
is `Gtk.SignalListItemFactory` on the combo (`factory`, and optionally
`list_factory` for the open list). That is how DropDown / ComboRow are meant
to be used — setup/bind create the row widgets from each model item.

| Property | Role |
| --- | --- |
| `factory` | Builds the **closed** selected-value widget (pull-down area) |
| `list_factory` | Builds each row **inside** the open popover (if unset, reuses `factory`) |
| `expression` | String for **search** (and for the stock factory if you use it) |
| `model` | `Gtk.StringList` of labels |

What we did instead: set only a custom `list_factory`, leave the stock
`factory`, and try to surface the selection via **`use_subtitle`**. That is
not “use the factory”; it reuses the ActionRow subtitle slot as a stand-in
for the combo value chrome. The blank the reporter sees is that **pull-down
area** (`factory`), which never got a real bind of `StringObject:string`.

Also junk: `selected = INVALID` then reselect in `fill()` — no-op
(`Gtk.SingleSelection` ignores `INVALID` when the model has items).

Popover resize: list rows’ natural width follows **visible** (filtered)
items, so the popover shrinks on search. Row-level `width_chars` /
`set_size_request` did not meet acceptance.

## Proposed fixes

### Bug 1 — traditional factories for closed + list

**Recommended:** Use factories the normal way. Do **not** use `use_subtitle`
as the selected value.

- One `SignalListItemFactory` (or two if closed vs list need different
  chrome): `setup` creates a `Gtk.Label`, `bind` sets
  `(item as Gtk.StringObject).string`.
- Assign it to **`factory`** (closed pull-down). Assign the same or a wider
  variant to **`list_factory`** (open list, no ellipsis).
- Keep `expression` only so search can filter.
- Static subtitle again: `Spoken language for dictation`.
- `fill()`: only `combo.selected = idx`.

```vala
// Traditional ComboRow item factory (closed value + list rows)
factory.setup → Label { … }
factory.bind  → label.label = (list_item.item as StringObject)?.string ?? ""

combo.factory = factory;           // pull-down / selected value
combo.list_factory = list_factory; // open list (wider; no ellipsis)
combo.expression = …;              // search only
combo.use_subtitle = false;
combo.subtitle = "Spoken language for dictation";
combo.model = labels;
```

💩 Closed `factory` and open `list_factory` need **different** styling: the
selected strip cannot use the list’s `width_chars` floor or it blows out the
row. List keeps the wide floor; closed ellipsizes.

### Bug 2 — stop popover resize on search

**Recommended:** In the shared item factory, set each `Gtk.Label`’s
`width_chars` to the longest catalog label’s character count so every row
(including short filtered hits) requests the same minimum width. No popover
walk, no CSS.

🚫 Display-wide / app-wide CSS for `popover.menu`.

## Implementation order

1. Bug 1 — shared/split factories. **✔️**
2. Bug 2 — factory `Label.width_chars` on list. **✔️**
3. Verify on installed 0.3.2 prefs binary.

## Notes

Prior approach reused ComboRow via `use_subtitle` / stock factory instead of
binding items through factories. That is the wrong shape for bug 1. Implement
the factory path above; do not add more subtitle/reselect hacks.
