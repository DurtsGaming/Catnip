-- Translations: every file shows its text as L["English text"]. The keys are the English text, so
-- English needs no entries, and a key another language hasn't translated shows in English. Each
-- other language has a file next to this one (zhCN.lua...), kept in step with the code by
-- tools/locales.py. Spell names come from the game instead (ns.SpellName), already translated.
local addonName, ns = ...

ns.L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})
