
GLUE_SCREENS = {
	["login"] = 		{ frame = "AccountLogin", 		playMusic = true,	playAmbience = true },
	["realmlist"] = 	{ frame = "RealmListUI", 		playMusic = true,	playAmbience = false },
	["charselect"] = 	{ frame = "CharacterSelect",	playMusic = true,	playAmbience = false },
	["charcreate"] =	{ frame = "CharacterCreate",	playMusic = true,	playAmbience = false },
};

GLUE_SECONDARY_SCREENS = {
	["cinematics"] =	{ frame = "CinematicsFrame", 	playMusic = true,	playAmbience = false,	fullScreen = false,	showSound = "gsTitleOptions" },
	["credits"] = 		{ frame = "CreditsFrame", 		playMusic = false,	playAmbience = false,	fullScreen = true,	showSound = "gsTitleCredits" },
	["movie"] = 		{ frame = "MovieFrame", 		playMusic = false,	playAmbience = false,	fullScreen = true,	showSound = "gsTitleOptionOK" },
	["options"] = 		{ frame = "VideoOptionsFrame",	playMusic = true,	playAmbience = false,	fullScreen = false,	showSound = "gsTitleOptions" },
};

-- Realm Split info
SERVER_SPLIT_SHOW_DIALOG = false;
SERVER_SPLIT_CLIENT_STATE = -1;	--	-1 uninitialized; 0 - no choice; 1 - realm 1; 2 - realm 2
SERVER_SPLIT_STATE_PENDING = -1;	--	-1 uninitialized; 0 - no server split; 1 - server split (choice mode); 2 - server split (no choice mode)
SERVER_SPLIT_DATE = nil;

SEX_NONE = 1;
SEX_MALE = 2;
SEX_FEMALE = 3;

function GlueParent_OnLoad(self)
	local width = GetScreenWidth();
	local height = GetScreenHeight();

	if ( width / height > 16 / 9) then
		local maxWidth = height * 16 / 9;
		local barWidth = ( width - maxWidth ) / 2;
		self:ClearAllPoints();
		self:SetPoint("TOPLEFT", barWidth, 0); 
		self:SetPoint("BOTTOMRIGHT", -barWidth, 0);
	end

	self:RegisterEvent("FRAMES_LOADED");
	self:RegisterEvent("ACCOUNT_MESSAGES_BODY_LOADED");
	self:RegisterEvent("LOGIN_STATE_CHANGED");
	self:RegisterEvent("LOGIN_FAILED");
	self:RegisterEvent("OPEN_STATUS_DIALOG");
end

function GlueParent_OnEvent(self, event, ...)
	if ( event == "FRAMES_LOADED" ) then
		LocalizeFrames();
		GlueParent_EnsureValidScreen();
		GlueParent_UpdateDialogs();
		GlueParent_CheckCinematic();
	elseif ( event == "LOGIN_STATE_CHANGED" ) then
		GlueParent_EnsureValidScreen();
		GlueParent_UpdateDialogs();
	elseif ( event == "OPEN_STATUS_DIALOG" ) then
		local dialog, text = ...;
		GlueDialog_Show(dialog, text);
	end
end

function InGlue()
	return true;
end

function SecureCapsuleGet(name)
	return _G[name];
end

function nop()
end

-- =============================================================
-- State/Screen functions
-- =============================================================

function GlueParent_IsScreenValid(screen)
	local auroraState, connectedToWoW, wowConnectionState, hasRealmList = C_Login.GetState();
	if ( screen == "charselect" or screen == "charcreate" ) then
		return auroraState == LE_AURORA_STATE_NONE and (connectedToWoW or wowConnectionState == LE_WOW_CONNECTION_STATE_CONNECTING) and not hasRealmList;
	elseif ( screen == "realmlist" ) then
		return hasRealmList;
	elseif ( screen == "login" ) then
		return not connectedToWoW and not hasRealmList;
	else
		return false;
	end
end

function GlueParent_GetBestScreen()
	local auroraState, connectedToWoW, wowConnectionState, hasRealmList = C_Login.GetState();
	if ( hasRealmList ) then
		return "realmlist";
	elseif ( connectedToWoW ) then
		return "charselect";
	else
		return "login";
	end
end

