-------------------------------------------------------------------------------
-- This context manages the world anchored plot text.  These the the 'floater' values
-- that get displayed when a unit/city takes damage, etc.

include( "InstanceManager" );
include( "mod_settings" );
local g_FloatUpPlotTextInstanceManager		= InstanceManager:new( "FloatUpPlotText", "Anchor", Controls.FloatUpPlotTextContainer );

-- Active instance of a message
hstructure InstancedMessageEntry

	plotIndex		: number;
	turnAdded		: number;
	instance		: table;

end

local g_PlotTextInstanceMap					= {};

-- Instance number so we can identify the instance in the animation callback
local g_PlotTextInstanceNumber = 1;

-- Message in the queue
hstructure QueuedMessageEntry

	messageType		: number;
	delay			: number;
	plotIndex		: number;
	text			: string;
	turnAdded		: number;

end

local g_QueuedMessages						= {};

----------------------------------------------------------------        
-- Return the first queued message that is for the specified plot index.
function GetFirstQueuedMessageAt( plotIndex )
	-- There should not be very many queued messages, so just to a simple search.
	for i, queueEntry in ipairs(g_QueuedMessages) do
		if (queueEntry.plotIndex == plotIndex) then
			return table.remove(g_QueuedMessages, i);
		end
	end

	return nil;
end

----------------------------------------------------------------        
-- Is there an active message at the plot index?
function IsActiveMessageAt( plotIndex )
	-- Find an active message at the plot
	for _, activeEntry in pairs(g_PlotTextInstanceMap) do
		if (activeEntry.plotIndex == plotIndex) then
			return true;
		end
	end

	return false;
end

----------------------------------------------------------------        
-- Add a message to the queue
function QueueMessage( messageType, delay, plotIndex, text )

	if (IsActiveMessageAt(plotIndex)) then
		-- There is already a message at that plot, queue this one up
	    local queuedMessage = hmake QueuedMessageEntry { messageType = messageType, delay = delay, plotIndex = plotIndex, text = text, turnAdded = Game.GetCurrentGameTurn() };
		table.insert( g_QueuedMessages, queuedMessage );
		return true;
	else
		return false;
	end
end

----------------------------------------------------------------        
-- Handle the animation end
function MessageAnimEndHandler( control )

	-- The animation is complete, release the control from the instance manager
	local instanceKey = control:GetVoid1();
    local instanceEntry = g_PlotTextInstanceMap[ instanceKey ];
    
    if ( instanceEntry ~= nil ) then
        g_FloatUpPlotTextInstanceManager:ReleaseInstance( instanceEntry.instance );
		local plotIndex = instanceEntry.plotIndex;
        g_PlotTextInstanceMap[ instanceKey ] = nil;
		if (table.count( g_PlotTextInstanceMap ) == 0) then
			-- If empty, reset the counter.
			g_PopupInstanceNumber = 1;
		end

		-- See if there is a queued message waiting at that location
		local queuedMessage = GetFirstQueuedMessageAt( plotIndex );
		if (queuedMessage ~= nil) then
			AddMessage(queuedMessage.messageType, queuedMessage.delay, queuedMessage.plotIndex, queuedMessage.text, queuedMessage.turnAdded);
		end

    end
end

----------------------------------------------------------------        
function DestroyAllPlotText( )

	for i, v in pairs(g_PlotTextInstanceMap) do
		if (v.instance ~= nil) then
	        g_FloatUpPlotTextInstanceManager:ReleaseInstance( v.instance );
		end
	end

	g_FloatUpPlotTextInstanceManager:ResetInstances();
	g_PlotTextInstanceMap = {};
	g_PlotTextInstanceNumber = 1;
	g_QueuedMessages = {};
end

