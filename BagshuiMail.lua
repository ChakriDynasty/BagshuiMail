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

-- TurtleMail.sendmail_load builds 21 attachment slots and sends them
-- one letter at a time from MAIL_SEND_SUCCESS.
local BATCH = 21
local queue = {}
local pending = 0
local sending = false
local advance = false
local lastProgress = 0
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

local function altCategories()
	local list = {}
	if not BsCategories or not BsCategories.list then
		return list
	end
	for id, category in pairs(BsCategories.list) do
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

local function itemForSlot(bag, slot)
	local link = GetContainerItemLink(bag, slot)
	if not link or not BsItemInfo then
		return nil
	end
	local item = {}
	BsItemInfo:Get(link, item, true, true)
	if not item.id or item.id == 0 then
		return nil
	end
	item.bagNum = bag
	item.slotNum = slot
	return item
end

local function collect()
	local cats = altCategories()
	local found = {}
	local bag
	for bag = 0, 4 do
		local slots = GetContainerNumSlots(bag)
		local slot
		for slot = 1, slots do
			local _, count, locked = GetContainerItemInfo(bag, slot)
			if count and count > 0 and locked ~= 1 then
				local item = itemForSlot(bag, slot)
				if item and not soulbound(item) and not questItem(item) then
					local i
					for i = 1, getn(cats) do
						if BsCategories:MatchCategory(cats[i].id, item) then
							table.insert(found, { bag, slot, cats[i].name })
							break
						end
					end
				end
			end
		end
	end
	return found
end

local function batchesFrom(found, size)
	local byName = {}
	local order = {}
	local i
	for i = 1, getn(found) do
		local name = found[i][3]
		if not byName[name] then
			byName[name] = {}
			table.insert(order, name)
		end
		table.insert(byName[name], { found[i][1], found[i][2] })
	end
	local out = {}
	for i = 1, getn(order) do
		local name = order[i]
		local items = byName[name]
		local startAt = 1
		while startAt <= getn(items) do
			local batch = {}
			local n = startAt
			while n <= getn(items) and getn(batch) < size do
				table.insert(batch, items[n])
				n = n + 1
			end
			table.insert(out, { name = name, items = batch })
			startAt = n
		end
	end
	return out
end

local function stop(reason)
	sending = false
	pending = 0
	advance = false
	lastProgress = 0
	queue = {}
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

-- Same steps as using TurtleMail by hand:
-- open the Send tab, clear the attachment row, right-click each stack on,
-- type the alt, press Send. TurtleMail then mails one stack per letter.
local function sendLikeTurtleMail(batch)
	MailFrameTab_OnClick(2)
	TurtleMail.sendmail_clear()
	local attached = 0
	local i
	for i = 1, getn(batch.items) do
		if TurtleMail.sendmail_set_attachment(batch.items[i]) then
			attached = attached + 1
		end
	end
	if attached == 0 then
		return 0
	end
	SendMailNameEditBox:SetText(batch.name)
	MailSubjectEditBox:SetText(batch.name)
	SendMailBodyEditBox:SetText("")
	TurtleMail.send_mail_button_onclick()
	return attached
end

local function startNext()
	if getn(queue) == 0 then
		stop("Done.")
		return
	end
	local batch = table.remove(queue, 1)
	local me = UnitName("player")
	if me and string.lower(me) == string.lower(batch.name) then
		setStatus("Skipped " .. batch.name .. " (that is this character).")
		advance = true
		return
	end
	local price = GetSendMailPrice() or 30
	if GetMoney() < price * getn(batch.items) then
		stop("Not enough money for postage.")
		return
	end
	pending = sendLikeTurtleMail(batch)
	lastProgress = GetTime()
	if pending == 0 then
		setStatus("Nothing mailable for " .. batch.name .. ".")
		advance = true
		return
	end
	setStatus("Sending " .. pending .. " to " .. batch.name)
	say("Sending " .. pending .. " to " .. batch.name)
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
	local found = collect()
	if getn(found) == 0 then
		setStatus("Nothing in those categories to send.")
		return
	end
	queue = batchesFrom(found, BATCH)
	sending = true
	lastProgress = GetTime()
	if sendButton then
		sendButton:Disable()
	end
	say("Sending " .. getn(found) .. " stacks.")
	startNext()
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
		startNext()
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