function GlueParent_UpdateDialogs()
	local auroraState, connectedToWoW, wowConnectionState, hasRealmList, waitingForRealmList = C_Login.GetState();

	if ( auroraState == LE_AURORA_STATE_CONNECTING ) then
		GlueDialog_Show("CANCEL", LOGIN_STATE_CONNECTING);
	elseif ( auroraState == LE_AURORA_STATE_NONE and C_Login.GetLastError() ) then
		local errorCategory, errorID, localizedString, debugString = C_Login.GetLastError();

		local isHTML = false;
		local hasURL = false;

		--If we didn't get a string from C, look one up in GlueStrings as HTML
		if ( not localizedString ) then
			local tag = string.format("%s_ERROR_%d_HTML", errorCategory, errorID);
			localizedString = _G[tag];
			if ( localizedString ) then
				isHTML = true;
			end
		end

		--If we didn't get a string from C, look one up in GlueStrings
		if ( not localizedString ) then
			local tag = string.format("%s_ERROR_%d", errorCategory, errorID);
			localizedString = _G[tag];
		end

		--If we still don't have one, just display a generic error with the ID
		if ( not localizedString ) then
			localizedString = string.format(_G[errorCategory.."_ERROR_OTHER"], errorID);
		end

		--If we got a debug message, stick it on the end
		if ( debugString ) then
			localizedString = localizedString.."\n\n(DebugMessage: "..debugString..")";
		end

		--See if we want a URL as well
		local urlTag = string.format("%s_ERROR_%d_URL", errorCategory, errorID);
		if ( _G[urlTag] ) then
			hasURL = true;
		end

		if ( isHTML ) then
			GlueDialog_Show("OKAY_HTML", localizedString);
		elseif ( hasURL ) then
			GlueDialog_Show("OKAY_WITH_URL", localizedString, urlTag);
		else
			GlueDialog_Show("OKAY", localizedString);
		end

		C_Login.ClearLastError();
	elseif (  waitingForRealmList ) then
		GlueDialog_Show("REALM_LIST_IN_PROGRESS");
	elseif ( wowConnectionState == LE_WOW_CONNECTION_STATE_CONNECTING ) then
		GlueDialog_Show("CANCEL", GAME_SERVER_LOGIN);
	elseif ( wowConnectionState == LE_WOW_CONNECTION_STATE_IN_QUEUE ) then
		local waitPosition, waitMinutes, hasFCM = C_Login.GetWaitQueueInfo();
		
		if ( hasFCM ) then
			GlueDialog_Show("QUEUED_WITH_FCM", _G["QUEUE_FCM"]);
		elseif ( waitMinutes == 0 ) then
			local queueString = string.format(_G["QUEUE_TIME_LEFT_UNKNOWN"], waitPosition);
			GlueDialog_Show("QUEUED_NORMAL", queueString);
		elseif (waitMinutes == 1) then
			local queueString = string.format(_G["QUEUE_TIME_LEFT_SECONDS"], waitPosition);
			GlueDialog_Show("QUEUED_NORMAL", queueString);
		else
			local queueString = string.format(_G["QUEUE_TIME_LEFT"], waitPosition, waitMinutes);
			GlueDialog_Show("QUEUED_NORMAL", queueString);
		end
	else
		-- JS_TODO: make it so this only cancels state dialogs, like "Connecting"
		GlueDialog_Hide();
	end
end

function GlueParent_EnsureValidScreen()
	local currentScreen = GlueParent.currentScreen;
	if ( not GlueParent_IsScreenValid(currentScreen) ) then
		local bestScreen = GlueParent_GetBestScreen();

		LogAuroraClient("ae", "Screen invalid. Changing",
			"changingFrom", currentScreen,
			"changingTo", bestScreen);

		GlueParent_SetScreen(GlueParent_GetBestScreen());
	end
end

local function GlueParent_ChangeScreen(screenInfo, screenTable)
	LogAuroraClient("ae", "Switching to screen",
			"screen", screenInfo.frame);

	--Hide all other screens
	for key, info in pairs(screenTable) do
		if ( info ~= screenInfo ) then
			_G[info.frame]:Hide();
		end
	end

	--Start music. Have to do this before showing screen in case its OnShow changes screen.
	local displayedExpansionLevel = GetClientDisplayExpansionLevel();
	if ( screenInfo.playMusic ) then
		PlayGlueMusic(EXPANSION_GLUE_MUSIC[displayedExpansionLevel]);
	end
	if ( screenInfo.playAmbience ) then
		PlayGlueAmbience(EXPANSION_GLUE_AMBIENCE[displayedExpansionLevel], 4.0);
	end

	--Actually show this screen
	_G[screenInfo.frame]:Show();
end

function GlueParent_SetScreen(screen)
	local screenInfo = GLUE_SCREENS[screen];
	if ( screenInfo ) then
		GlueParent.currentScreen = screen;
		GlueParent_ChangeScreen(screenInfo, GLUE_SCREENS);
	end
end

function GlueParent_OpenSecondaryScreen(screen)
	local screenInfo = GLUE_SECONDARY_SCREENS[screen];
	if ( screenInfo ) then
		GlueParent.currentSecondaryScreen = screen;
		if ( screenInfo.fullScreen ) then
			GlueParent.ScreenFrame:Hide();
		else
			GlueParent.ScreenFrame:Show();
		end
		if ( screenInfo.showSound ) then
			PlaySound(screenInfo.showSound);
		end
		GlueParent_ChangeScreen(screenInfo, GLUE_SECONDARY_SCREENS);
	end
end

