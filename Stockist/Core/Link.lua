local ADDON_NAME, Stockist = ...

-- Link groups: panels with the same group name follow the same selected item. Selecting an item in
-- one panel (a click in the watchlist, say) fires LINK_SELECTED and every linked panel switches to it.
--   Stockist.Link.Select("A", 2589)    a panel chose an item
--   Stockist.Link.Get("A")             the group's current item (nil if none yet)
--   Events:On("LINK_SELECTED", function(group, itemID) ... end)
-- Selections live for the session only.
local Link = { selected = {} }
Stockist.Link = Link

function Link.Select(group, itemID)
    if not group or not itemID then return end
    Link.selected[group] = itemID
    Stockist.Events:Fire("LINK_SELECTED", group, itemID)
end

function Link.Get(group)
    return group and Link.selected[group] or nil
end
