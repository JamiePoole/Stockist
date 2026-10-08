local ADDON_NAME, Stockist = ...

-- The kinds of panel the workspace (or a window) can host. A panel type registers itself by name:
--   Stockist.Panels:Register("chart", { title = "Price chart", create = function(parent, opts) -> panel end })
-- A panel object has at least `frame` (its root, filling `parent`), `SetItem(itemID)` and `Refresh()`.
-- See docs/design/workspace.md.
Stockist.Panels = Stockist.NewRegistry("panel")