function GlueParent_CloseSecondaryScreen()
	if ( GlueParent.currentSecondaryScreen ) then
		local screenInfo = GLUE_SECONDARY_SCREENS[GlueParent.currentSecondaryScreen];
		GlueParent.currentSecondaryScreen = nil;

		--The secondary screen may have started music. Start the primary screen's music if so
		local primaryScreen = GlueParent.currentScreen;
		if ( primaryScreen and GLUE_SCREENS[primaryScreen] ) then
			local displayedExpansionLevel = GetClientDisplayExpansionLevel();
			if ( GLUE_SCREENS[primaryScreen].playMusic ) then
				PlayGlueMusic(EXPANSION_GLUE_MUSIC[displayedExpansionLevel]);
			end
			if ( GLUE_SCREENS[primaryScreen].playAmbience ) then
				PlayGlueAmbience(EXPANSION_GLUE_AMBIENCE[displayedExpansionLevel], 4.0);
			end
		end

		_G[screenInfo.frame]:Hide();

		--Show the original screen if we hid it. Have to do this last in case it opens a new secondary screen.
		if ( screenInfo.fullScreen ) then
			GlueParent.ScreenFrame:Show();
		end
	end
end

function GlueParent_CheckCinematic()
	local cinematicIndex = tonumber(GetCVar("playIntroMovie"));
	local displayExpansionLevel = GetClientDisplayExpansionLevel();
	if ( not cinematicIndex or cinematicIndex <= displayExpansionLevel ) then
		SetCVar("playIntroMovie", displayExpansionLevel + 1);
		MovieFrame.version = tonumber(GetCVar("playIntroMovie"));
		GlueParent_OpenSecondaryScreen("movie");
	end
end

-- =============================================================
-- Model functions
-- =============================================================

function SetLoginScreenModel(model)
	model:SetCamera(0);
	model:SetSequence(0);

	local expansionLevel = GetClientDisplayExpansionLevel();
	local lowResBG = EXPANSION_LOW_RES_BG[expansionLevel];
	local highResBG = EXPANSION_HIGH_RES_BG[expansionLevel];
	local background = GetLoginScreenBackground(highResBG, lowResBG);

	model:SetModel(background, true);
end

-- Function to get the background tag from a full path ( '..\UI_tagName.m2' )
function GetBackgroundModelTag(path)
	local pathUpper = strupper(path);
	local matchStart;
	local matchEnd;
	local tag;
	matchStart, matchEnd, tag = string.find(pathUpper, 'UI_(%a+).M2');
	if ( not tag ) then
		tag = "CHARACTERSELECT"; -- default
	end
	return tag;
end

function SetLighting(model, race)
	--model:SetSequence(0);
	model:SetCamera(0);
	local fogInfo = CHAR_MODEL_FOG_INFO[race];
	if ( fogInfo ) then
		model:SetFogColor(fogInfo.r, fogInfo.g, fogInfo.b);
		model:SetFogNear(0);
		model:SetFogFar(fogInfo.far);
	else
		model:ClearFog();
    end

    local glowInfo = CHAR_MODEL_GLOW_INFO[race];
    if ( glowInfo ) then
        model:SetGlow(glowInfo);
    else
		model:SetGlow(0.3);
    end

    model:ResetLights();
end

-- Function to set the background model for character select and create screens
function SetBackgroundModel(model, path)
	local nameupper = GetBackgroundModelTag(path);
	if ( model == CharacterCreate ) then
		SetCharCustomizeBackground(path);
	else
		SetCharSelectBackground(path);
	end
	if ( GLUE_AMBIENCE_TRACKS[nameupper] ) then
		PlayGlueAmbience(GLUE_AMBIENCE_TRACKS[nameupper], 4.0);
	end
	if ( ( model == CharacterSelectModel ) and ( string.find(model:GetModel(), 'lowres') == nil ) ) then
		SetLighting(model, nameupper)
	else
		SetLighting(model, "DEFAULT")
	end

	return nameupper;
end

-- =============================================================
-- Buttons
-- =============================================================

function GlueParent_ShowOptionsScreen()
	GlueParent_OpenSecondaryScreen("options");
end

function GlueParent_ShowCinematicsScreen()
	local numMovies = GetClientDisplayExpansionLevel() + 1;
	if ( numMovies == 1 ) then
		MovieFrame.version = 1;
		GlueParent_OpenSecondaryScreen("movie");
	else
		GlueParent_OpenSecondaryScreen("cinematics");
	end
end

function GlueParent_ShowCreditsScreen()
	GlueParent_OpenSecondaryScreen("credits");
end

-- =============================================================
-- Utils
-- =============================================================

function SetExpansionLogo(texture, expansionLevel)
	if ( EXPANSION_LOGOS[expansionLevel].texture ) then
		texture:SetTexture(EXPANSION_LOGOS[expansionLevel].texture);
	else
		texture:SetAtlas(EXPANSION_LOGOS[expansionLevel].atlas);
	end
end

function UpgradeAccount()
	PlaySound("gsLoginNewAccount");
	LoadURLIndex(2);
end

-- =============================================================
-- Backwards Compatibility
-- =============================================================
function getglobal(var)
	return _G[var];
end

function setglobal(var, val)
	_G[var] = val;
end
