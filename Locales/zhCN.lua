-- Simplified Chinese (zhCN) translation for Catnip.
--
-- To translate a line, remove the "-- " in front and type the translation between the empty
-- quotes:
--     -- L["Reset"] = ""
-- becomes
--     L["Reset"] = "..."
-- The key in L["..."] is the English text: leave it exactly as it is. Untranslated lines show in
-- English. Keep %s (a name or text) and %d (a number) in the translation; if the sentence needs
-- two of them in the other order, number them: %2$d ... %1$s. Spell names (Rake, Prowl...) come
-- from the game already translated, so they aren't listed here.
--
-- This file is rewritten by tools/locales.py, which keeps your translations and adds new text as
-- it appears. Only edit the L[...] lines; other changes here are lost.
if GetLocale() ~= "zhCN" then
    return
end
local addonName, ns = ...
local L = ns.L

-- Catnip.lua
L["open settings"] = "打开设置"
L["settings and Edit Mode"] = "设置和编辑模式"
L["debug messages on or off"] = "开启或关闭调试信息"
L["tools for testing and development"] = "测试和开发工具"
L["Debug messages on"] = "调试信息：开启"
L["Debug messages off"] = "调试信息：关闭"

-- Elements.lua
L["Above"] = "上方"
L["Circle"] = "圆环"
L["Fill"] = "填充"
L["Ring"] = "外环"
L["Below"] = "下方"
L["Arcs and Orbs"] = "弧条和光球"
L["Text"] = "文字"
L["None"] = "无"
L["Thin"] = "细"
L["Thick"] = "粗"
L["Font"] = "字体"
L["Size"] = "大小"
L["Outline"] = "描边"

-- UnlockOverlay.lua
L["Click to edit"] = "点击编辑"

-- Layout.lua
L["Rotation Frame"] = "循环框体"
L["Stealth Mode"] = "潜行模式"
L["Enabled"] = "启用"
L["Opacity while stealthed"] = "潜行时不透明度"

-- Resource.lua
L["Resource Circle"] = "资源圆环"
L["Fill opacity"] = "填充不透明度"
L["Background opacity"] = "背景不透明度"
L["Border opacity"] = "边框不透明度"
L["Mana as"] = "法力值显示为"
L["Percent"] = "百分比"
L["Value"] = "数值"
L["Resource Value"] = "资源数值"

-- ComboPoints.lua
L["Combo Points"] = "连击点数"
L["Opacity"] = "不透明度"

-- ComboRings.lua
L["Angular"] = "棱角"
L["Circular"] = "圆形"
L["Shows"] = "显示"
L["Segments"] = "分段"
L["Combo Ring %d"] = "连击点外环 %d"

-- Swing.lua
L["Swing Time"] = "攻击计时"
L["Swing Timer"] = "平砍计时条"
L["Bar opacity"] = "计时条不透明度"
L["Color"] = "颜色"
L["Maul queued color"] = "槌击排队颜色"
L["Maul Orb"] = "槌击光球"
L["The swing timer isn't supported in this version of the game."] = "当前游戏版本不支持平砍计时条。"

-- StealthSmoke.lua
L["Stealth Smoke"] = "潜行烟雾"

-- Cast.lua
L["Cast Time"] = "施法计时"
L["Swing/Cast Timer"] = "平砍/施法计时"
L["Timer size"] = "计时文字大小"
L["Spell name size"] = "法术名称大小"
L["Match Maul color when queued"] = "槌击排队时同步颜色"
L["Cast Timer"] = "施法计时条"

-- ManaPrediction.lua
L["Mana Prediction"] = "法力消耗预测"
L["Show mana cost prediction"] = "显示法力消耗预测"

-- FiveSecondRule.lua
L["Five-Second Ring"] = "五秒规则圆环"

-- Gcd.lua
L["GCD Pie"] = "GCD 饼图"

-- Proc.lua
L["To see Clearcasting in combat, add Omen of Clarity to the Cooldown Manager's tracked buffs."] = "要在战斗中显示节能施法，请把清晰预兆加入冷却管理器的追踪的增益效果。"

-- DotRings.lua
L["Rake Duration"] = "扫击持续时间"
L["Rip Duration"] = "撕扯持续时间"
L["%s will move to combo point %d after combat."] = "%s 将在战斗结束后移到第 %d 个连击点。"
L["DoT rings aren't supported in this version of the game."] = "当前游戏版本不支持 DoT 外环。"

-- Enrage.lua
L["The Enrage tint isn't supported in this version of the game."] = "当前游戏版本不支持狂怒染色。"
L["Enrage Tint"] = "狂怒染色"

-- ShiftingPower.lua
L["Shifting Power Arc"] = "变形能量弧条"

-- GrowlArc.lua
L["Growl Arc"] = "低吼弧条"
L["Cooldown Arc"] = "冷却弧条"
L["Shifting Power ready pulse"] = "变形能量就绪闪光"

