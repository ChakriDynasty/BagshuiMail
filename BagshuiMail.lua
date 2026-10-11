-- One mailbox button. Each Bagshui category named after a bank alt
-- is mailed to that character. TurtleMail sends the letters if it is loaded.

local ALTS = {
	madaore = "Madaore",
	madacloth = "Madacloth",
	madaleather = "Madaleather",
	madafood = "Madafood",
	madawood = "Madawood",
	madaherb = "Madaherb",
	madajunk = "Madajunk",
	madaboe = "Madaboe",
}

-- One stack per letter. The recipient is chosen from the item in the slot
-- at the moment TurtleMail picks it up.
local pending = 0
local sending = false
local advance = false
local lastProgress = 0
local skipped = {}
local statusText
local sendButton
local hooked = false

local function say(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffBagshuiMail|r: " .. text)
end

local function setStatus(text)
	if statusText then
		statusText:SetText(text)
	end
end

local function soulbound(item)
	local tip = item.tooltip or ""
	if ITEM_SOULBOUND and string.find(tip, ITEM_SOULBOUND, 1, true) then
		return true
	end
	if string.find(tip, "Soulbound", 1, true) then
		return true
	end
	return false
end

local function questItem(item)
	return item.type == "Quest"
end

local function bagshuiParts()
	if not Bagshui or not Bagshui.components then
		return nil
	end
	return Bagshui.components.Bags, Bagshui.components.Categories, Bagshui.components.ItemInfo
end

local function altCategories(categories)
	local list = {}
	if not categories or not categories.list then
		return list
	end
	for id, category in pairs(categories.list) do
		local name = category.name
		local key = name and string.lower(name)
		if key and ALTS[key] then
			table.insert(list, {
				id = id,
				name = ALTS[key],
				sequence = category.sequence or 100,
			})
		elseif name == "Bind on Equip" then
			table.insert(list, { id = id, name = "Madaboe", sequence = category.sequence or 89 })
		end
	end
	table.sort(list, function(a, b)
		if a.sequence == b.sequence then
			return a.name < b.name
		end
		return a.sequence < b.sequence
	end)
	return list
end

local function containerItemId(bag, slot)
	local link = GetContainerItemLink(bag, slot)
	if not link then
		return nil
	end
	local _, _, id = string.find(link, "item:(%d+)")
	return tonumber(id)
end

local function altNameForCategoryId(categories, categoryId)
	if not categories or not categories.list or categoryId == nil or categoryId == "" then
		return nil
	end
	local category = categories.list[categoryId]
	if not category and tonumber(categoryId) then
		category = categories.list[tonumber(categoryId)]
	end
	if not category or not category.name then
		return nil
	end
	local key = string.lower(category.name)
	if ALTS[key] then
		return ALTS[key]
	end
	if category.name == "Bind on Equip" then
		return "Madaboe"
	end
	return nil
end

local function liveItem(itemInfo, bag, slot)
	local link = GetContainerItemLink(bag, slot)
	if not link or not itemInfo then
		return nil
	end
	local item = {}
	if not itemInfo:Get(link, item, true, true) then
		return nil
	end
	if not item.id or item.id == 0 then
		return nil
	end
	item.bagNum = bag
	item.slotNum = slot
	return item
end

local function recipientFor(categories, cats, bags, item)
	local cached = bags and bags.inventory and bags.inventory[item.bagNum] and bags.inventory[item.bagNum][item.slotNum]
	if cached and cached.id == item.id and cached.bagNum == item.bagNum and cached.slotNum == item.slotNum then
		local shown = altNameForCategoryId(categories, cached.bagshuiCategoryId)
		if shown then
			return shown
		end
	end
	local i
	for i = 1, getn(cats) do
		if categories:MatchCategory(cats[i].id, item) then
			return cats[i].name
		end
	end
	return nil
end

local function nextStack()
	local bags, categories, itemInfo = bagshuiParts()
	if not bags or not categories or not itemInfo then
		return nil, "Bagshui is not ready."
	end
	local cats = altCategories(categories)
	if getn(cats) == 0 then
		return nil, "Bagshui has no alt categories."
	end
	local me = UnitName("player")
	local bag
	for bag = 0, 4 do
		local slots = GetContainerNumSlots(bag)
		local slot
		for slot = 1, slots do
			local key = bag .. ":" .. slot
			if not skipped[key] then
				local _, count, locked = GetContainerItemInfo(bag, slot)
				if count and count > 0 and locked ~= 1 then
					local item = liveItem(itemInfo, bag, slot)
					if item and not soulbound(item) and not questItem(item) then
						local who = recipientFor(categories, cats, bags, item)
						if who and (not me or string.lower(me) ~= string.lower(who)) then
							return {
								bag = bag,
								slot = slot,
								id = item.id,
								name = who,
								itemName = item.name or "Item",
							}
						end
					end
				end
			end
		end
	end
	return nil
end

local function stop(reason)
	sending = false
	pending = 0
	advance = false
	lastProgress = 0
	skipped = {}
	if MailFrame and MailFrame:IsVisible() and TurtleMail and TurtleMail.sendmail_clear then
		TurtleMail.sendmail_clear()
	end
	if sendButton then
		sendButton:Enable()
	end
	setStatus(reason)
	say(reason)
end

local function turtleReady()
	return TurtleMail
		and TurtleMail.sendmail_clear
		and TurtleMail.sendmail_set_attachment
		and TurtleMail.send_mail_button_onclick
end

-- TurtleMail picks the bag slot up when Send is pressed. Check the item id
-- immediately before that, and send only that one stack.
local function sendOne(stack)
	if containerItemId(stack.bag, stack.slot) ~= stack.id then
		return false
	end
	MailFrameTab_OnClick(2)
	TurtleMail.sendmail_clear()
	if containerItemId(stack.bag, stack.slot) ~= stack.id then
		return false
	end
	if not TurtleMail.sendmail_set_attachment({ stack.bag, stack.slot }) then
		skipped[stack.bag .. ":" .. stack.slot] = true
		TurtleMail.sendmail_clear()
		return false
	end
	if containerItemId(stack.bag, stack.slot) ~= stack.id then
		skipped[stack.bag .. ":" .. stack.slot] = true
		TurtleMail.sendmail_clear()
		return false
	end
	SendMailNameEditBox:SetText(stack.name)
	MailSubjectEditBox:SetText(stack.name)
	SendMailBodyEditBox:SetText("")
	TurtleMail.send_mail_button_onclick()
	return true
end

local function sendNext()
	local stack, err = nextStack()
	if not stack then
		if err then
			stop(err)
		else
			stop("Done.")
		end
		return
	end
	local price = GetSendMailPrice() or 30
	if GetMoney() < price then
		stop("Not enough money for postage.")
		return
	end
	pending = 1
	lastProgress = GetTime()
	setStatus(stack.itemName .. " to " .. stack.name)
	if not sendOne(stack) then
		advance = true
		return
	end
	say(stack.itemName .. " to " .. stack.name)
end

local function beginSend()
	if sending then
		return
	end
	if not MailFrame or not MailFrame:IsVisible() then
		say("Open the mailbox first.")
		return
	end
	if not turtleReady() then
		say("Enable TurtleMail, then open the mailbox again.")
		return
	end
	skipped = {}
	local stack, err = nextStack()
	if not stack then
		setStatus(err or "Nothing in those categories to send.")
		return
	end
	sending = true
	lastProgress = GetTime()
	if sendButton then
		sendButton:Disable()
	end
	sendNext()
end

local function onSendSuccess()
	if not sending then
		return
	end
	pending = pending - 1
	lastProgress = GetTime()
	if pending <= 0 then
		-- This batch is finished. TurtleMail's own update has already
		-- cleared its send flag, so the next alt can use Send again.
		advance = true
	else
		setStatus(pending .. " letters left in this batch.")
	end
end

local function onError()
	if not sending then
		return
	end
	local msg = arg1 or ""
	if msg == ERR_MAIL_REACHED_CAP or msg == ERR_MAIL_TARGET_NOT_FOUND or msg == ERR_MAIL_TO_SELF or msg == ERR_PLAYER_WRONG_FACTION then
		stop("Stopped: " .. msg)
	end
end

local function showTab()
	InboxFrame:Hide()
	SendMailFrame:Hide()
	if TurtleMailLogFrame then
		TurtleMailLogFrame:Hide()
	end
	BagshuiMailFrame:Show()
	PanelTemplates_SetTab(MailFrame, 4)
end

local function installHook()
	if hooked or not MailFrameTab_OnClick then
		return
	end
	local orig = MailFrameTab_OnClick
	MailFrameTab_OnClick = function(tab)
		if not tab then
			tab = this:GetID()
		end
		if tab == 4 then
			showTab()
			return
		end
		if BagshuiMailFrame then
			BagshuiMailFrame:Hide()
		end
		orig(tab)
	end
	hooked = true
end

local function placeTab()
	if not MailFrameTab4 then
		return
	end
	local anchor = MailFrameTab2
	if MailFrameTab3 and MailFrameTab3:IsShown() then
		anchor = MailFrameTab3
	end
	MailFrameTab4:ClearAllPoints()
	MailFrameTab4:SetPoint("LEFT", anchor, "RIGHT", -16, 0)
end

local function build()
	if BagshuiMailFrame then
		return
	end
	installHook()
	local tab = CreateFrame("Button", "MailFrameTab4", MailFrame, "FriendsFrameTabTemplate")
	tab:SetID(4)
	tab:SetText("Alts")
	tab:SetScript("OnClick", function()
		MailFrameTab_OnClick(4)
	end)
	if PanelTemplates_SetNumTabs then
		PanelTemplates_SetNumTabs(MailFrame, 4)
	end
	placeTab()

	local frame = CreateFrame("Frame", "BagshuiMailFrame", MailFrame)
	frame:SetPoint("TOPLEFT", MailFrame, "TOPLEFT", 16, -70)
	frame:SetPoint("BOTTOMRIGHT", MailFrame, "BOTTOMRIGHT", -16, 40)
	frame:Hide()

	sendButton = CreateFrame("Button", "BagshuiMailSendButton", frame, "UIPanelButtonTemplate")
	sendButton:SetWidth(180)
	sendButton:SetHeight(28)
	sendButton:SetPoint("TOP", frame, "TOP", 0, -24)
	sendButton:SetText("Send to alts")
	sendButton:SetScript("OnClick", beginSend)

	statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	statusText:SetPoint("TOP", sendButton, "BOTTOM", 0, -16)
	statusText:SetWidth(280)
	statusText:SetJustifyH("CENTER")
	statusText:SetText("Sends each category to the alt with the same name.")
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("MAIL_SHOW")
events:RegisterEvent("MAIL_CLOSED")
events:RegisterEvent("MAIL_SEND_SUCCESS")
events:RegisterEvent("UI_ERROR_MESSAGE")
events:SetScript("OnUpdate", function()
	if not sending then
		return
	end
	if advance then
		advance = false
		sendNext()
		return
	end
	if lastProgress > 0 and (GetTime() - lastProgress) > 20 then
		stop("Stopped. Close the mailbox if letters are still going out.")
	end
end)
events:SetScript("OnEvent", function()
	if event == "PLAYER_LOGIN" or event == "MAIL_SHOW" then
		build()
		placeTab()
	elseif event == "MAIL_CLOSED" then
		if sending then
			stop("Mailbox closed.")
		end
	elseif event == "MAIL_SEND_SUCCESS" then
		onSendSuccess()
	elseif event == "UI_ERROR_MESSAGE" then
		onError()
	end
end)