----------------------------------------------------------------        
-- Remove messages that are more than 2 turns old.
function DestroyOldPlotText()

	local killTurn = Game.GetCurrentGameTurn() - 2;

	-- Remove active ones.
	for i, v in pairs(g_PlotTextInstanceMap) do
		if (v.instance ~= nil) then
			if (v.turnAdded <= killTurn) then 
				g_FloatUpPlotTextInstanceManager:ReleaseInstance( v.instance );
				g_PlotTextInstanceMap[ i ] = nil;
			end
		end
	end

	if (table.count( g_PlotTextInstanceMap ) == 0) then
		-- If empty, reset the counter.
		g_PopupInstanceNumber = 1;
	end

	-- Remove queued ones.
	local i=1;
	while i < #g_QueuedMessages do
		local v = g_QueuedMessages[i];
		if (v.turnAdded <= killTurn) then
			table.remove(g_QueuedMessages, i);
		else
			i = i + 1;
		end
	end

	-- Activate ones from the queue
	i=1;
	while i < #g_QueuedMessages do
		local v = g_QueuedMessages[i];
		if (not IsActiveMessageAt(v.plotIndex)) then
			AddMessage(v.messageType, v.delay, v.plotIndex, v.text, v.turnAdded);
			table.remove(g_QueuedMessages, i);
		else
			i = i + 1;
		end
	end
end

----------------------------------------------------------------        
function AddMessage( messageType, delay, plotIndex, text, turnAdded )

    local instance = g_FloatUpPlotTextInstanceManager:GetInstance();
		
	local x, y = Map.GetPlotLocation(plotIndex);
	local worldX, worldY, worldZ = UI.GridToWorld( x, y );
    instance.Anchor:SetWorldPositionVal( worldX, worldY, worldZ );
    instance.Text:SetText( text );
    instance.AlphaAnimOut:RegisterEndCallback( MessageAnimEndHandler );
	instance.AlphaAnimOut:SetVoid1( g_PlotTextInstanceNumber );

    instance.SlideAnim:SetPauseTime( delay );
    instance.AlphaAnimIn:SetPauseTime( delay );
    instance.AlphaAnimOut:SetPauseTime( delay + 0.75 );
    
	-- Reset and play the animations.  We used to call BranchResetAnimation on the parent (Anchor), but now that the items are global update, this doesn't work.
	instance.AlphaAnimOut:SetToBeginning();
	instance.AlphaAnimOut:Play();

	instance.AlphaAnimIn:SetToBeginning();
	instance.AlphaAnimIn:Play();

	instance.SlideAnim:SetToBeginning();
	instance.SlideAnim:Play();

    g_PlotTextInstanceMap[ g_PlotTextInstanceNumber ] = hmake InstancedMessageEntry{ plotIndex = plotIndex, instance = instance, turnAdded = turnAdded };

	g_PlotTextInstanceNumber = g_PlotTextInstanceNumber + 1;
end

----------------------------------------------------------------        
----------------------------------------------------------------        
function AddPlotText( messageType, delay, x, y, text )

	-- Convert to an index
	local plotIndex = Map.GetPlotIndex(x, y);

	-- Create a plot text message.
	-- Currently this is ignoring the eMessageType, though in the future it
	-- might use it to pick which type of instance to create.
	if (not QueueMessage(messageType, delay, plotIndex, text)) then
		AddMessage(messageType, delay, plotIndex, text, Game.GetCurrentGameTurn());
	end
end
Events.WorldTextMessage.Add( AddPlotText );

----------------------------------------------------------------
-- Local player has changed
----------------------------------------------------------------
function OnLocalPlayerChanged(iLocalPlayer, iPrevLocalPlayer)

	DestroyAllPlotText();

end
--- Events.LocalPlayerChanged.Add(OnLocalPlayerChanged);


------------------ Keyboard navigation -----------------------------------------------
-- UI for keyboard navigation live here rather than in worldinput because the indicator 
-- should show up at the top of the wold-view z-order (so it draws over things like city banners 
-- and unit flags but beneath all hud and screen stuff).  And apparently z-order is implicit and 
-- tied to lua context order, so it pretty much has to live here.  Which is kind of reasonable - 
-- it is a plot info message of a certain form.

local keyboardTargetMouseMoveSettingValues = {
    "LOC_MORE_KEY_BINDINGS_KEYBOARD_TARGETING_DISPLAY_MODE_ALWAYS",
    "LOC_MORE_KEY_BINDINGS_KEYBOARD_TARGETING_DISPLAY_MODE_HIDE_ON_MOUSE_USE",
    "LOC_MORE_KEY_BINDINGS_KEYBOARD_TARGETING_DISPLAY_MODE_FADE_ON_MOUSE_USE"};
