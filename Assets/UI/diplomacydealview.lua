-- ===========================================================================
-- Diplomacy Trade View Manager
-- ===========================================================================
include( "InstanceManager" );
include( "Civ6Common" ); -- AutoSizeGridButton
include( "SupportFunctions" ); -- DarkenLightenColor
include( "PopupDialogSupport" );
include( "ToolTipHelper_PlayerYields" );

-- ===========================================================================
--	VARIABLES
-- ===========================================================================
local ms_PlayerPanelIM		:table		= InstanceManager:new( "PlayerAvailablePanel",  "Root" );
local ms_IconOnlyIM			:table		= InstanceManager:new( "IconOnly",  "SelectButton", Controls.IconOnlyContainer );
local ms_IconAndTextIM		:table		= InstanceManager:new( "IconAndText",  "SelectButton", Controls.IconAndTextContainer );
local ms_LeftRightListIM	:table		= InstanceManager:new( "LeftRightList",  "List", Controls.LeftRightListContainer );
local ms_TopDownListIM		:table		= InstanceManager:new( "TopDownList",  "List", Controls.TopDownListContainer );

local ms_ValueEditDealItemID = -1;		-- The ID of the deal item that is being value edited.
local ms_ValueEditDealItemControlTable = nil; -- The control table of the deal item that is being edited.

local OTHER_PLAYER = 0;
local LOCAL_PLAYER = 1;

local ms_LocalPlayerPanel = {};
local ms_OtherPlayerPanel = {};

local ms_LocalPlayer =		nil;
local ms_OtherPlayer =		nil;
local ms_OtherPlayerID =	-1;
local ms_OtherPlayerIsHuman = false;

local ms_InitiatedByPlayerID = -1;

local ms_bIsDemand = false;
local ms_bExiting = false;

local ms_LastIncomingDealProposalAction = DealProposalAction.PENDING;

local m_kPopupDialog			:table; -- Will use custom "popup" since in leader mode the Popup stack is disabled.

local AvailableDealItemGroupTypes = {};
AvailableDealItemGroupTypes.GOLD				= 1;
AvailableDealItemGroupTypes.LUXURY_RESOURCES	= 2;
AvailableDealItemGroupTypes.STRATEGIC_RESOURCES	= 3;
AvailableDealItemGroupTypes.AGREEMENTS			= 4;
AvailableDealItemGroupTypes.CITIES				= 5;
AvailableDealItemGroupTypes.OTHER_PLAYERS		= 6;
AvailableDealItemGroupTypes.GREAT_WORKS			= 7;
AvailableDealItemGroupTypes.CAPTIVES			= 8;

AvailableDealItemGroupTypes.COUNT				= 8;

local ms_AvailableGroups = {};

-----------------------

local DealItemGroupTypes = {};
DealItemGroupTypes.GOLD			= 1;
DealItemGroupTypes.RESOURCES	= 2;
DealItemGroupTypes.AGREEMENTS	= 3;
DealItemGroupTypes.CITIES		= 4;
DealItemGroupTypes.GREAT_WORKS	= 5;
DealItemGroupTypes.CAPTIVES		= 6;

DealItemGroupTypes.COUNT		= 6;

local ms_DealGroups = {};

local ms_DealAgreementsGroup = {};

local ms_DefaultOneTimeGoldAmount = 100;

local ms_DefaultMultiTurnGoldAmount = 10;
local ms_DefaultMultiTurnGoldDuration = 30;

local ms_bForceUpdateOnCommit = false;

--CQUI Addition
local YIELD_FONT_ICONS:table = {
        YIELD_FOOD				= "[ICON_FoodLarge]",
        YIELD_PRODUCTION		= "[ICON_ProductionLarge]",
        YIELD_GOLD				= "[ICON_GoldLarge]",
        YIELD_SCIENCE			= "[ICON_ScienceLarge]",
        YIELD_CULTURE			= "[ICON_CultureLarge]",
        YIELD_FAITH				= "[ICON_FaithLarge]",
        TourismYield			= "[ICON_TourismLarge]"
        };

-- ===========================================================================
function SetIconToSize(icon, iconName, iconSize)
	if iconSize == nil then
		iconSize = 50;
	end
	local x, y, szIconName, iconSize = IconManager:FindIconAtlasNearestSize(iconName, iconSize, true);
	icon.Icon:SetTexture(x, y, szIconName);
	icon.Icon:SetSizeVal(iconSize, iconSize);
end

-- ===========================================================================
function InitializeDealGroups()

	for i = 1, AvailableDealItemGroupTypes.COUNT, 1 do
		ms_AvailableGroups[i] = {};
	end

	for i = 1, DealItemGroupTypes.COUNT, 1 do
		ms_DealGroups[i] = {};
	end

end
InitializeDealGroups();

-- ===========================================================================
function GetPlayerType(player : table)
	if (player:GetID() == ms_LocalPlayer:GetID()) then
		return LOCAL_PLAYER;
	end

	return OTHER_PLAYER;
end

-- ===========================================================================
function GetPlayerOfType(playerType : number)
	if (playerType == LOCAL_PLAYER) then
		return ms_LocalPlayer;
	end

	return ms_OtherPlayer;
end

-- ===========================================================================
function GetOtherPlayer(player : table)
	if (player ~= nil and player:GetID() == ms_OtherPlayer:GetID()) then
		return ms_LocalPlayer;
	end

	return ms_OtherPlayer;
end

-- ===========================================================================
function SetDefaultLeaderDialogText()
	if (ms_bIsDemand == true and ms_InitiatedByPlayerID == ms_OtherPlayerID) then
		Controls.LeaderDialog:LocalizeAndSetText("LOC_DIPLO_DEMAND_INTRO");
	else
		Controls.LeaderDialog:LocalizeAndSetText("LOC_DIPLO_DEAL_INTRO");
	end
end