-- ShiftOrbs.lua
L["Shift Orbs"] = "变形光球"
L["Show almost-ready orb"] = "显示即将就绪的光球"

-- CooldownRings.lua
L["Faerie Fire Cooldown"] = "精灵之火冷却"
L["Primal Bite Cooldown"] = "原始撕咬冷却"

-- OmenRing.lua
L["Omen of Clarity Internal Cooldown"] = "清晰预兆内置冷却"

-- CooldownItems.lua
L["Potions (%s)"] = "药水（%s）"
L["Potions"] = "药水"
L["%s has no Use: effect, so there's no cooldown to track."] = "%s 没有“使用：”效果，没有可追踪的冷却。"
L["Tracking Potions: %s's buff will light up the Potions icon."] = "追踪药水：%s 的增益效果会点亮药水图标。"

-- Cooldowns.lua
L["Cooldown Frame"] = "冷却框体"

-- EditMode.lua
L["Catnip Edit Mode"] = "Catnip 编辑模式"
L["Drag a frame to move it. Click it for its settings."] = "拖动框体以移动，点击打开其设置。"
L["Reset Positions"] = "重置位置"
L["Done"] = "完成"

-- BlizzardEditMode.lua
L["Catnip Settings"] = "Catnip 设置"
L["Edit Mode can't open in combat."] = "战斗中无法打开编辑模式。"

-- Preview.lua
L["Caster"] = "人形态"
L["Bear"] = "熊"
L["Cat"] = "豹"

-- Options.lua
L["The color picker isn't available in this version of the game."] = "当前游戏版本无法使用颜色选择器。"
L["General (%s)"] = "通用（%s）"
L["Disabled"] = "禁用"
L["Move in Edit Mode"] = "在编辑模式中移动"
L["Reset..."] = "重置…"
L["Reset %s"] = "重置%s"
L["Reset"] = "重置"
L["Cancel"] = "取消"
L["General"] = "通用"
L["Blizzard UI"] = "暴雪界面"
L["Hide Blizzard's cast bar"] = "隐藏暴雪施法条"
L["Blizzard's cast bar will change after combat."] = "暴雪施法条将在战斗结束后更改。"
L["Hide Action Bar 1"] = "隐藏动作条 1"
L["Hide Stance Bar"] = "隐藏姿态条"
L["Keybinds still work while the bars are hidden."] = "隐藏动作条后，按键绑定仍然有效。"
L["Troubleshooting"] = "故障排查"
L["Debug messages in chat"] = "在聊天框显示调试信息"
L["Rotation"] = "循环"
L["Resets every element, plus the frame's scale, opacity and position."] = "重置所有元素，以及框体的缩放、不透明度和位置。"
L["Scale"] = "缩放"
L["Overall opacity"] = "整体不透明度"
L["Horizontal position"] = "水平位置"
L["Vertical position"] = "垂直位置"
L["Preview"] = "预览"
L["Stealth"] = "潜行"
L["Reset to defaults"] = "恢复默认设置"
L["Default font and outline. Elements can choose their own."] = "默认字体和描边，各元素可单独设置。"
L["Cooldown"] = "冷却"
L["Resets the frame's size, position, icons and opacity. Your tracked abilities are kept."] = "重置框体的大小、位置、图标和不透明度，已追踪的技能会保留。"
L["Height"] = "高度"
L["Width"] = "宽度"
L["Abilities"] = "技能"
L["Check the abilities to show, then drag them to set their order. Higher ones sit closer to the anchor (see Alignment). Unchecked items are removed from the list."] = "勾选要显示的技能，再拖动调整顺序。越靠上的越靠近锚点（见“对齐”）。未勾选的物品会从列表中移除。"
L["No abilities with a cooldown found."] = "没有找到有冷却时间的技能。"
L["Drop an item here to track it"] = "把物品拖到这里进行追踪"
L["Items with a Use: effect, like trinkets, get their own icon. All potions share one Potions icon, which lights up while a potion's buff is active."] = "带“使用：”效果的物品（如饰品）各有自己的图标。所有药水共用一个药水图标，药水的增益效果生效时会点亮。"
L["Icons"] = "图标"
L["Icon size"] = "图标尺寸"
L["Overflow"] = "溢出"
L["Hide"] = "隐藏"
L["Spill"] = "溢出显示"
L["When icons don't fit: hide the lowest-priority ones, or let them spill past the edge."] = "图标放不下时：隐藏优先级最低的，或让它们溢出到边框外。"
L["Active opacity"] = "生效时不透明度"
L["Inactive opacity"] = "未生效时不透明度"
L["Alignment"] = "对齐"
L["Where icons gather inside the frame."] = "图标在框体内聚集的位置。"
L["To show countdown numbers, turn on Options > Action Bars > Show Numbers for Cooldowns."] = "要显示倒计时数字，请开启 选项 > 动作条 > 显示冷却时间。"

-- AddOnsPage.lua
L["Open Catnip Settings"] = "打开 Catnip 设置"
L["or type /catnip"] = "或输入 /catnip"