local keyboardTargetMouseMoveSetting = ModSettings.Select:new(
    keyboardTargetMouseMoveSettingValues, 3, 
    "LOC_MORE_KEY_BINDINGS_MOD_SETTINGS_CATEGORY",
    "LOC_MORE_KEY_BINDINGS_KEYBOARD_TARGETING_DISPLAY_MODE");

-- Keep track of visibility so we don't start refading it every time the mouse moves.  
-- That would look as stupid as the background fading when switching between tech/civic screens
-- (and other similar level screen popups).
local keyboardTargetingVisibility = true;

function UpdateKeyboardTargetingVisibility(visible:boolean)
  if visible then
    Controls.KeyboardPlotTargetingAnchor:SetHide(false);
    Controls.KeyboardPlotTargetAlpha:SetToBeginning();
  else
    if keyboardTargetMouseMoveSetting.Value == "LOC_MORE_KEY_BINDINGS_KEYBOARD_TARGETING_DISPLAY_MODE_HIDE_ON_MOUSE_USE" then 
      Controls.KeyboardPlotTargetingAnchor:SetHide(true);
    elseif keyboardTargetMouseMoveSetting.Value == "LOC_MORE_KEY_BINDINGS_KEYBOARD_TARGETING_DISPLAY_MODE_FADE_ON_MOUSE_USE" then
      if keyboardTargetingVisibility then
        Controls.KeyboardPlotTargetAlpha:SetToBeginning();
        Controls.KeyboardPlotTargetAlpha:Play();
      end
    end
  end
  keyboardTargetingVisibility = visible;
end

function OnUpdateKeyboardTargetingPlot(plotX:number, plotY:number, implicit:boolean)
  -- Apparently you can't just send it directly to SetWorldPositionVal because there's a 4th element
  -- that is ... who the fuck knows.  The game doesn't seem to use it anywhere.
  local worldX, worldY, worldZ = UI.GridToWorld(plotX, plotY);
  Controls.KeyboardPlotTargetingAnchor:SetWorldPositionVal(worldX, worldY, worldZ);

  local visibility = keyboardTargetingVisibility;
  if not implicit then
    visibility = true;
  end
  UpdateKeyboardTargetingVisibility(visibility);
end

local keyboardTargetDisabledByInterfaceMode = {};
local keyboardTargetIconByInterfaceMode = {};

function RegisterKeyboardTargetDisplaySettings(interfaceMode:number, icon:string, disabled:boolean)
  keyboardTargetDisabledByInterfaceMode[interfaceMode] = disabled;
  keyboardTargetIconByInterfaceMode[interfaceMode] = icon;

  UpdateKeyboardTarget();
end

-- By default hide the keyboard targeting outline in MOVE_TO mode since it doesn't play well 
-- with the move-to path (and in particular the turn numbering).  Allow users to turn it on if they want.
local hideKeyboardTargetOutlineInMoveToMode = ModSettings.Boolean:new(
    true,
    "LOC_MORE_KEY_BINDINGS_MOD_SETTINGS_CATEGORY", 
    "LOC_MORE_KEY_BINDINGS_HIDE_KEYBOARD_TARGETING_OUTLINE_IN_MOVE_TO_MODE",
    "LOC_MORE_KEY_BINDINGS_HIDE_KEYBOARD_TARGETING_OUTLINE_IN_MOVE_TO_MODE_TOOLTIP");

function UpdateKeyboardTarget(interfaceMode:number)
  interfaceMode = interfaceMode or UI.GetInterfaceMode();

  local disabled = keyboardTargetDisabledByInterfaceMode[interfaceMode] or false;
  Controls.KeyboardPlotTargetOutline:SetHide(disabled);
  Controls.KeyboardTargetAction:SetHide(disabled);

  local modeIcon = keyboardTargetIconByInterfaceMode[interfaceMode];
  modeIcon = modeIcon or "ICON_MORE_KEY_BINDINGS_KEYBOARD";
  Controls.KeyboardTargetAction:SetIcon(modeIcon);
end

function OnUnitSelectionChanged(playerID:number, unitID:number, hexI:number, hexJ:number, hexK:number, isSelected:boolean, isEditable:boolean)
  UpdateKeyboardTarget();
end

function OnInterfaceModeChanged(oldMode:number, newMode:number)
  UpdateKeyboardTarget(newMode);
end