-- ===========================================================================
function ProposeWorkingDeal(bIsAutoPropose : boolean)
	if (bIsAutoPropose == nil) then
		bIsAutoPropose = false;
	end

	if (not DealManager.HasPendingDeal(ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID())) then
		if (ms_bIsDemand) then
			DealManager.SendWorkingDeal(DealProposalAction.DEMANDED, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
		else
			if (bIsAutoPropose) then
				DealManager.SendWorkingDeal(DealProposalAction.INSPECT, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
			else
				DealManager.SendWorkingDeal(DealProposalAction.PROPOSED, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
			end
		end
	end
end

-- ===========================================================================
function RequestEqualizeWorkingDeal()
	if (not DealManager.HasPendingDeal(ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID())) then
		DealManager.SendWorkingDeal(DealProposalAction.EQUALIZE, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
	end
end

-- ===========================================================================
function DealIsEmpty()
	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
	if (pDeal == nil or pDeal:GetItemCount() == 0) then
		return true;
	end

	return false;
end

-- ===========================================================================
-- Update the proposed working deal.  This is called as items are changed in the deal.
-- It is primarily used to 'auto-propose' the deal when working with an AI.
function UpdateProposedWorkingDeal()
	if (ms_LastIncomingDealProposalAction ~= DealProposalAction.PENDING or IsAutoPropose()) then 

		local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
		if (pDeal == nil or pDeal:GetItemCount() == 0 or ms_bIsDemand) then
			-- Is a demand or no items, restart
			ms_LastIncomingDealProposalAction = DealProposalAction.PENDING;
			UpdateDealStatus();
		else
			if (IsAutoPropose()) then
				ProposeWorkingDeal(IsAutoPropose());
			end
		end
	end
end

--	Displays the leader's name (with screen name if you are a human in a multiplayer game), along with the civ name,
--	and the icon of the civ with civ colors.  When you mouse over the civ icon, you should see a full list of all cities.
--	This should help players differentiate between duplicate civs.
function PopulateSignatureArea(player:table)
	-- Set colors for the Civ icon
	if (player ~= nil) then
		m_primaryColor, m_secondaryColor  = UI.GetPlayerColors( player:GetID() );
		local darkerBackColor = DarkenLightenColor(m_primaryColor,(-85),100);
		local brighterBackColor = DarkenLightenColor(m_primaryColor,90,255);
		Controls.CivBacking_Base:SetColor(m_primaryColor);
		Controls.CivBacking_Lighter:SetColor(brighterBackColor);
		Controls.CivBacking_Darker:SetColor(darkerBackColor);
		Controls.CivIcon:SetColor(m_secondaryColor);
	end

	-- Set the leader name, civ name, and civ icon data
	local leader:string = PlayerConfigurations[player:GetID()]:GetLeaderTypeName();
	if GameInfo.CivilizationLeaders[leader] == nil then
		UI.DataError("Banners found a leader \""..leader.."\" which is not/no longer in the game; icon may be whack.");
	else
		if(GameInfo.CivilizationLeaders[leader].CivilizationType ~= nil) then
			local civTypeName = GameInfo.CivilizationLeaders[leader].CivilizationType
			local civIconName = "ICON_"..civTypeName;
			Controls.CivIcon:SetIcon(civIconName);
			Controls.CivName:SetText(Locale.ToUpper(Locale.Lookup(GameInfo.Civilizations[civTypeName].Name)));
			local leaderName = Locale.ToUpper(Locale.Lookup(GameInfo.Leaders[leader].Name))
			local playerName = PlayerConfigurations[player:GetID()]:GetPlayerName();
			if GameConfiguration.IsAnyMultiplayer() and player:IsHuman() then
				leaderName = leaderName .. " ("..Locale.ToUpper(playerName)..")"
			end
			Controls.LeaderName:SetText(leaderName);

			--Create a tooltip which shows a list of this Civ's cities
			local civTooltip = Locale.Lookup(GameInfo.Civilizations[civTypeName].Name);
			local pPlayerConfig = PlayerConfigurations[player:GetID()];
			local playerName = pPlayerConfig:GetPlayerName();
			local playerCities = player:GetCities();
			if(playerCities ~= nil) then
				civTooltip = civTooltip .. "[NEWLINE]"..Locale.Lookup("LOC_PEDIA_CONCEPTS_PAGEGROUP_CITIES_NAME").. ":[NEWLINE]----------";
				for i,city in playerCities:Members() do
					civTooltip = civTooltip.. "[NEWLINE]".. Locale.Lookup(city:GetName());
				end
			end
			Controls.CivIcon:SetToolTipString(Locale.Lookup(civTooltip));
		end
	end
	Controls.SignatureStack:CalculateSize();
	Controls.SignatureStack:ReprocessAnchoring();
end

-- ===========================================================================
function UpdateOtherPlayerText(otherPlayerSays)
	local bHide = true;
	if (ms_OtherPlayer ~= nil and otherPlayerSays ~= nil) then
		local playerConfig = PlayerConfigurations[ms_OtherPlayer:GetID()];
		if (playerConfig ~= nil) then
			-- Set the leader name
			local leaderDesc = playerConfig:GetLeaderName();
			Controls.OtherPlayerBubbleName:SetText(Locale.ToUpper(Locale.Lookup("LOC_DIPLOMACY_DEAL_OTHER_PLAYER_SAYS", leaderDesc)));
		end
	end
	-- When we get dialog for what the leaders say during a trade, we can add it here!
end

-- ===========================================================================
function OnToggleCollapseGroup(iconList : table)
	if (iconList.ListStack:IsHidden()) then
		iconList.ListStack:SetHide(false);
	else
		iconList.ListStack:SetHide(true);
	end

	iconList.List:CalculateSize();
	iconList.List:ReprocessAnchoring();
end
-- ===========================================================================
function CreateHorizontalGroup(rootStack : table, title : string)
	local iconList = ms_LeftRightListIM:GetInstance(rootStack);
	if (title == nil or title == "") then
		iconList.Title:SetHide(true);		-- No title
	else
		iconList.TitleText:LocalizeAndSetText(title);
	end
	iconList.List:CalculateSize();
	iconList.List:ReprocessAnchoring();

	return iconList;
end

-- ===========================================================================
function CreateVerticalGroup(rootStack : table, title : string)
	local iconList = ms_TopDownListIM:GetInstance(rootStack);
	if (title == nil or title == "") then
		iconList.Title:SetHide(true);		-- No title
	else
		iconList.TitleText:LocalizeAndSetText(title);
	end
	iconList.List:CalculateSize();
	iconList.List:ReprocessAnchoring();

	return iconList;
end


-- ===========================================================================
function CreatePlayerAvailablePanel(playerType : number, rootControl : table)

	--local playerPanel = ms_PlayerPanelIM:GetInstance(rootControl);

	ms_AvailableGroups[AvailableDealItemGroupTypes.GOLD][playerType]				= CreateHorizontalGroup(rootControl);
	ms_AvailableGroups[AvailableDealItemGroupTypes.LUXURY_RESOURCES][playerType]	= CreateHorizontalGroup(rootControl, "LOC_DIPLOMACY_DEAL_LUXURY_RESOURCES");
	ms_AvailableGroups[AvailableDealItemGroupTypes.STRATEGIC_RESOURCES][playerType] = CreateHorizontalGroup(rootControl, "LOC_DIPLOMACY_DEAL_STRATEGIC_RESOURCES");
	ms_AvailableGroups[AvailableDealItemGroupTypes.AGREEMENTS][playerType]			= CreateVerticalGroup(rootControl, "LOC_DIPLOMACY_DEAL_AGREEMENTS");
	ms_AvailableGroups[AvailableDealItemGroupTypes.CITIES][playerType]				= CreateVerticalGroup(rootControl, "LOC_DIPLOMACY_DEAL_CITIES");
	ms_AvailableGroups[AvailableDealItemGroupTypes.OTHER_PLAYERS][playerType]		= CreateVerticalGroup(rootControl, "LOC_DIPLOMACY_DEAL_OTHER_PLAYERS");
	ms_AvailableGroups[AvailableDealItemGroupTypes.GREAT_WORKS][playerType]			= CreateVerticalGroup(rootControl, "LOC_DIPLOMACY_DEAL_GREAT_WORKS");
	ms_AvailableGroups[AvailableDealItemGroupTypes.CAPTIVES][playerType]			= CreateVerticalGroup(rootControl, "LOC_DIPLOMACY_DEAL_CAPTIVES");

	rootControl:CalculateSize();
	rootControl:ReprocessAnchoring();

	return playerPanel;
end

-- ===========================================================================
function CreatePlayerDealPanel(playerType : number, rootControl : table)
--This creates the containers for the offer area...
	--ms_DealGroups[DealItemGroupTypes.RESOURCES][playerType]	= CreateHorizontalGroup(rootControl);
	--ms_DealGroups[DealItemGroupTypes.AGREEMENTS][playerType]	= CreateVerticalGroup(rootControl);
	--**********************************************************************
	-- Currently putting them all in the same control.
	ms_DealGroups[DealItemGroupTypes.RESOURCES][playerType] = rootControl;
	ms_DealGroups[DealItemGroupTypes.AGREEMENTS][playerType] = rootControl;
	ms_DealGroups[DealItemGroupTypes.CITIES][playerType] = rootControl;
	ms_DealGroups[DealItemGroupTypes.GREAT_WORKS][playerType] = rootControl;
	ms_DealGroups[DealItemGroupTypes.CAPTIVES][playerType] = rootControl;

end

-- ===========================================================================
function CreateValueAmountEditOverlay()
	Controls.ValueAmountEditLeft:RegisterCallback( Mouse.eLClick, function() OnValueAmountEditDelta(-1); end );
	Controls.ValueAmountEditRight:RegisterCallback( Mouse.eLClick, function() OnValueAmountEditDelta(1); end );
	Controls.ValueAmountEdit:RegisterCommitCallback( OnValueAmountEditCommit );
	Controls.ConfirmValueEdit:RegisterCallback( Mouse.eLClick, OnValueAmountEditCommit );
end

-- ===========================================================================
function OnValuePulldownCommit(forType)

	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
	if (pDeal ~= nil) then

		local pDealItem = pDeal:FindItemByID(ms_ValueEditDealItemID);
		if (pDealItem ~= nil) then
			pDealItem:SetValueType( forType );
			
			local valueName = pDealItem:GetValueTypeNameID();
			Controls.ValueTypeEditPulldown:GetButton():LocalizeAndSetText(valueName);
			if (ms_ValueEditDealItemControlTable ~= nil) then
				-- Keep the text on the icon, that is currently hidden, up to date too.
				ms_ValueEditDealItemControlTable.ValueText:LocalizeAndSetText(pDealItem:GetValueTypeNameID(valueName));
			end

			UpdateDealStatus();
			UpdateProposedWorkingDeal();
		end
	end

end

-- ===========================================================================
function PopulateValuePulldown(pullDown, pDealItem)
	
	local possibleValues = DealManager.GetPossibleDealItems(pDealItem:GetFromPlayerID(), pDealItem:GetToPlayerID(), pDealItem:GetType(), pDealItem:GetSubType());
	if (possibleValues ~= nil) then
		pullDown:ClearEntries();
		for i, entry in ipairs(possibleValues) do

			entryControlTable = {};
			pullDown:BuildEntry( "InstanceOne", entryControlTable );

			local szItemName = Locale.Lookup(entry.ForTypeDisplayName);
			if (entry.Duration == -1) then
				local eTech = GameInfo.Technologies[entry.ForType].Index;
			    local iTurns = 	ms_LocalPlayer:GetDiplomacy():ComputeResearchAgreementTurns(ms_OtherPlayer, eTech);
				szDisplayName = Locale.Lookup("LOC_DIPLOMACY_DEAL_PARAMETER_WITH_TURNS", szItemName, iTurns);
			else
				szDisplayName = szItemName;
			end

			entryControlTable.Button:LocalizeAndSetText(szDisplayName);						
			local eType = entry.ForType;
			entryControlTable.Button:RegisterCallback(Mouse.eLClick, function()
				OnValuePulldownCommit(eType);
			end);
		end
		local valueName = pDealItem:GetValueTypeNameID();
		if (valueName ~= nil) then
			pullDown:GetButton():LocalizeAndSetText(valueName);
		else
			pullDown:GetButton():LocalizeAndSetText("LOC_DIPLOMACY_DEAL_SELECT_DEAL_PARAMETER");
		end

		pullDown:SetHide(false);
		pullDown:CalculateInternals();
	end	
end

-- ===========================================================================
function SetValueText(icon, pDealItem)

	if (icon.ValueText ~= nil) then
		local valueName = pDealItem:GetValueTypeNameID();
		if (valueName == nil) then
			if (pDealItem:HasPossibleValues()) then
				valueName = "LOC_DIPLOMACY_DEAL_CLICK_TO_CHANGE_DEAL_PARAMETER";
			end
		end
		if (valueName ~= nil) then
			icon.ValueText:LocalizeAndSetText(valueName);
			icon.ValueText:SetHide(false);
		else
			icon.ValueText:SetHide(true);
		end
	end
end

-- ===========================================================================
function CreatePanels()

	CreateValueAmountEditOverlay();

	-- Create the Other Player Panels
	CreatePlayerAvailablePanel(OTHER_PLAYER, Controls.TheirInventoryStack);

	-- Create the Local Player Panels
	CreatePlayerAvailablePanel(LOCAL_PLAYER, Controls.MyInventoryStack);

	CreatePlayerDealPanel(OTHER_PLAYER, Controls.TheirOfferStack);
	CreatePlayerDealPanel(LOCAL_PLAYER, Controls.MyOfferStack);

	Controls.EqualizeDeal:RegisterCallback( Mouse.eLClick, OnEqualizeDeal );
	Controls.EqualizeDeal:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.AcceptDeal:RegisterCallback( Mouse.eLClick, OnProposeOrAcceptDeal );
	Controls.AcceptDeal:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.DemandDeal:RegisterCallback( Mouse.eLClick, OnProposeOrAcceptDeal );
	Controls.DemandDeal:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.RefuseDeal:RegisterCallback(Mouse.eLClick, OnRefuseDeal);
	Controls.RefuseDeal:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.ResumeGame:RegisterCallback(Mouse.eLClick, OnResumeGame);
	Controls.ResumeGame:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.WhatWouldItTakeButton:RegisterCallback(Mouse.eLClick, OnEqualizeDeal);
	Controls.WhatWouldItTakeButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.WhatWouldYouGiveMe:RegisterCallback(Mouse.eLClick, OnEqualizeDeal);
	Controls.WhatWouldYouGiveMe:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

end

-- ===========================================================================
-- Find the 'instance' table from the control
function FindIconInstanceFromControl(rootControl : table)

	if (rootControl ~= nil) then
		local controlTable = ms_IconOnlyIM:FindInstanceByControl(rootControl);
		if (controlTable == nil) then
			controlTable = ms_IconAndTextIM:FindInstanceByControl(rootControl);
		end

		return controlTable;
	end

	return nil;
end

-- ===========================================================================
-- Show or hide the "amount text" or the "Value Text" sub-control of the supplied control instance
function SetHideValueText(controlTable : table, bHide : boolean)

	if (controlTable ~= nil) then
		if (controlTable.AmountText ~= nil) then
			controlTable.AmountText:SetHide(bHide);
		end
		if (controlTable.ValueText ~= nil) then
			controlTable.ValueText:SetHide(bHide);
		end
	end
end

-- ===========================================================================
-- Detach the value edit overlay from anything it is attached to.
function ClearValueEdit()

	SetHideValueText(ms_ValueEditDealItemControlTable, false);

	ms_ValueEditDealItemControlTable = nil
	ms_ValueEditDealItemID = -1;

	Controls.ValueAmountEditOverlay:SetHide(true);
	Controls.ValueTypeEditOverlay:SetHide(true);
	Controls.ValueAmountEditOverlayContainer:SetHide(true);

end

-- ===========================================================================
-- Is the deal a gift to the other player?
function IsGiftToOtherPlayer()
	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
	if (pDeal ~= nil and not ms_bIsDemand and pDeal:IsValid()) then
		local iItemsFromLocal = pDeal:GetItemCount(ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
		local iItemsFromOther = pDeal:GetItemCount(ms_OtherPlayer:GetID(), ms_LocalPlayer:GetID());

		if (iItemsFromLocal > 0 and iItemsFromOther == 0) then
			return true;
			
		end
	end

	return false;
end

-- ===========================================================================
function UpdateDealStatus()
	local bDealValid = false;
	ClearValueEdit();
	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
	if (pDeal ~= nil) then
		if (pDeal:GetItemCount() > 0) then
			bDealValid = true;
		end
	end

	if (bDealValid) then
		bDealValid = pDeal:IsValid();
	end

	Controls.EqualizeDeal:SetHide(ms_bIsDemand);

	-- Have we sent out a deal?
	local bHasPendingDeal = DealManager.HasPendingDeal(ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());

	if (not bHasPendingDeal and ms_LastIncomingDealProposalAction == DealProposalAction.PENDING) then
		-- We have yet to send out a deal.
		Controls.AcceptDeal:SetHide(true);
		local showDemand = bDealValid and ms_bIsDemand;
		Controls.DemandDeal:SetHide(not showDemand);
	else	
		local cantAccept = (ms_LastIncomingDealProposalAction ~= DealProposalAction.ACCEPTED and ms_LastIncomingDealProposalAction ~= DealProposalAction.PROPOSED and ms_LastIncomingDealProposalAction ~= DealProposalAction.ADJUSTED) or not bDealValid or bHasPendingDeal;
		Controls.AcceptDeal:SetHide(cantAccept);
		if (ms_bIsDemand) then
			if (ms_LocalPlayer:GetID() == ms_InitiatedByPlayerID) then
				-- Local human is making a demand
				if (ms_LastIncomingDealProposalAction == DealProposalAction.ACCEPTED) then
					Controls.DemandDeal:SetHide(cantAccept);
					-- The other player has accepted the demand, but we must enact it.
					-- We won't have the human need to press the accept button, just do it and exit.
					OnProposeOrAcceptDeal();
					return;
				else
					Controls.AcceptDeal:SetHide(true);
					Controls.DemandDeal:SetHide(false);
				end
			else
				Controls.DemandDeal:SetHide(true);
			end
		else
			Controls.DemandDeal:SetHide(true);
		end
	end

	UpdateProposalButtons(bDealValid);
	AutoSizeGridButton(Controls.WhatWouldYouGiveMe,100,20,10,"1");
	AutoSizeGridButton(Controls.WhatWouldItTakeButton,100,20,10,"1");
	AutoSizeGridButton(Controls.RefuseDeal,200,32,10,"1");
	AutoSizeGridButton(Controls.EqualizeDeal,200,32,10,"1");
	AutoSizeGridButton(Controls.AcceptDeal,200,41,10,"1");
	Controls.DealOptionsStack:CalculateSize();
	Controls.DealOptionsStack:ReprocessAnchoring();

end

-- ===========================================================================
-- The Human has ask to have the deal equalized.  Well, what the AI is 
-- willing to take.
function OnEqualizeDeal()
	ClearValueEdit();
	RequestEqualizeWorkingDeal();
end

-- ===========================================================================
-- Propose the deal, if this is the first time, or accept it, if the other player has
-- accepted it.
function OnProposeOrAcceptDeal()

	ClearValueEdit();

	if (ms_LastIncomingDealProposalAction == DealProposalAction.PENDING or ms_LastIncomingDealProposalAction == DealProposalAction.REJECTED) then
		ProposeWorkingDeal();
		UpdateDealStatus();
				UI.PlaySound("Confirm_Bed_Positive");
	else		
		if (ms_LastIncomingDealProposalAction == DealProposalAction.ACCEPTED or ms_LastIncomingDealProposalAction == DealProposalAction.PROPOSED or ms_LastIncomingDealProposalAction == DealProposalAction.ADJUSTED) then
			-- Any adjustments?
			if (DealManager.AreWorkingDealsEqual(ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID())) then
				-- Yes, we can accept, and exit
				DealManager.SendWorkingDeal(DealProposalAction.ACCEPTED, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());		
				OnContinue();
				UI.PlaySound("Confirm_Bed_Positive");
			else
				-- No, send an adjustment and stay in the deal view.
				DealManager.SendWorkingDeal(DealProposalAction.ADJUSTED, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());		
				UpdateDealStatus();
			end
		end
	end
end

-- ===========================================================================
function OnRefuseDeal(bForceClose)

	if (bForceClose == nil) then
		bForceClose = false;
	end

	local bHasPendingDeal = DealManager.HasPendingDeal(ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());

	local sessionID = DiplomacyManager.FindOpenSessionID(Game.GetLocalPlayer(), ms_OtherPlayer:GetID());
	if (sessionID ~= nil) then
		if (not ms_OtherPlayerIsHuman and not bHasPendingDeal) then
			-- Refusing an AI's deal
			ClearValueEdit();

			if (ms_InitiatedByPlayerID == ms_OtherPlayerID) then
				-- AI started this, so tell them that we don't want the deal
				if (bForceClose == true) then
					-- Forcing the close, usually because the turn timer expired
					DealManager.SendWorkingDeal(DealProposalAction.REJECTED, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
					DiplomacyManager.CloseSession(sessionID);
					StartExitAnimation();
				else
					DiplomacyManager.AddResponse(sessionID, Game.GetLocalPlayer(), "NEGATIVE");
				end
			else
				-- Else close the session
				DiplomacyManager.CloseSession(sessionID);
				StartExitAnimation();
			end
		else
			if (ms_OtherPlayerIsHuman) then
				if (bHasPendingDeal) then
					-- Canceling the deal with the other player.
					DealManager.SendWorkingDeal(DealProposalAction.CLOSED, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
				else
					if (ms_InitiatedByPlayerID ~= Game.GetLocalPlayer()) then
						-- Refusing the deal with the other player.
						DealManager.SendWorkingDeal(DealProposalAction.REJECTED, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
					end
				end

				DiplomacyManager.CloseSession(sessionID);
				StartExitAnimation();
			end				
		end
	else
		-- We have lost our session!
		if (not ContextPtr:IsHidden()) then
			if (not ms_bExiting) then
				OnResumeGame();
			end
		end		
	end

end

-- ===========================================================================
function OnResumeGame()

	-- Exiting back to wait for a response
	ClearValueEdit();

	local sessionID = DiplomacyManager.FindOpenSessionID(Game.GetLocalPlayer(), ms_OtherPlayer:GetID());
	if (sessionID ~= nil) then
		DiplomacyManager.CloseSession(sessionID);
	end

	-- Start the exit animation, it will call OnContinue when complete
	StartExitAnimation();
end

-- ===========================================================================
function OnExitFadeComplete()
	if(Controls.TradePanelFade:IsReversing()) then
		Controls.TradePanelFade:SetSpeed(2);
		Controls.TradePanelSlide:SetSpeed(2);

		OnContinue();
	end
end
Controls.TradePanelFade:RegisterEndCallback(OnExitFadeComplete);
-- ===========================================================================
-- Change the value number edit by a delta
function OnValueAmountEditDelta(delta : number)

	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
	if (pDeal ~= nil) then

		local pDealItem = pDeal:FindItemByID(ms_ValueEditDealItemID);
		if (pDealItem ~= nil) then
			local iNewAmount = pDealItem:GetAmount() + delta;
			if (iNewAmount < 1) then
				iNewAmount = 1;
			end

			local iMaxAmount = pDealItem:GetMaxAmount();
			if (iNewAmount > iMaxAmount) then
				iNewAmount = iMaxAmount;
			end

			if (iNewAmount ~= pDealItem:GetAmount()) then
				pDealItem:SetAmount(iNewAmount);
				ms_bForceUpdateOnCommit = true;
			end

			local newAmountStr = tostring(pDealItem:GetAmount());
			Controls.ValueAmountEdit:SetText(newAmountStr);
			if (ms_ValueEditDealItemControlTable ~= nil) then
				-- Keep the amount on the icon, that is currently hidden, up to date too.
				ms_ValueEditDealItemControlTable.AmountText:SetText(newAmountStr);
			end
		end
	end
end

-- ===========================================================================
-- Commit the value in the edit control to the deal item
function OnValueAmountEditCommit()

	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
	if (pDeal ~= nil) then

		local pDealItem = pDeal:FindItemByID(ms_ValueEditDealItemID);
		if (pDealItem ~= nil) then
			local iNewAmount = tonumber( Controls.ValueAmountEdit:GetText() );
			if (iNewAmount < 1) then
				iNewAmount = 1;
			end

			local iMaxAmount = pDealItem:GetMaxAmount();
			if (iNewAmount > iMaxAmount) then
				iNewAmount = iMaxAmount;
			end

			if (iNewAmount ~= pDealItem:GetAmount() or ms_bForceUpdateOnCommit) then
				pDealItem:SetAmount(iNewAmount);
				ms_bForceUpdateOnCommit = false;
				UpdateProposedWorkingDeal();
			end
			local newAmountStr = tostring(pDealItem:GetAmount());
			Controls.ValueAmountEdit:SetText(newAmountStr);
			if (ms_ValueEditDealItemControlTable ~= nil) then
				-- Keep the amount on the icon, that is currently hidden, up to date too.
				ms_ValueEditDealItemControlTable.AmountText:SetText(newAmountStr);
			end
			UpdateDealStatus();
		end
	end
end

-- ===========================================================================
-- Detach the value edit if it is attached to the control
function DetachValueEdit(itemID: number)

	if (itemID == ms_ValueEditDealItemID) then
		ClearValueEdit();
	end

end

-- ===========================================================================
-- Reattach the value edit overlay to the control set it is editing.
function ReAttachValueEdit()

	if (ms_ValueEditDealItemControlTable ~= nil) then

		local rootControl = ms_ValueEditDealItemControlTable.SelectButton;

		-- Position over the deal item.  We do this, rather than attaching to the item as a child, because we want to always be on top over everything.
		local x, y = rootControl:GetScreenOffset();
		local w, h = rootControl:GetSizeVal();

		SetHideValueText(ms_ValueEditDealItemControlTable, true);

		-- Display the number in the value edit field
		local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
		if (pDeal ~= nil) then

			local pDealItem = pDeal:FindItemByID(ms_ValueEditDealItemID);
			if (pDealItem ~= nil) then

				local itemType = pDealItem:GetType();
				if (itemType == DealItemTypes.GOLD or itemType == DealItemTypes.RESOURCES) then
					-- Gold and Resources just edit the amount
					Controls.ValueAmountEditOverlay:SetOffsetVal(x + (w/2), y + h);
					Controls.ValueAmountEditOverlay:SetHide(false);
					Controls.ValueAmountEditOverlayContainer:SetHide(false);

					Controls.ValueAmountEdit:SetText(tonumber(pDealItem:GetAmount()));
				else
					if (itemType == DealItemTypes.AGREEMENTS) then
						Controls.ValueTypeEditOverlay:SetOffsetVal(x + (w/2), y + h);
						Controls.ValueTypeEditOverlay:SetHide(false);

						PopulateValuePulldown(Controls.ValueTypeEditPulldown, pDealItem);
					end
				end

			end
		end			

		rootControl:ReprocessAnchoring();
	end

end

-- ===========================================================================
-- Attach the value edit overlay to a control set.
function AttachValueEdit(rootControl : table, dealItemID : number)

	ClearValueEdit();

	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
	if (pDeal ~= nil) then

		local pDealItem = pDeal:FindItemByID(dealItemID);
		if (pDealItem ~= nil) then
			-- Do we have something to edit?
			if (pDealItem:HasPossibleValues() or pDealItem:HasPossibleAmounts()) then
				-- Yes
				ms_ValueEditDealItemControlTable = FindIconInstanceFromControl(rootControl);
				ms_ValueEditDealItemID = dealItemID;

				ReAttachValueEdit();
			end
		end
	end

end

-- ===========================================================================
-- Update the deal panel for a player
function UpdateDealPanel(player)
	if (player:GetID() == ms_OtherPlayer:GetID()) then
		PopulatePlayerDealPanel(Controls.TheirOfferStack, ms_OtherPlayer);
	else
		PopulatePlayerDealPanel(Controls.MyOfferStack, ms_LocalPlayer);
	end
	UpdateDealStatus();
end

-- ===========================================================================
function OnClickAvailableOneTimeGold(player, iAddAmount : number)

	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
	if (pDeal ~= nil) then

		local pPlayerTreasury = player:GetTreasury();
		local bFound = false;
		
		-- Already there?
		local dealItems = pDeal:FindItemsByType(DealItemTypes.GOLD, DealItemSubTypes.NONE, player:GetID());
		local pDealItem;
		if (dealItems ~= nil) then
			for i, pDealItem in ipairs(dealItems) do
				if (pDealItem:GetDuration() == 0) then
					local iMaxGold = pDealItem:GetMaxAmount();
					-- Already have a one time gold.  Up the amount
					iAddAmount = pDealItem:GetAmount() + iAddAmount;
					if (iAddAmount > iMaxGold) then
						iAddAmount = iMaxGold;
					end
					if (iAddAmount ~= pDealItem:GetAmount()) then
						pDealItem:SetAmount(iAddAmount);
						bFound = true;
						break;
					else
						return;		-- No change, just exit
					end
				end
			end
		end

		-- Doesn't exist yet, add it.
		if (not bFound) then

			-- Going to add anything?
			pDealItem = pDeal:AddItemOfType(DealItemTypes.GOLD, player:GetID());
			if (pDealItem ~= nil) then

				-- Set the duration, so the max amount calculation knows what we are doing
				pDealItem:SetDuration(0);

				local iMaxGold = pDealItem:GetMaxAmount();

				-- Adjust the gold to our max
				if (iAddAmount > iMaxGold) then
					iAddAmount = iMaxGold;
				end

				if (iAddAmount > 0) then
					pDealItem:SetAmount(iAddAmount);
					bFound = true;
				else
					-- It is empty, remove it.
					local itemID = pDealItem:GetID();
					pDeal:RemoveItemByID(itemID);
				end
			end
		end


		if (bFound) then
			UpdateProposedWorkingDeal();
			UpdateDealPanel(player);
		end
	end
end

-- ===========================================================================
function OnClickAvailableMultiTurnGold(player, iAddAmount : number, iDuration : number)

	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
	if (pDeal ~= nil) then

		local pPlayerTreasury = player:GetTreasury();

		local bFound = false;
		UI.PlaySound("UI_GreatWorks_Put_Down");

		-- Already there?
		local dealItems = pDeal:FindItemsByType(DealItemTypes.GOLD, DealItemSubTypes.NONE, player:GetID());
		local pDealItem;
		if (dealItems ~= nil) then
			for i, pDealItem in ipairs(dealItems) do
				if (pDealItem:GetDuration() ~= 0) then
					local iMaxGold = pDealItem:GetMaxAmount();
					-- Already have a multi-turn gold.  Up the amount
					iAddAmount = pDealItem:GetAmount() + iAddAmount;
					if (iAddAmount > iMaxGold) then
						iAddAmount = iMaxGold;
					end
					if (iAddAmount ~= pDealItem:GetAmount()) then
						pDealItem:SetAmount(iAddAmount);
						bFound = true;
						break;
					else
						return;		-- No change, just exit
					end
				end
			end
		end

		-- Doesn't exist yet, add it.
		if (not bFound) then
			-- Going to add anything?
			pDealItem = pDeal:AddItemOfType(DealItemTypes.GOLD, player:GetID());
			if (pDealItem ~= nil) then

				-- Set the duration, so the max amount calculation knows what we are doing
				pDealItem:SetDuration(iDuration);

				local iMaxGold = pDealItem:GetMaxAmount();
				-- Adjust the gold to our max
				if (iAddAmount > iMaxGold) then
					iAddAmount = iMaxGold;
				end

				if (iAddAmount > 0) then
					pDealItem:SetAmount(iAddAmount);
					bFound = true;
				else
					-- It is empty, remove it.
					local itemID = pDealItem:GetID();
					pDeal:RemoveItemByID(itemID);
				end
			end
		end

		if (bFound) then
			UpdateProposedWorkingDeal();
			UpdateDealPanel(player);
		end
	end
end

-- ===========================================================================
-- Check to see if the deal should be auto-proposed.
function IsAutoPropose()
	if (not ms_OtherPlayerIsHuman) then
		local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
		if (pDeal ~= nil and not ms_bIsDemand and pDeal:IsValid() and not DealManager.HasPendingDeal(ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID())) then
			local iItemsFromLocal = pDeal:GetItemCount(ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
			local iItemsFromOther = pDeal:GetItemCount(ms_OtherPlayer:GetID(), ms_LocalPlayer:GetID());

			if (iItemsFromLocal > 0 and iItemsFromOther > 0) then
				return true;
			end
		end
	end
	return false;
end

-- ===========================================================================
-- Check the state of the deal and show/hide the special proposal buttons
function UpdateProposalButtons(bDealValid)

	local bDealIsPending = DealManager.HasPendingDeal(ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());

	if (bDealValid and (not bDealIsPending or not ms_OtherPlayerIsHuman)) then
		Controls.ResumeGame:SetHide(true);
		local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
		Controls.EqualizeDeal:SetHide(ms_bIsDemand);
		if (pDeal ~= nil) then

			local iItemsFromLocal = pDeal:GetItemCount(ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
			local iItemsFromOther = pDeal:GetItemCount(ms_OtherPlayer:GetID(), ms_LocalPlayer:GetID());

			if (not ms_bIsDemand) then
				if (not ms_OtherPlayerIsHuman) then
					-- Dealing with an AI
					if (iItemsFromLocal > 0 and iItemsFromOther == 0) then
						-- One way gift?
						Controls.MyDirections:SetHide(true);
						Controls.TheirDirections:SetHide(false);
						Controls.WhatWouldYouGiveMe:SetHide(false);
						Controls.WhatWouldItTakeButton:SetHide(true);
						Controls.EqualizeDeal:SetHide(true);
						Controls.AcceptDeal:SetHide(false);
						Controls.AcceptDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_GIFT_DEAL");
						-- Make sure the leader text is set to something appropriate.
						SetDefaultLeaderDialogText();
					else
						if (iItemsFromLocal == 0 and iItemsFromOther > 0) then
							Controls.MyDirections:SetHide(false);
							Controls.TheirDirections:SetHide(true);
							Controls.WhatWouldYouGiveMe:SetHide(true);
							Controls.WhatWouldItTakeButton:SetHide(false);
							Controls.AcceptDeal:SetHide(true);				--If either of the above buttons are showing, disable the main accept button
							-- Make sure the leader text is set to something appropriate.
							SetDefaultLeaderDialogText();
						else												--Something is being offered on both sides
							Controls.MyDirections:SetHide(true);
							Controls.TheirDirections:SetHide(true);
							Controls.WhatWouldYouGiveMe:SetHide(true);
							Controls.WhatWouldItTakeButton:SetHide(true);
							Controls.AcceptDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_ACCEPT_DEAL");
						end
					end
				else
					-- Dealing with another human

					Controls.EqualizeDeal:SetHide(true);
					Controls.AcceptDeal:SetHide(false);

					if (ms_LastIncomingDealProposalAction == DealProposalAction.PENDING) then
						-- Just starting the deal
						if (iItemsFromLocal > 0 and iItemsFromOther == 0) then
							-- Is this one way to them?
							Controls.MyDirections:SetHide(true);
							Controls.TheirDirections:SetHide(false);
							Controls.WhatWouldYouGiveMe:SetHide(false);
							Controls.WhatWouldItTakeButton:SetHide(true);
							Controls.AcceptDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_GIFT_DEAL");
						else
							-- Everything else is a proposal to another human
							Controls.MyDirections:SetHide(true);
							Controls.TheirDirections:SetHide(true);
							Controls.WhatWouldYouGiveMe:SetHide(true);
							Controls.WhatWouldItTakeButton:SetHide(true);
							Controls.AcceptDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_PROPOSE_DEAL");
						end
						-- Make sure the leader text is set to something appropriate.
						SetDefaultLeaderDialogText();
					else
						Controls.MyDirections:SetHide(true);
						Controls.TheirDirections:SetHide(true);
						Controls.WhatWouldYouGiveMe:SetHide(true);
						Controls.WhatWouldItTakeButton:SetHide(true);
						-- Are the incoming and outgoing deals the same?
						if (DealManager.AreWorkingDealsEqual(ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID())) then 
							Controls.AcceptDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_ACCEPT_DEAL");
						else
							Controls.AcceptDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_PROPOSE_DEAL");
						end
					end
				end
			else
				-- Is a Demand
				if (ms_InitiatedByPlayerID == ms_OtherPlayerID) then
					Controls.MyDirections:SetHide(true);
					Controls.TheirDirections:SetHide(true);
				else
					if (iItemsFromOther == 0) then
						Controls.TheirDirections:SetHide(false);
					else
						Controls.TheirDirections:SetHide(true);
					end
				end
				Controls.WhatWouldYouGiveMe:SetHide(true);
				Controls.WhatWouldItTakeButton:SetHide(true);
				-- Make sure the leader text is set to something appropriate.
				SetDefaultLeaderDialogText();
			end
		else
			-- Make sure the leader text is set to something appropriate.
			SetDefaultLeaderDialogText();
		end
	else															
		--There isn't a valid deal, or we are just viewing a pending deal.
		local bIsViewing = (bDealIsPending and ms_OtherPlayerIsHuman);

		local iItemsFromLocal = 0;
		local iItemsFromOther = 0;

		local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
		if (pDeal ~= nil) then
			iItemsFromLocal = pDeal:GetItemCount(ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
			iItemsFromOther = pDeal:GetItemCount(ms_OtherPlayer:GetID(), ms_LocalPlayer:GetID());
		end

		Controls.WhatWouldYouGiveMe:SetHide(true);
		Controls.WhatWouldItTakeButton:SetHide(true);
		Controls.MyDirections:SetHide( bIsViewing or iItemsFromLocal > 0);
		Controls.TheirDirections:SetHide( bIsViewing or iItemsFromOther > 0);
		Controls.EqualizeDeal:SetHide(true);
		Controls.AcceptDeal:SetHide(true);
		Controls.DemandDeal:SetHide(true);

		if (not DealIsEmpty() and not bDealValid) then
			-- Set have the other leader tell them that the deal has invalid items.
			Controls.LeaderDialog:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_INVALID");
		else
			SetDefaultLeaderDialogText();
		end
			
		Controls.ResumeGame:SetHide(not bIsViewing);
	end

	if (not Controls.AcceptDeal:IsHidden()) then
		Controls.EqualizeDeal:SetHide(true);
	end

	if (bDealIsPending and ms_OtherPlayerIsHuman) then
		if (ms_bIsDemand) then
			Controls.RefuseDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_CANCEL_DEMAND");
		else
			Controls.RefuseDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_CANCEL_DEAL");
		end
	else
		-- Did the other player start this or the local player?
		if (ms_InitiatedByPlayerID == ms_OtherPlayerID) then
			if (not bDealValid) then
				-- Our changes have made the deal invalid, say cancel instead
				Controls.RefuseDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_CANCEL_DEAL");
			else
				if (ms_bIsDemand) then
					Controls.AcceptDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_ACCEPT_DEMAND");
					Controls.RefuseDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_REFUSE_DEMAND");
				else
					Controls.RefuseDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_REFUSE_DEAL");
				end
			end
		else
			Controls.RefuseDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_EXIT_DEAL");
		end
	end
	Controls.DealOptionsStack:CalculateSize();
	Controls.DealOptionsStack:ReprocessAnchoring();

	if (ms_bIsDemand) then
		if (ms_InitiatedByPlayerID == ms_OtherPlayerID) then
			-- Demand from the other player and we are responding
			Controls.MyOfferBracket:SetHide(false);
			Controls.MyOfferLabel:SetHide(false);
			Controls.TheirOfferLabel:SetHide(true);
			Controls.TheirOfferBracket:SetHide(true);
		else
			-- Demand from us, to the other player
			Controls.MyOfferBracket:SetHide(true);
			Controls.MyOfferLabel:SetHide(true);
			Controls.TheirOfferLabel:SetHide(false);
			Controls.TheirOfferBracket:SetHide(false);
		end
	else
		Controls.MyOfferLabel:SetHide(false);
		Controls.MyOfferBracket:SetHide(false);
		Controls.TheirOfferLabel:SetHide(false);
		Controls.TheirOfferBracket:SetHide(false);
	end

	Controls.TheirOfferStack:CalculateSize();
	Controls.TheirOfferStack:ReprocessAnchoring();
	Controls.TheirOfferBracket:DoAutoSize();
	Controls.TheirOfferBracket:ReprocessAnchoring();
	Controls.TheirOfferScroll:CalculateSize();
	Controls.TheirOfferBracket:ReprocessAnchoring();	-- Because the bracket is centered inside the scroll box, we have to reprocess this again.

	Controls.MyOfferStack:CalculateSize();
	Controls.MyOfferStack:ReprocessAnchoring();
	Controls.MyOfferBracket:DoAutoSize();
	Controls.MyOfferBracket:ReprocessAnchoring();
	Controls.MyOfferScroll:CalculateSize();
	Controls.MyOfferBracket:ReprocessAnchoring();		-- Because the bracket is centered inside the scroll box, we have to reprocess this again.

end

-- ===========================================================================
function PopulateAvailableGold(player : table, iconList : table)

	local iAvailableItemCount = 0;

	local eFromPlayerID = player:GetID();
	local eToPlayerID = GetOtherPlayer(player):GetID();

	local possibleResources = DealManager.GetPossibleDealItems(eFromPlayerID, eToPlayerID, DealItemTypes.GOLD);
	if (possibleResources ~= nil) then
		for i, entry in ipairs(possibleResources) do
			if (entry.Duration == 0) then
				-- One time gold
				local playerTreasury:table	= player:GetTreasury();
				local goldBalance	:number = math.floor(playerTreasury:GetGoldBalance());

				if (not ms_bIsDemand) then
					-- One time gold
					local icon = ms_IconOnlyIM:GetInstance(iconList.ListStack);
					icon.AmountText:SetText(goldBalance);
					icon.SelectButton:SetToolTipString(nil);		-- We recycle the entries, so make sure this is clear.
					SetIconToSize(icon, "ICON_YIELD_GOLD_5");
					icon.SelectButton:RegisterCallback( Mouse.eLClick, function() OnClickAvailableOneTimeGold(player, ms_DefaultOneTimeGoldAmount); end );
					icon.SelectButton:RegisterCallback( Mouse.eLClick, function() OnClickAvailableOneTimeGold(player, ms_DefaultOneTimeGoldAmount); end );

					iAvailableItemCount = iAvailableItemCount + 1;
				end
			else
				-- Multi-turn gold
				icon = ms_IconAndTextIM:GetInstance(iconList.ListStack);
				SetIconToSize(icon, "ICON_YIELD_GOLD_5");
				icon.IconText:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_GOLD_PER_TURN");
				icon.SelectButton:SetToolTipString(nil);		-- We recycle the entries, so make sure this is clear.
				icon.SelectButton:RegisterCallback( Mouse.eLClick, function() OnClickAvailableMultiTurnGold(player, ms_DefaultMultiTurnGoldAmount, ms_DefaultMultiTurnGoldDuration); end );
				icon.ValueText:SetHide(true);

				iconList.ListStack:CalculateSize();
				iconList.List:ReprocessAnchoring();

				iAvailableItemCount = iAvailableItemCount + 1;
			end
		end
	end

	return iAvailableItemCount;
end

-- ===========================================================================
function OnClickAvailableBasic(itemType, player, valueType)

	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
	if (pDeal ~= nil) then

		-- Already there?
		local pDealItem = pDeal:FindItemByValueType(itemType, DealItemSubTypes.NONE, valueType, player:GetID());
		if (pDealItem == nil) then
			-- No
			pDealItem = pDeal:AddItemOfType(itemType, player:GetID());
			if (pDealItem ~= nil) then
				pDealItem:SetValueType(valueType);
				UpdateDealPanel(player);
				UpdateProposedWorkingDeal();
			end
		end
	end
end

-- ===========================================================================
function OnClickAvailableResource(player, resourceType)

	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
	if (pDeal ~= nil) then

		-- Already there?
		local pDealItem = pDeal:FindItemByValueType(DealItemTypes.RESOURCES, DealItemSubTypes.NONE, resourceType, player:GetID());
		if (pDealItem == nil) then
			-- No
			local pPlayerResources = player:GetResources();
			local iAmount = pPlayerResources:GetResourceAmount( resourceType );
			if (iAmount > 0) then
				pDealItem = pDeal:AddItemOfType(DealItemTypes.RESOURCES, player:GetID());
				if (pDealItem ~= nil) then
					-- Add one
					pDealItem:SetValueType(resourceType);
					pDealItem:SetAmount(1);
					pDealItem:SetDuration(30);	-- Default to this many turns		

					UpdateDealPanel(player);
					UpdateProposedWorkingDeal();
					UI.PlaySound("UI_GreatWorks_Put_Down");

				end
			end
		end
	end
end

-- ===========================================================================
function OnClickAvailableAgreement(player, agreementType, agreementTurns)

	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
	if (pDeal ~= nil) then

		-- Already there?
		local pDealItem = pDeal:FindItemByType(DealItemTypes.AGREEMENTS, agreementType, player:GetID());
		if (pDealItem == nil) then
			-- No
			pDealItem = pDeal:AddItemOfType(DealItemTypes.AGREEMENTS, player:GetID());
			if (pDealItem ~= nil) then
				pDealItem:SetSubType(agreementType);
				pDealItem:SetDuration(agreementTurns);

				UpdateDealPanel(player);
				UpdateProposedWorkingDeal();
				UI.PlaySound("UI_GreatWorks_Put_Down");
			end
		end
	end
end

-- ===========================================================================
function OnClickAvailableGreatWork(player, type)

	OnClickAvailableBasic(DealItemTypes.GREATWORK, player, type);
	UI.PlaySound("UI_GreatWorks_Put_Down");

end

-- ===========================================================================
function OnClickAvailableCaptive(player, type)

	OnClickAvailableBasic(DealItemTypes.CAPTIVE, player, type);
	UI.PlaySound("UI_GreatWorks_Put_Down");

end

-- ===========================================================================
function OnClickAvailableCity(player, valueType, subType)

	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
	if (pDeal ~= nil) then

		-- Already there?
		local pDealItem = pDeal:FindItemByValueType(DealItemTypes.CITIES, subType, valueType, player:GetID());
		if (pDealItem == nil) then
			-- No
			pDealItem = pDeal:AddItemOfType(DealItemTypes.CITIES, player:GetID());
			if (pDealItem ~= nil) then
				pDealItem:SetSubType(subType);
				pDealItem:SetValueType(valueType);
				if (not pDealItem:IsValid(pDeal)) then
					pDeal:RemoveItemByID(pDealItem:GetID());
				end
				UpdateDealPanel(player);
				UpdateProposedWorkingDeal();
			end
		end
	end

	UI.PlaySound("UI_GreatWorks_Put_Down");

end

-- ===========================================================================
function OnRemoveDealItem(player, itemID)

	if (ms_bIsDemand == true and ms_InitiatedByPlayerID == ms_OtherPlayerID) then
		-- Can't remove it
		return;
	end

	DetachValueEdit(itemID);

	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
	if (pDeal ~= nil) then

		local pDealItem = pDeal:FindItemByID(itemID);
		if (pDealItem ~= nil) then
			if (not pDealItem:IsLocked()) then
				if (pDeal:RemoveItemByID(itemID)) then
					UpdateDealPanel(player);
					UpdateProposedWorkingDeal();
					UI.PlaySound("UI_GreatWorks_Pick_Up");
				end
			end
		end
	end
end

-- ===========================================================================
function OnSelectValueDealItem(player, itemID, controlInstance)

	if (ms_bIsDemand == true and ms_InitiatedByPlayerID == ms_OtherPlayerID) then
		-- Can't edit it
		return;
	end

	if (controlInstance ~= nil) then
		AttachValueEdit(controlInstance, itemID);
	end
end

-- ===========================================================================
function PopulateAvailableResources(player : table, iconList : table, className : string)

	local iAvailableItemCount = 0;
	local possibleResources = DealManager.GetPossibleDealItems(player:GetID(), GetOtherPlayer(player):GetID(), DealItemTypes.RESOURCES);
	if (possibleResources ~= nil) then
		for i, entry in ipairs(possibleResources) do
	
			local resourceDesc = GameInfo.Resources[entry.ForType];
			if (resourceDesc ~= nil) then
				-- Do we have some and is it a luxury item?
				if (entry.MaxAmount > 0 and resourceDesc.ResourceClassType == className ) then
					local icon = ms_IconOnlyIM:GetInstance(iconList.ListStack);
					SetIconToSize(icon, "ICON_" .. resourceDesc.ResourceType);
					icon.AmountText:SetText(tostring(entry.MaxAmount));
					icon.AmountText:SetHide(false);

					icon.SelectButton:SetDisabled( not entry.IsValid );
					local resourceType = entry.ForType;
					-- What to do when double clicked/tapped.
					icon.SelectButton:RegisterCallback( Mouse.eLClick, function() OnClickAvailableResource(player, resourceType); end );
					-- Set a tool tip
					icon.SelectButton:LocalizeAndSetToolTip(resourceDesc.Name);
					icon.SelectButton:ReprocessAnchoring();

					iAvailableItemCount = iAvailableItemCount + 1;
				end
			end
		end

		iconList.ListStack:CalculateSize();
		iconList.List:ReprocessAnchoring();
	end

	-- Hide if empty
	iconList.GetTopControl():SetHide( iconList.ListStack:GetSizeX()==0 );

	return iAvailableItemCount;
end

-- ===========================================================================
function PopulateAvailableLuxuryResources(player : table, iconList : table)

	local iAvailableItemCount = 0;
	iAvailableItemCount = iAvailableItemCount + PopulateAvailableResources(player, iconList, "RESOURCECLASS_LUXURY");
	return iAvailableItemCount;
end

-- ===========================================================================
function PopulateAvailableStrategicResources(player : table, iconList : table)

	local iAvailableItemCount = 0;
	iAvailableItemCount = iAvailableItemCount + PopulateAvailableResources(player, iconList, "RESOURCECLASS_STRATEGIC");
	return iAvailableItemCount; 
end

-- ===========================================================================
function PopulateAvailableAgreements(player : table, iconList : table)

	local iAvailableItemCount = 0;
	local possibleAgreements = DealManager.GetPossibleDealItems(player:GetID(), GetOtherPlayer(player):GetID(), DealItemTypes.AGREEMENTS);
	if (possibleAgreements ~= nil) then
		for i, entry in ipairs(possibleAgreements) do
			local agreementType = entry.SubType;

			local agreementDuration = entry.Duration;
			local icon = ms_IconAndTextIM:GetInstance(iconList.ListStack);

			local info: table = GameInfo.DiplomaticActions[ agreementType ];
			if (info ~= nil) then
				SetIconToSize(icon, "ICON_".. info.DiplomaticActionType, 38);
			end
			icon.AmountText:SetHide(true);
			icon.IconText:LocalizeAndSetText(entry.SubTypeName);
			icon.SelectButton:SetDisabled( not entry.IsValid and entry.ValidationResult ~= DealValidationResult.MISSING_DEPENDENCY );	-- Hide if invalid, unless it is just missing a dependency, the user will update that when it is added to the deal.
			icon.ValueText:SetHide(true);

			-- What to do when double clicked/tapped.
			icon.SelectButton:RegisterCallback( Mouse.eLClick, function() OnClickAvailableAgreement(player, agreementType, agreementDuration); end );
			-- Set a tool tip if their is a duration
			if (entry.Duration > 0) then
				local szTooltip = Locale.Lookup("LOC_DIPLOMACY_DEAL_PARAMETER_WITH_TURNS", entry.SubTypeName, entry.Duration);
				icon.SelectButton:SetToolTipString(szTooltip);
			else
				icon.SelectButton:SetToolTipString(nil);
			end

			-- icon.SelectButton:LocalizeAndSetToolTip( );
			icon.SelectButton:ReprocessAnchoring();

			iAvailableItemCount = iAvailableItemCount + 1;
		end

		iconList.ListStack:CalculateSize();
		iconList.List:ReprocessAnchoring();
	end

	-- Hide if empty
	iconList.GetTopControl():SetHide( iconList.ListStack:GetSizeX()==0 );

	return iAvailableItemCount;
end

-- ===========================================================================
function MakeCityToolTip(player : table, cityID : number)
	local pCity = player:GetCities():FindID( cityID );
	if (pCity ~= nil) then	
		local szToolTip = Locale.Lookup("LOC_DEAL_CITY_POPULATION_TOOLTIP", pCity:GetPopulation());
		local districtNames = {};
		local pCityDistricts = pCity:GetDistricts();
		if (pCityDistricts ~= nil) then

			for i, pDistrict in pCityDistricts:Members() do
				local pDistrictDef = GameInfo.Districts[ pDistrict:GetType() ];
				if (pDistrictDef ~= nil) then
					local districtType:string = pDistrictDef.DistrictType;
					-- Skip the city center and any wonder districts
					if (districtType ~= "DISTRICT_CITY_CENTER" and districtType ~= "DISTRICT_WONDER") then
						table.insert(districtNames, pDistrictDef.Name);
					end
				end
			end
		end

		if (#districtNames > 0) then
			szToolTip = szToolTip .. "[NEWLINE]" .. Locale.Lookup("LOC_DEAL_CITY_DISTRICTS_TOOLTIP");
			for i, name in ipairs(districtNames) do
				szToolTip = szToolTip .. "[NEWLINE]" .. Locale.Lookup(name);
			end
		end
		return szToolTip;			
	end

	return "";
end

-- ===========================================================================
function PopulateAvailableCities(player : table, iconList : table)

	local iAvailableItemCount = 0;
	local possibleItems = DealManager.GetPossibleDealItems(player:GetID(), GetOtherPlayer(player):GetID(), DealItemTypes.CITIES);
	if (possibleItems ~= nil) then
		for i, entry in ipairs(possibleItems) do

			local type = entry.ForType;
			local subType = entry.SubType;
			local icon = ms_IconAndTextIM:GetInstance(iconList.ListStack);
			SetIconToSize(icon, "ICON_BUILDINGS", 45);
			icon.AmountText:SetHide(true);
			icon.IconText:LocalizeAndSetText(entry.ForTypeName);
			icon.SelectButton:SetDisabled( not entry.IsValid and entry.ValidationResult ~= DealValidationResult.MISSING_DEPENDENCY );	-- Hide if invalid, unless it is just missing a dependency, the user will update that when it is added to the deal.
			icon.ValueText:SetHide(true);

			-- What to do when double clicked/tapped.
			icon.SelectButton:RegisterCallback( Mouse.eLClick, function() OnClickAvailableCity(player, type, subType); end );

			icon.SelectButton:SetToolTipString( MakeCityToolTip(player, type) );
			icon.SelectButton:ReprocessAnchoring();

			iAvailableItemCount = iAvailableItemCount + 1;
		end

		iconList.ListStack:CalculateSize();
		iconList.List:ReprocessAnchoring();
	end

	-- Hide if empty
	iconList.GetTopControl():SetHide( iconList.ListStack:GetSizeX()==0 );

	return iAvailableItemCount;
end

-- ===========================================================================
function PopulateAvailableOtherPlayers(player : table, iconList : table)

	local iAvailableItemCount = 0;
	-- Hide if empty
	iconList.GetTopControl():SetHide( iconList.ListStack:GetSizeX()==0 );

	return iAvailableItemCount;
end

-- ===========================================================================
function PopulateAvailableGreatWorks(player : table, iconList : table)

	local iAvailableItemCount = 0;
	local possibleItems = DealManager.GetPossibleDealItems(player:GetID(), GetOtherPlayer(player):GetID(), DealItemTypes.GREATWORK);
	if (possibleItems ~= nil) then
		for i, entry in ipairs(possibleItems) do

			local greatWorkDesc = GameInfo.GreatWorks[entry.ForTypeDescriptionID];
			if (greatWorkDesc ~= nil) then
				local type = entry.ForType;
				local icon = ms_IconAndTextIM:GetInstance(iconList.ListStack);
				SetIconToSize(icon, "ICON_" .. greatWorkDesc.GreatWorkType);
				icon.AmountText:SetHide(true);
				icon.IconText:LocalizeAndSetText(entry.ForTypeName);
				icon.SelectButton:SetDisabled( not entry.IsValid and entry.ValidationResult ~= DealValidationResult.MISSING_DEPENDENCY );	-- Hide if invalid, unless it is just missing a dependency, the user will update that when it is added to the deal.
				icon.ValueText:SetHide(true);
    
				-- What to do when double clicked/tapped.
				icon.SelectButton:RegisterCallback( Mouse.eLClick, function() OnClickAvailableGreatWork(player, type); end );
				-- Set a tool tip
				--icon.SelectButton:LocalizeAndSetToolTip(greatWorkDesc.Name);
				
        --CQUI Changes
        local yieldType:string = GameInfo.GreatWork_YieldChanges[greatWorkDesc.GreatWorkType].YieldType;
        local yieldValue:number = GameInfo.GreatWork_YieldChanges[greatWorkDesc.GreatWorkType].YieldChange;
        local greatWorkYields:string = YIELD_FONT_ICONS[yieldType] .. yieldValue .. " [ICON_TourismLarge]" .. greatWorkDesc.Tourism;
        local tooltipText:string;
        local greatWorkTypeName:string;
        
        if (greatWorkDesc.EraType ~= nil) then
          greatWorkTypeName = Locale.Lookup("LOC_" .. greatWorkDesc.GreatWorkObjectType .. "_" .. greatWorkDesc.EraType);
        else
          greatWorkTypeName = Locale.Lookup("LOC_" .. greatWorkDesc.GreatWorkObjectType);
        end
        tooltipText = Locale.Lookup(greatWorkDesc.Name) .. " (" .. greatWorkTypeName .. ")[NEWLINE]" .. greatWorkYields;
        icon.SelectButton:SetToolTipString(tooltipText);
        --end CQUI Changes
        
        icon.SelectButton:ReprocessAnchoring();

				iAvailableItemCount = iAvailableItemCount + 1;
			end
		end

		iconList.ListStack:CalculateSize();
		iconList.List:ReprocessAnchoring();
	end

	-- Hide if empty
	iconList.GetTopControl():SetHide( iconList.ListStack:GetSizeX()==0 );

	return iAvailableItemCount;

end

-- ===========================================================================
function PopulateAvailableCaptives(player : table, iconList : table)

	local iAvailableItemCount = 0;

	local possibleItems = DealManager.GetPossibleDealItems(player:GetID(), GetOtherPlayer(player):GetID(), DealItemTypes.CAPTIVE);
	if (possibleItems ~= nil) then
		for i, entry in ipairs(possibleItems) do

			local type = entry.ForType;
			local icon = ms_IconAndTextIM:GetInstance(iconList.ListStack);
			SetIconToSize(icon, "ICON_UNIT_SPY");
			icon.AmountText:SetHide(true);
			icon.IconText:LocalizeAndSetText(entry.ForTypeName);
			icon.SelectButton:SetDisabled( not entry.IsValid and entry.ValidationResult ~= DealValidationResult.MISSING_DEPENDENCY );	-- Hide if invalid, unless it is just missing a dependency, the user will update that when it is added to the deal.
			icon.ValueText:SetHide(true);

			-- What to do when double clicked/tapped.
			icon.SelectButton:RegisterCallback( Mouse.eLClick, function() OnClickAvailableCaptive(player, type); end );
			icon.SelectButton:SetToolTipString(nil);		-- We recycle the entries, so make sure this is clear.
			icon.SelectButton:ReprocessAnchoring();

			iAvailableItemCount = iAvailableItemCount + 1;
		end

		iconList.ListStack:CalculateSize();
		iconList.List:ReprocessAnchoring();
	end

	-- Hide if empty
	iconList.GetTopControl():SetHide( iconList.ListStack:GetSizeX()==0 );

	return iAvailableItemCount;
end

-- ===========================================================================
function PopulatePlayerAvailablePanel(rootControl : table, player : table)

	local iAvailableItemCount = 0;

	if (player ~= nil) then
	
		local playerType = GetPlayerType(player);
		if (ms_bIsDemand and player:GetID() == ms_InitiatedByPlayerID) then
			-- This is a demand, so hide all the demanding player's items
			for i = 1, AvailableDealItemGroupTypes.COUNT, 1 do
				ms_AvailableGroups[i][playerType].GetTopControl():SetHide(true);
			end
		else
			ms_AvailableGroups[AvailableDealItemGroupTypes.GOLD][playerType].GetTopControl():SetHide(false);

			iAvailableItemCount = iAvailableItemCount + PopulateAvailableGold(player, ms_AvailableGroups[AvailableDealItemGroupTypes.GOLD][playerType]);
			iAvailableItemCount = iAvailableItemCount + PopulateAvailableLuxuryResources(player, ms_AvailableGroups[AvailableDealItemGroupTypes.LUXURY_RESOURCES][playerType]);
			iAvailableItemCount = iAvailableItemCount + PopulateAvailableStrategicResources(player, ms_AvailableGroups[AvailableDealItemGroupTypes.STRATEGIC_RESOURCES][playerType]);

			if (not ms_bIsDemand) then
				iAvailableItemCount = iAvailableItemCount + PopulateAvailableAgreements(player, ms_AvailableGroups[AvailableDealItemGroupTypes.AGREEMENTS][playerType]);
			else
				ms_AvailableGroups[AvailableDealItemGroupTypes.AGREEMENTS][playerType].GetTopControl():SetHide(true);
			end

			iAvailableItemCount = iAvailableItemCount + PopulateAvailableCities(player, ms_AvailableGroups[AvailableDealItemGroupTypes.CITIES][playerType]);

			if (not ms_bIsDemand) then
				iAvailableItemCount = iAvailableItemCount + PopulateAvailableOtherPlayers(player, ms_AvailableGroups[AvailableDealItemGroupTypes.OTHER_PLAYERS][playerType]);
			else
				ms_AvailableGroups[AvailableDealItemGroupTypes.OTHER_PLAYERS][playerType].GetTopControl():SetHide(false);
			end

			iAvailableItemCount = iAvailableItemCount + PopulateAvailableGreatWorks(player, ms_AvailableGroups[AvailableDealItemGroupTypes.GREAT_WORKS][playerType]);
			iAvailableItemCount = iAvailableItemCount + PopulateAvailableCaptives(player, ms_AvailableGroups[AvailableDealItemGroupTypes.CAPTIVES][playerType]);

		end

		rootControl:CalculateSize();
		rootControl:ReprocessAnchoring();

	end

	return iAvailableItemCount; 
end

-- ===========================================================================
function PopulateDealBasic(player : table, iconList : table, populateType : number, iconName : string)

	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
	local playerType = GetPlayerType(player);
	if (pDeal ~= nil) then
		
		local pDealItem;
		for pDealItem in pDeal:Items() do
			local type = pDealItem:GetType();
			if (pDealItem:GetFromPlayerID() == player:GetID()) then
				local iDuration = pDealItem:GetDuration();
				local dealItemID = pDealItem:GetID();
				
				if (type == populateType) then
					local icon = ms_IconAndTextIM:GetInstance(iconList);
					SetIconToSize(icon, iconName);
					icon.AmountText:SetHide(true);
					local typeName = pDealItem:GetValueTypeNameID();
					if (typeName ~= nil) then
						icon.IconText:LocalizeAndSetText(typeName);
					end
				
					icon.SelectButton:RegisterCallback(Mouse.eRClick, function(void1, void2, self) OnRemoveDealItem(player, dealItemID, self); end);
					icon.SelectButton:RegisterCallback( Mouse.eLClick, function(void1, void2, self) OnSelectValueDealItem(player, dealItemID, self); end );

					icon.SelectButton:SetToolTipString(nil);		-- We recycle the entries, so make sure this is clear.
				end
			end
		end

		iconList:CalculateSize();
		iconList:ReprocessAnchoring();

	end

end

-- ===========================================================================
function PopulateDealResources(player : table, iconList : table)
	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
	local playerType = GetPlayerType(player);
	if (pDeal ~= nil) then
		ms_IconOnlyIM:ReleaseInstanceByParent(iconList);
		ms_IconAndTextIM:ReleaseInstanceByParent(iconList);

		local pDealItem;
		for pDealItem in pDeal:Items() do
			local type = pDealItem:GetType();
			if (pDealItem:GetFromPlayerID() == player:GetID()) then
				local iDuration = pDealItem:GetDuration();
				local dealItemID = pDealItem:GetID();
				-- Gold?
				if (type == DealItemTypes.GOLD) then
					local icon;
					if (iDuration == 0) then
						-- One time
						icon = ms_IconOnlyIM:GetInstance(iconList);
					else
						-- Multi-turn
						icon = ms_IconAndTextIM:GetInstance(iconList);
						icon.IconText:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_FOR_TURNS", iDuration);
						icon.ValueText:SetHide(true);
					end
					SetIconToSize(icon, "ICON_YIELD_GOLD_5");
					icon.AmountText:SetText(tostring(pDealItem:GetAmount()));
					icon.AmountText:SetHide(false);
					icon.SelectButton:RegisterCallback(Mouse.eRClick, function(void1, void2, self) OnRemoveDealItem(player, dealItemID, self); end);
					icon.SelectButton:RegisterCallback( Mouse.eLClick, function(void1, void2, self) OnSelectValueDealItem(player, dealItemID, self); end );
					icon.SelectButton:SetToolTipString(nil);		-- We recycle the entries, so make sure this is clear.
					if (dealItemID == ms_ValueEditDealItemID) then
						ms_ValueEditDealItemControlTable = icon;
					end
				else
					if (type == DealItemTypes.RESOURCES) then

						local resourceType = pDealItem:GetValueType();
						local icon;
						if (iDuration == 0) then
							-- One time
							icon = ms_IconOnlyIM:GetInstance(iconList);
						else
							-- Multi-turn
							icon = ms_IconAndTextIM:GetInstance(iconList);
							icon.IconText:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_FOR_TURNS", iDuration);
							icon.ValueText:SetHide(true);
						end
						local resourceDesc = GameInfo.Resources[resourceType];
						SetIconToSize(icon, "ICON_" .. resourceDesc.ResourceType);
						icon.AmountText:SetText(tostring(pDealItem:GetAmount()));
						icon.AmountText:SetHide(false);
						icon.SelectButton:RegisterCallback(Mouse.eRClick, function(void1, void2, self) OnRemoveDealItem(player, dealItemID, self); end);
						icon.SelectButton:RegisterCallback( Mouse.eLClick, function(void1, void2, self) OnSelectValueDealItem(player, dealItemID, self); end );
						-- Set a tool tip
						icon.SelectButton:LocalizeAndSetToolTip(resourceDesc.Name);

						-- KWG: Make a way for the icon manager to have categories, so the API is like this
						-- icon.Icon:SetTexture(IconManager:FindIconAtlasForType(IconTypes.RESOURCE, resourceType));

						if (dealItemID == ms_ValueEditDealItemID) then
							ms_ValueEditDealItemControlTable = icon;
						end
					end --end else if the item isn't gold
				end -- end for each item in dael
			end -- end if deal
		end

		iconList:CalculateSize();
		iconList:ReprocessAnchoring();

		ReAttachValueEdit();
	end

end

-- ===========================================================================
function PopulateDealAgreements(player : table, iconList : table)

	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
	local playerType = GetPlayerType(player);
	if (pDeal ~= nil) then
		
		local pDealItem;
		for pDealItem in pDeal:Items() do
			local type = pDealItem:GetType();
			if (pDealItem:GetFromPlayerID() == player:GetID()) then
				local dealItemID = pDealItem:GetID();
				-- Agreement?
				if (type == DealItemTypes.AGREEMENTS) then
					local icon = ms_IconAndTextIM:GetInstance(iconList);
					local info: table = GameInfo.DiplomaticActions[ pDealItem:GetSubType() ];
					if (info ~= nil) then
						SetIconToSize(icon, "ICON_".. info.DiplomaticActionType, 38);
					end

					icon.AmountText:SetHide(true);
					local subTypeDisplayName = pDealItem:GetSubTypeNameID();
					if (subTypeDisplayName ~= nil) then
						icon.IconText:LocalizeAndSetText(subTypeDisplayName);
					end
					icon.SelectButton:SetToolTipString(nil);		-- We recycle the entries, so make sure this is clear.

					-- Populate the value pulldown
					SetValueText(icon, pDealItem);
				
					icon.SelectButton:RegisterCallback(Mouse.eRClick, function(void1, void2, self) OnRemoveDealItem(player, dealItemID, self); end);
					icon.SelectButton:RegisterCallback( Mouse.eLClick, function(void1, void2, self) OnSelectValueDealItem(player, dealItemID, self); end );
				end
			end
		end

		iconList:CalculateSize();
		iconList:ReprocessAnchoring();

	end

end

-- ===========================================================================
function PopulateDealGreatWorks(player : table, iconList : table)

	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
	local playerType = GetPlayerType(player);
	if (pDeal ~= nil) then
		
		local pDealItem;
		for pDealItem in pDeal:Items() do
			local type = pDealItem:GetType();
			if (pDealItem:GetFromPlayerID() == player:GetID()) then
				local iDuration = pDealItem:GetDuration();
				local dealItemID = pDealItem:GetID();
				
				if (type == DealItemTypes.GREATWORK) then
					local icon = ms_IconAndTextIM:GetInstance(iconList);

					local typeID = pDealItem:GetValueTypeID();
					SetIconToSize(icon, "ICON_" .. typeID);
					icon.AmountText:SetHide(true);
					local typeName = pDealItem:GetValueTypeNameID();
					if (typeName ~= nil) then
						icon.IconText:LocalizeAndSetText(typeName);
						icon.SelectButton:LocalizeAndSetToolTip(typeName);
					else
						icon.IconText:SetText(nil);
						icon.SelectButton:SetToolTipString(nil);
					end
									
					icon.SelectButton:RegisterCallback(Mouse.eRClick, function(void1, void2, self) OnRemoveDealItem(player, dealItemID, self); end);
					icon.SelectButton:RegisterCallback( Mouse.eLClick, function(void1, void2, self) OnSelectValueDealItem(player, dealItemID, self); end );
				end
			end
		end

		iconList:CalculateSize();
		iconList:ReprocessAnchoring();

	end

end

-- ===========================================================================
function PopulateDealCaptives(player : table, iconList : table)

	PopulateDealBasic(player, iconList, DealItemTypes.CAPTIVE, "ICON_UNIT_SPY");

end

-- ===========================================================================
function PopulateDealCities(player : table, iconList : table)

	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
	local playerType = GetPlayerType(player);
	if (pDeal ~= nil) then
		
		local pDealItem;
		for pDealItem in pDeal:Items() do
			local type = pDealItem:GetType();
			if (pDealItem:GetFromPlayerID() == player:GetID()) then
				local dealItemID = pDealItem:GetID();
				
				if (type == DealItemTypes.CITIES) then
					local icon = ms_IconAndTextIM:GetInstance(iconList);
					SetIconToSize(icon, "ICON_BUILDINGS");
					icon.AmountText:SetHide(true);
					local typeName = pDealItem:GetValueTypeNameID();
					if (typeName ~= nil) then
						icon.IconText:LocalizeAndSetText(typeName);
					end
				
					icon.SelectButton:RegisterCallback(Mouse.eRClick, function(void1, void2, self) OnRemoveDealItem(player, dealItemID, self); end);
					icon.SelectButton:RegisterCallback( Mouse.eLClick, function(void1, void2, self) OnSelectValueDealItem(player, dealItemID, self); end );

					icon.SelectButton:SetToolTipString( MakeCityToolTip(player, pDealItem:GetValueType() ) );
				end
			end
		end

		iconList:CalculateSize();
		iconList:ReprocessAnchoring();

	end


end

-- ===========================================================================
function PopulatePlayerDealPanel(rootControl : table, player : table)

	if (player ~= nil) then
		
		local playerType = GetPlayerType(player);
		PopulateDealResources(player, ms_DealGroups[DealItemGroupTypes.RESOURCES][playerType]);
		PopulateDealAgreements(player, ms_DealGroups[DealItemGroupTypes.AGREEMENTS][playerType]);
		PopulateDealCaptives(player, ms_DealGroups[DealItemGroupTypes.CAPTIVES][playerType]);
		PopulateDealGreatWorks(player, ms_DealGroups[DealItemGroupTypes.GREAT_WORKS][playerType]);
		PopulateDealCities(player, ms_DealGroups[DealItemGroupTypes.CITIES][playerType]);

		rootControl:CalculateSize();
		rootControl:ReprocessAnchoring();
	end
end

-- ===========================================================================
function HandleESC()
	-- Were we just viewing the deal?
	if (not Controls.ResumeGame:IsHidden()) then
		OnResumeGame();
	else
		OnRefuseDeal();
	end
end

-- ===========================================================================
--	INPUT Handlings
--	If this context is visible, it will get a crack at the input.
-- ===========================================================================
function KeyHandler( key:number )
	if (key == Keys.VK_ESCAPE) then 
		HandleESC();			
		return true; 
	end

	return false;
end

-- ===========================================================================
function InputHandler( pInputStruct:table )
	local uiMsg = pInputStruct:GetMessageType();
	if uiMsg == KeyEvents.KeyUp then 
		return KeyHandler( pInputStruct:GetKey() ); 
	end
	if (uiMsg == MouseEvents.LButtonUp or
		uiMsg == MouseEvents.RButtonUp or
		uiMsg == MouseEvents.MButtonUp or
		uiMsg == MouseEvents.PointerUp) then 
		ClearValueEdit();
	end

	return false;
end

-- ===========================================================================
--	Handle a request to be shown, this should only be called by
--  the diplomacy statement handler.
-- ===========================================================================

function OnShowMakeDeal(otherPlayerID)
	ms_OtherPlayerID = otherPlayerID;
	ms_bIsDemand = false;
	ContextPtr:SetHide( false );
end
LuaEvents.DiploPopup_ShowMakeDeal.Add(OnShowMakeDeal);

-- ===========================================================================
--	Handle a request to be shown, this should only be called by
--  the diplomacy statement handler.
-- ===========================================================================

function OnShowMakeDemand(otherPlayerID)
	ms_OtherPlayerID = otherPlayerID;
	ms_bIsDemand = true;
	ContextPtr:SetHide( false );
end
LuaEvents.DiploPopup_ShowMakeDemand.Add(OnShowMakeDemand);

-- ===========================================================================
--	Handle a request to be hidden, this should only be called by
--  the diplomacy statement handler.
-- ===========================================================================

function OnHideDeal(otherPlayerID)
	OnContinue();
end
LuaEvents.DiploPopup_HideDeal.Add(OnHideDeal);

-- ===========================================================================
-- The other player has updated the deal
function OnDiplomacyIncomingDeal(eFromPlayer, eToPlayer, eAction)

	if (eFromPlayer == ms_OtherPlayerID) then
		local pDeal = DealManager.GetWorkingDeal(DealDirection.INCOMING, ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
		if (pDeal ~= nil) then
			-- Copy the deal to our OUTGOING deal back to the other player, in case we want to make modifications
			DealManager.CopyIncomingToOutgoingWorkingDeal(ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
			ms_LastIncomingDealProposalAction = eAction;

			PopulatePlayerDealPanel(Controls.TheirOfferStack, ms_OtherPlayer);
			PopulatePlayerDealPanel(Controls.MyOfferStack, ms_LocalPlayer);
			UpdateDealStatus();

		end
	end

end
Events.DiplomacyIncomingDeal.Add(OnDiplomacyIncomingDeal);

-- ===========================================================================
--	Handle a deal changing, usually from an incoming statement.
-- ===========================================================================

function OnDealUpdated(otherPlayerID, eAction, szText)
	if (not ContextPtr:IsHidden()) then
		OnDiplomacyIncomingDeal( otherPlayerID, Game.GetLocalPlayer(), eAction); 
		-- Display some updated text.
		if (szText ~= nil) then
			Controls.LeaderDialog:LocalizeAndSetText(szText);
		end			
	end
end
LuaEvents.DiploPopup_DealUpdated.Add(OnDealUpdated);

-- ===========================================================================
function StartExitAnimation()
	-- Start the exit animation, it will call OnContinue when complete
	ms_bExiting = true;
	Controls.Signature_Slide:Reverse();
	Controls.Signature_Alpha:Reverse();
	Controls.YieldSlide:Reverse();
	Controls.YieldAlpha:Reverse();
	Controls.TradePanelFade:Reverse();
	Controls.TradePanelSlide:Reverse();
	Controls.TradePanelFade:SetSpeed(5);
	Controls.TradePanelSlide:SetSpeed(5);
	UI.PlaySound("UI_Diplomacy_Menu_Change");
end

-- ===========================================================================
function OnContinue()
	ContextPtr:SetHide( true );
end

-- ===========================================================================
--	Functions for setting the data in the yield area
-- ===========================================================================

function FormatValuePerTurn( value:number )
	return Locale.ToNumber(value, "+#,###.#;-#,###.#");
end

function RefreshYields()

	local ePlayer		:number = Game.GetLocalPlayer();
	local localPlayer	:table= nil;
	if ePlayer ~= -1 then
		localPlayer = Players[ePlayer];
		if localPlayer == nil then
			return;
		end
	else
		return;
	end

	---- SCIENCE ----
	local playerTechnology		:table	= localPlayer:GetTechs();
	local currentScienceYield	:number = playerTechnology:GetScienceYield();
	Controls.SciencePerTurn:SetText( FormatValuePerTurn(currentScienceYield) );	
	Controls.ScienceBacking:SetToolTipString( GetScienceTooltip() );
	Controls.ScienceStack:CalculateSize();
	
	---- CULTURE----
	local playerCulture			:table	= localPlayer:GetCulture();
	local currentCultureYield	:number = playerCulture:GetCultureYield();
	Controls.CulturePerTurn:SetText( FormatValuePerTurn(currentCultureYield) );	
	Controls.CultureBacking:SetToolTipString( GetCultureTooltip() );
	Controls.CultureStack:CalculateSize();

	---- GOLD ----
	local playerTreasury:table	= localPlayer:GetTreasury();
	local goldYield		:number = playerTreasury:GetGoldYield() - playerTreasury:GetTotalMaintenance();
	local goldBalance	:number = math.floor(playerTreasury:GetGoldBalance());
	Controls.GoldBalance:SetText( Locale.ToNumber(goldBalance, "#,###.#"));	
	Controls.GoldPerTurn:SetText( FormatValuePerTurn(goldYield) );	
	Controls.GoldBacking:SetToolTipString(GetGoldTooltip());
	Controls.GoldStack:CalculateSize();	
	
	---- FAITH ----
	local playerReligion		:table	= localPlayer:GetReligion();
	local faithYield			:number = playerReligion:GetFaithYield();
	local faithBalance			:number = playerReligion:GetFaithBalance();
	Controls.FaithBalance:SetText( Locale.ToNumber(faithBalance, "#,###.#"));	
	Controls.FaithPerTurn:SetText( FormatValuePerTurn(faithYield) );
	Controls.FaithBacking:SetToolTipString( GetFaithTooltip() );
	Controls.FaithStack:CalculateSize();	
	if (faithYield == 0) then
		Controls.FaithBacking:SetHide(true);
	else
		Controls.FaithBacking:SetHide(false);
	end
	
	Controls.YieldStack:CalculateSize();
	Controls.YieldStack:ReprocessAnchoring();
end
-- ===========================================================================

-- ===========================================================================
function OnShow()
	RefreshYields();
	Controls.Signature_Slide:SetToBeginning();
	Controls.Signature_Alpha:SetToBeginning();
	Controls.Signature_Slide:Play();
	Controls.Signature_Alpha:Play();
	Controls.YieldAlpha:SetToBeginning();
	Controls.YieldAlpha:Play();
	Controls.YieldSlide:SetToBeginning();
	Controls.YieldSlide:Play();
	Controls.TradePanelFade:SetToBeginning();
	Controls.TradePanelFade:Play();
	Controls.TradePanelSlide:SetToBeginning();
	Controls.TradePanelSlide:Play();
	Controls.LeaderDialogFade:SetToBeginning();
	Controls.LeaderDialogFade:Play();
	Controls.LeaderDialogSlide:SetToBeginning();
	Controls.LeaderDialogSlide:Play();

	ms_IconOnlyIM:ResetInstances();
	ms_IconAndTextIM:ResetInstances();

	ms_bExiting = false;

	if (Game.GetLocalPlayer() == -1) then
		return;
	end

	-- For hotload testing, force the other player to be valid
	if (ms_OtherPlayerID == -1) then
		local playerID = 0
		for playerID = 0, GameDefines.MAX_PLAYERS-1, 1 do
			if (playerID ~= Game.GetLocalPlayer() and Players[playerID]:IsAlive()) then
				ms_OtherPlayerID = playerID;
				break;
			end
		end
	end

	-- Set up some globals for easy access
	ms_LocalPlayer = Players[Game.GetLocalPlayer()];
	ms_OtherPlayer = Players[ms_OtherPlayerID];
	ms_OtherPlayerIsHuman = ms_OtherPlayer:IsHuman();

	local sessionID = DiplomacyManager.FindOpenSessionID(Game.GetLocalPlayer(), ms_OtherPlayer:GetID());
	if (sessionID ~= nil) then
		local sessionInfo = DiplomacyManager.GetSessionInfo(sessionID);
		ms_InitiatedByPlayerID = sessionInfo.FromPlayer;
	end

	-- Did the AI start this or the human?
	if (ms_InitiatedByPlayerID == ms_OtherPlayerID) then
		ms_LastIncomingDealProposalAction = DealProposalAction.PROPOSED;
		DealManager.CopyIncomingToOutgoingWorkingDeal(ms_LocalPlayer:GetID(), ms_OtherPlayer:GetID());
	else
		ms_LastIncomingDealProposalAction = DealProposalAction.PENDING;
		-- We are NOT clearing the current outgoing deal. This allows other screens to pre-populate the deal.
	end

	UpdateOtherPlayerText(1);
	PopulateSignatureArea(ms_OtherPlayer);
	SetDefaultLeaderDialogText();

	local iAvailableItemCount = 0;
	-- Available content to trade.  Shouldn't change during the session, but it might, especially in multiplayer.
	iAvailableItemCount = iAvailableItemCount + PopulatePlayerAvailablePanel(Controls.MyInventoryStack, ms_LocalPlayer);
	iAvailableItemCount = iAvailableItemCount + PopulatePlayerAvailablePanel(Controls.TheirInventoryStack, ms_OtherPlayer);

	Controls.MyInventoryScroll:CalculateSize();
	Controls.TheirInventoryScroll:CalculateSize();

	if (iAvailableItemCount == 0) then
		-- Nothing to trade/demand
		if not m_kPopupDialog:IsOpen() then
			if (ms_bIsDemand) then
				m_kPopupDialog:AddText(Locale.Lookup("LOC_DIPLO_DEMAND_NO_AVAILABLE_ITEMS"));
				m_kPopupDialog:AddTitle( Locale.ToUpper(Locale.Lookup("LOC_DIPLO_CHOICE_MAKE_DEMAND")), Controls.PopupTitle)
				m_kPopupDialog:AddButton( Locale.Lookup("LOC_OK_BUTTON"), OnRefuseDeal);  
			else
				m_kPopupDialog:AddText(	  Locale.Lookup("LOC_DIPLO_DEAL_NO_AVAILABLE_ITEMS"));
				m_kPopupDialog:AddTitle( Locale.ToUpper(Locale.Lookup("LOC_DIPLO_CHOICE_MAKE_DEAL")), Controls.PopupTitle)
				m_kPopupDialog:AddButton( Locale.Lookup("LOC_OK_BUTTON"), OnRefuseDeal);  
			end
			m_kPopupDialog:Open("DiplomacyActionView");
		end
	else
		if m_kPopupDialog:IsOpen() then
			m_kPopupDialog:Close();
		end		
	end

	PopulatePlayerDealPanel(Controls.TheirOfferStack, ms_OtherPlayer);
	PopulatePlayerDealPanel(Controls.MyOfferStack, ms_LocalPlayer);
	UpdateDealStatus();

	Controls.MyOfferScroll:CalculateSize();
	Controls.TheirOfferScroll:CalculateSize();

	LuaEvents.DiploBasePopup_HideUI(true);
	TTManager:ClearCurrent();	-- Clear any tool tips raised;

	Controls.DealOptionsStack:CalculateSize();
	Controls.DealOptionsStack:ReprocessAnchoring();
end

----------------------------------------------------------------    
function OnHide()
	LuaEvents.DiploBasePopup_HideUI(false);
end

-- ===========================================================================
--	Context CTOR
-- ===========================================================================
function OnInit( isHotload )
	CreatePanels();

	if (isHotload and not ContextPtr:IsHidden()) then
		OnShow();
	end
end

-- ===========================================================================
--	Context DESTRUCTOR
--	Not called when screen is dismissed, only if the whole context is removed!
-- ===========================================================================
function OnShutdown()

end

-- ===========================================================================
function OnLocalPlayerTurnEnd()
	if (not ContextPtr:IsHidden()) then
		-- Were we just viewing the deal?
		if (not Controls.ResumeGame:IsHidden()) then
			OnResumeGame();
		else
			OnRefuseDeal(true);
		end
	end
end

-- ===========================================================================
function Initialize()

	ContextPtr:SetInitHandler( OnInit );
	ContextPtr:SetInputHandler( InputHandler, true );
	ContextPtr:SetShutdown( OnShutdown );
	ContextPtr:SetShowHandler( OnShow );
	ContextPtr:SetHideHandler( OnHide );

	Events.LocalPlayerTurnEnd.Add( OnLocalPlayerTurnEnd );

	m_kPopupDialog = PopupDialogLogic:new( "DealConfirmDialog", Controls.PopupDialog, Controls.PopupStack );
	m_kPopupDialog:SetOpenAnimationControls( Controls.PopupAlphaIn, Controls.PopupSlideIn );	
	m_kPopupDialog:SetInstanceNames( nil, nil, "PopupTextInstance", "Text", "RowInstance", "Row");
	m_kPopupDialog:SetSize(400,200);
end

Initialize();