-- Hide keyboard targeting display during battle so it doesn't interfere with the grand 
-- view of your troops impaling the enemy. /s
function OnCombatVisBegin(data:table)
  Controls.KeyboardPlotTargetingAnchor:SetHide(true);
end

function OnCombatVisEnd(data:table)
  Controls.KeyboardPlotTargetingAnchor:SetHide(false);
  UpdateKeyboardTargetingVisibility(keyboardTargetingVisibility);
end


function OnInputHandler(input:table)
	if input:GetMessageType() == MouseEvents.MouseMove and (input:GetMouseDX() ~= 0 or input:GetMouseDY() ~= 0) then
		UpdateKeyboardTargetingVisibility(false);
	end
end

function Initialize()
  RegisterKeyboardTargetDisplaySettings(InterfaceModeTypes.FORM_CORPS, "ICON_UNITCOMMAND_FORM_CORPS");
  RegisterKeyboardTargetDisplaySettings(InterfaceModeTypes.FORM_ARMY, "ICON_UNITCOMMAND_FORM_ARMY");
  RegisterKeyboardTargetDisplaySettings(InterfaceModeTypes.RANGE_ATTACK, "ICON_UNITOPERATION_RANGE_ATTACK");
  RegisterKeyboardTargetDisplaySettings(InterfaceModeTypes.CITY_RANGE_ATTACK, "ICON_UNITOPERATION_RANGE_ATTACK");
  RegisterKeyboardTargetDisplaySettings(InterfaceModeTypes.DISTRICT_RANGE_ATTACK, "ICON_UNITOPERATION_RANGE_ATTACK");
  RegisterKeyboardTargetDisplaySettings(InterfaceModeTypes.AIR_ATTACK, "ICON_UNITOPERATION_AIR_ATTACK");
  RegisterKeyboardTargetDisplaySettings(InterfaceModeTypes.PRIORITY_TARGET, "ICON_UNITCOMMAND_PRIORITY_TARGET");
  RegisterKeyboardTargetDisplaySettings(InterfaceModeTypes.REBASE, "ICON_UNITOPERATION_REBASE");
  RegisterKeyboardTargetDisplaySettings(InterfaceModeTypes.DEPLOY, "ICON_UNITOPERATION_DEPLOY");
  RegisterKeyboardTargetDisplaySettings(InterfaceModeTypes.AIRLIFT, "ICON_UNITCOMMAND_AIRLIFT");
  RegisterKeyboardTargetDisplaySettings(InterfaceModeTypes.COASTAL_RAID, "ICON_UNITOPERATION_COASTAL_RAID");
  RegisterKeyboardTargetDisplaySettings(InterfaceModeTypes.TELEPORT_TO_CITY, "ICON_UNITOPERATION_TELEPORT_TO_CITY");
  RegisterKeyboardTargetDisplaySettings(InterfaceModeTypes.WMD_STRIKE, "ICON_UNITOPERATION_WMD_STRIKE");
  RegisterKeyboardTargetDisplaySettings(InterfaceModeTypes.ICBM_STRIKE, "ICON_UNITOPERATION_WMD_STRIKE");

  hideKeyboardTargetOutlineInMoveToMode:AddChangedHandler(
    function(value:boolean, oldValue:boolean)
      -- Use no icon so the number in the path shows through.
      RegisterKeyboardTargetDisplaySettings(InterfaceModeTypes.MOVE_TO, "ICON_MORE_KEY_BINDINGS_NONE", value);
    end, true);

  ContextPtr:SetInputHandler(OnInputHandler, true);
  keyboardTargetMouseMoveSetting:AddChangedHandler(function(value, oldValue) 
    UpdateKeyboardTargetingVisibility(true);
    UpdateKeyboardTargetingVisibility(value);
  end);
  Events.UnitSelectionChanged.Add(OnUnitSelectionChanged);
  Events.InterfaceModeChanged.Add(OnInterfaceModeChanged);
  Events.CombatVisBegin.Add(OnCombatVisBegin);
  Events.CombatVisEnd.Add(OnCombatVisEnd);
  LuaEvents.WorldNavigation_UpdateKeyboardTargetingPlot.Add(OnUpdateKeyboardTargetingPlot);
  LuaEvents.WorldNavigation_RegisterKeyboardTargetDisplaySettings.Add(RegisterKeyboardTargetDisplaySettings);
end

Initialize();