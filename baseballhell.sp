#pragma semicolon 1

#include <tf2_stocks>
#include <sdkhooks>
#include <sourcemod>

#define REQUIRE_EXTENSIONS
#define AUTOLOAD_EXTENSIONS
#include <tf2items>

#undef REQUIRE_PLUGIN
#tryinclude <tf2itemsinfo>

#define REQUIRE_PLUGIN
#include <tf2items_giveweapon>

#define LOCH_ID 9090
#define ORNAMENT_ID 9091
#define CLEAVER_ID 9092

#define PROJ_MODE 2;

#define PLUGIN_VERSION  "1.60.10.0"

#if !defined _tf2itemsinfo_included
new TF2ItemSlot = 8;
#endif
 
static const int:BASEBALL_ID = int:9200; 
new Handle:handleEnabled = INVALID_HANDLE;
new Handle:handleSpeed = INVALID_HANDLE;
new Handle:handleGameMode = INVALID_HANDLE;

//this is the global delay multiplier, set by baseballhell_delay_multi
static Float:delayFloatMultiplier = Float:1.0;

//this is the modifier to make the cleaver faster, don't change this
static const Float:cleaverFloatMultiplier = Float:0.3;

//this is the modifier to make the lochnload faster, don't change this
static const Float:lochFloatMultiplier = Float:0.417;

//this is the bat's base fire rate, don't change this
static const Float:ballDelay = Float:0.25;

//these are for concatenation, you shouldn't touch these
new String:baseBallString[100];
new String:cleaverString[100];
new String:lochString[200];
new String:announceString[100];
new String:cleaverStringSpeedMultiplier[5];
new String:lochStringSpeedMultiplier[5];

//this is the final cleaver speed multiplier 
static Float:cleaverFloatSpeed = Float:0.25;

//this is the final loch speed multiplier 
static Float:lochFloatSpeed = Float:0.25;

//gamemode handler
new String:gameMode[100] = "SCOUT_PLAY_ALL_WEAPONS";

//enabled handler
static int:intEnabled = int:0; 

static Handle:timerArray[MAXPLAYERS + 1];

static bool:cooldownArray[MAXPLAYERS + 1];

static const int:startingHealth = int:40;

//array for 40 health settings
static const String:healthReduc[9][5] = 
{
	"-85",
	"-160",
	"-135",
	"-135",
	"-260",
	"-85",
	"-110",
	"-85",
	"-85"
};

public Plugin:myinfo =
{
	name = "[TF2] Baseball Hell",
	author = "Kami",
	description = "A laggy projectile based game modifier that promotes baseball and other projectile spam, along with other gameplay modifiers.",
	version = PLUGIN_VERSION,
	url = "http://steamcommunity.com/id/BlazinH"
};

public OnPluginStart()
{
	//Create all these dumb ConVars and hook them
	CreateConVar("baseballhell_version", PLUGIN_VERSION, "Baseball Hell Version.", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	handleEnabled = CreateConVar("baseballhell_enabled", "0", "Enable/Disable Baseball Hell", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 1.0);
	handleSpeed = CreateConVar("baseballhell_delay_multi", "1", "Fire Rate for projectiles. Increase this if the server lags.", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_NOTIFY, true, 1.0, true, 10.0);
	handleGameMode = CreateConVar("baseballhell_mode", "SCOUT_PLAY_ALL_WEAPONS", "The mode of Baseball hell. \n SCOUT_PLAY_ALL_WEAPONS - Scouts only, all weapons, special scout implements. \n SCOUT_PLAY_BAT_ONLY - Same as above, but only the sandman is equipped. \n ALL_PLAY_ALL_WEAPONS - All classes can play, with all weapons. Scouts have no double jump. \n ALL_PLAY_BAT_ONLY - Same as above, but only the sandman is equipped.", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_NOTIFY);
	HookConVarChange(handleGameMode, GameModeChanged);
	HookConVarChange(handleSpeed, cvarSpeed);
	HookConVarChange(handleEnabled, EnableThis);
	
	//inventory hook
	HookEvent( "post_inventory_application", OnPostInventoryApplicationAndPlayerSpawn );
	HookEvent( "player_spawn", OnPostInventoryApplicationAndPlayerSpawn );
	
	//hook for disabling respawn timer
	HookEvent( "teamplay_round_start", OnMapChange );
	
	//watch for sentries
	AddCommandListener(CommandListener_Build, "build");
}

public EnableThis(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	if (!StrEqual(oldVal,newVal))
	{
		intEnabled = int:StringToInt(newVal);
		
		if (intEnabled == int:1)
		{
			ServerCommand("mp_disable_respawn_times 1");
			ScoutCheck();
			//set all health to 40
			for(new i = 1; i <= MAXPLAYERS; i++)
			{
				if (IsValidClient(i))
				{
					SetEntData(i, FindDataMapOffs(i, "m_iHealth"), startingHealth, 4, true);
				}
			}
		}
		else
		{
			//sorry
			ServerCommand("sm_slay @all");
			//disable and normalize 
			ServerCommand("sm_smj_global_enabled 0");
			ServerCommand("sm_smj_global_limit 1");
			ServerCommand("mp_disable_respawn_times 0");
			ServerCommand("sm_resetspeed @all");
			for(new i = 1; i <= MAXPLAYERS; i++)
			{
				if (IsValidClient(i))
				{
					//remove the notarget flag
					new flags = GetEntityFlags(i)&~FL_NOTARGET;
					SetEntityFlags(i, flags);
				}
			}
		}
	}
}

//checks if it's safe to modify the client at this index
stock bool:IsValidClient(client)
{
	if (client <= 0) return false;
	if (client > MaxClients) return false;
	return IsClientInGame(client);
}

//set the secret ammo
stock SetSpeshulAmmo(client, wepslot, newAmmo)
{
	new weapon = GetPlayerWeaponSlot(client, wepslot);
	if (!IsValidEntity(weapon)) return;
	new type = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
	if (type < 0 || type > 31) return;
	SetEntProp(client, Prop_Send, "m_iAmmo", newAmmo, _, type);
}

//get the secret ammo
stock GetSpeshulAmmo(client, wepslot)
{
	if (!IsValidClient(client)) return 0;
	new weapon = GetPlayerWeaponSlot(client, wepslot);
	if (!IsValidEntity(weapon)) return 0;
	new type = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
	if (type < 0 || type > 31) return 0;
	return GetEntProp(client, Prop_Send, "m_iAmmo", _, type);
}

//when the player does anything, reset their ammo (this is inefficient)
public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
	if ((buttons & IN_ATTACK2) && (GetSpeshulAmmo(client , TFWeaponSlot_Melee) > 0) && (FloatMul(Float:ballDelay, Float:delayFloatMultiplier) > Float:0.25)) 
	{ ResetTimer(int:client); }
	else if ((GetSpeshulAmmo(client, TFWeaponSlot_Melee) < 1) && (FloatMul(Float:ballDelay, Float:delayFloatMultiplier) <= Float:0.25)) 
	{ SetSpeshulAmmo(client, TFWeaponSlot_Melee, 1); }
	if ((!StrEqual("ALL_PLAY_BAT_ONLY", gameMode, false) && !StrEqual("SCOUT_PLAY_BAT_ONLY", gameMode, false)) && (GetSpeshulAmmo(client, TFWeaponSlot_Secondary) < 1))
	{ SetSpeshulAmmo(client, TFWeaponSlot_Secondary, 1); }
}

//reset ammo when fired
public Action:timerRegen(Handle:timer, any:data)
{
	if(cooldownArray[int:data]) { cooldownArray[int:data] = false; }
	if(IsValidClient(int:data) && (GetSpeshulAmmo(int:data, TFWeaponSlot_Melee) < 1)) { SetSpeshulAmmo(int:data, TFWeaponSlot_Melee, 1); }
	timerArray[int:data] = INVALID_HANDLE;
}

public ResetAllTimers()
{
	for(new i = 1; i <= MAXPLAYERS; i++) 
	{ if (IsValidClient(i)) { ResetTimer(int:i); } }
}

public ResetTimer(int:client)
{
	if ((GetSpeshulAmmo(client, TFWeaponSlot_Melee) > 0) && !cooldownArray[client])
	{
		cooldownArray[client] = true;
		timerArray[client] = CreateTimer(FloatMul(Float:ballDelay, Float:delayFloatMultiplier), Timer:timerRegen, client);
	}
}


public OnAllPluginsLoaded() 
{
	//make some weapons
	CreateWeapons();
	
	//this plugin needs scout multijump
	if (intEnabled == int:1)
	{
		ServerCommand("sm_smj_global_enabled 1");
	}
	
	//the scout only modes enable infinitejump
	if ((StrEqual("SCOUT_PLAY_ALL_WEAPONS", gameMode, false) || StrEqual("SCOUT_PLAY_BAT_ONLY", gameMode, false)) && (intEnabled == int:1))
	{
		ServerCommand("sm_smj_global_limit 0");
	}
	else
	{ //the all class modes disable scouts double jump (this is changed somewhere else)
		ServerCommand("sm_smj_global_limit 1");
	}
} 

//create the cleaver and an array of a bats with different health decreases
public CreateWeapons()
{
	lochString = "408 ; 1 ; 127 ; 2 ; 103 ; 2.45 ; 370 ; 68 ; 97 ; 0.1 ; 100 ; 0.04 ; 3 ; 0.25 ; 112 ; 1 ; 76 ; 2 ; 178 ; 0.1 ; 6 ; ";
	
	//concatenate the fire delay multiplier onto the attributes of the loch-n-load
	lochFloatSpeed = FloatMul(delayFloatMultiplier, lochFloatMultiplier) ;
	lochFloatSpeed = FloatSub(lochFloatSpeed, lochFloatMultiplier / Float:2.0 ) ; //compensate for reload animation
	FloatToString(lochFloatSpeed, lochStringSpeedMultiplier, 5);
	StrCat(lochString, 200, lochStringSpeedMultiplier);

	TF2Items_CreateWeapon( LOCH_ID, "tf_weapon_grenadelauncher", 308, 0, 9, 10, lochString, -1, _, true ); 

	//concatenate the fire delay multiplier onto the attributes of the cleaver
	cleaverFloatSpeed = FloatMul(delayFloatMultiplier, cleaverFloatMultiplier) ;
	FloatToString(cleaverFloatSpeed, cleaverStringSpeedMultiplier, 5);
	cleaverString = "408 ; 1 ; 370 ; 56 ; 178 ; 0.1 ; 6 ; ";
	StrCat(cleaverString, 100, cleaverStringSpeedMultiplier);
	TF2Items_CreateWeapon( CLEAVER_ID, "tf_weapon_cleaver", 812, 1, 9, 10, cleaverString, -1, _, true ); 
	
	//for each class
	for (new int:class = int:0 ; class < int:9 ; class++)
	{
		if ((class != int:0) && (!StrEqual("SCOUT_PLAY_ALL_WEAPONS", gameMode, false) && !StrEqual("SCOUT_PLAY_BAT_ONLY", gameMode, false)))
		{
			break; //only create the scout bat if scouts only mode
		}
		//in order: launch balls, set switch speed to 10%, attach a particle
		baseBallString = "38 ; 1 ; 178 ; 0.1 ; 370 ; 43";
		
		if (class != int:0) //if this class isnt a scout
		{
			//concatenate better cap speed
			StrCat(baseBallString, 100, " ; 68 ; 1");
		}
		
		//concatenate the health reduction
		StrCat(baseBallString, 100, " ; 125 ; ");
		StrCat(baseBallString, 100, healthReduc[class]);

		//concatenate an attribute on engineer's bat; bots can only build minisentries, if they can at all
		if (class == int:5)
		{
			StrCat(baseBallString, 100, " ; 124 ; 1");
		}
		//concatenate no double jumps onto a scout's bat if a scout only mode is not on
		else if ((!StrEqual("SCOUT_PLAY_ALL_WEAPONS", gameMode, false)) && (!StrEqual("SCOUT_PLAY_BAT_ONLY", gameMode, false)) && (class == int:0))
		{
			StrCat(baseBallString, 100, " ; 49 ; 1"); //no double jumps on all player modes
		}
		TF2Items_CreateWeapon( (BASEBALL_ID + class) , "tf_weapon_bat_wood", 44, 2, 9, 10, baseBallString, -1, _, true ); 
	}
}

//handles a timer for baseball regeneration (isn't accurate, but is stable)
public cvarSpeed(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	delayFloatMultiplier = Float:StringToFloat(newVal);

	if (intEnabled == int:1)
	{
		announceString = "Fire rate set to ";
		new String:damn[5];
		FloatToString(FloatMul(Float:ballDelay, Float:delayFloatMultiplier), damn, 5);
		StrCat(announceString, 100, damn);
		StrCat(announceString, 100, " seconds");
		AnnounceAll();
		CreateWeapons();
		IssueNewWeapons();
	}
}

public AnnounceAll()
{
	for(new i = 1; i <= MAXPLAYERS; i++)
	{ if (IsValidClient(i)){ PrintHintText( i, announceString); } }
}

public GameModeChanged(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	//set a new game mode
	GetConVarString(cvar, gameMode, 100);
	announceString = "Baseball Hell mode set to ";
	new String:daMode[30];

	if (StrEqual("SCOUT_PLAY_ALL_WEAPONS", gameMode, false)){ daMode = "Scouts only, with all weapons"; }
	else if (StrEqual("SCOUT_PLAY_BAT_ONLY", gameMode, false)){ daMode = "Scouts with bat only"; }
	else if (StrEqual("ALL_PLAY_ALL_WEAPONS", gameMode, false)){ daMode = "All classes with all weapons"; }
	else if (StrEqual("ALL_PLAY_BAT_ONLY", gameMode, false)){ daMode = "All classes, with bat only"; }
	else { daMode = "who knows what!"; }
	StrCat(announceString, 100, daMode);
	AnnounceAll();
	ScoutCheck();
}

public ScoutCheck()
{
	if (intEnabled == int:1)
	{
		//scout only
		if (StrEqual("SCOUT_PLAY_ALL_WEAPONS", gameMode, false) || StrEqual("SCOUT_PLAY_BAT_ONLY", gameMode, false))
		{
			for(new i = 1; i <= MAXPLAYERS; i++)
			{ if (IsValidClient(i)) { TF2_SetPlayerClass(i, TFClass_Scout, false, true); } }
		}
		OnAllPluginsLoaded();
		IssueNewWeapons();
	}
}


public IssueNewWeapons()
{
	for(new i = 1; i <= MAXPLAYERS; i++)
	{
		if(IsValidClient(i))
		{
			RemoveAllWeapons(i);
			GiveArray(i);
		}
	}
}

public RemoveAllWeapons(client)
{
    for( new iSlot = 0; iSlot < _:TF2ItemSlot; iSlot++ )
        TF2_RemoveWeaponSlot( client, iSlot );
}

public GiveArray(client)
{
	if ((!StrEqual("ALL_PLAY_BAT_ONLY", gameMode, false)) && (!StrEqual("SCOUT_PLAY_BAT_ONLY", gameMode, false)))
	{
		TF2Items_GiveWeapon( client, CLEAVER_ID );
		TF2Items_GiveWeapon( client, LOCH_ID );
	}

	//each sandman has a different health decrease assigned to it, for different classes
	switch(TF2_GetPlayerClass(client))
	{
		case TFClass_Scout: TF2Items_GiveWeapon( client, BASEBALL_ID );
		case TFClass_Soldier: TF2Items_GiveWeapon( client, BASEBALL_ID + int:1 );
		case TFClass_Pyro: TF2Items_GiveWeapon( client, BASEBALL_ID + int:2 );
		case TFClass_DemoMan: TF2Items_GiveWeapon( client, BASEBALL_ID + int:3 );
		case TFClass_Heavy: TF2Items_GiveWeapon( client, BASEBALL_ID + int:4 );
		case TFClass_Engineer: TF2Items_GiveWeapon( client, BASEBALL_ID + int:5 );
		case TFClass_Medic: TF2Items_GiveWeapon( client, BASEBALL_ID + int:6 );
		case TFClass_Sniper: TF2Items_GiveWeapon( client, BASEBALL_ID + int:7 );
		case TFClass_Spy: TF2Items_GiveWeapon( client, BASEBALL_ID + int:8 );
	}
}

public OnMapChange( Handle:hEvent, const String:strEventName[], bool:bDontBroadcast )
{
	if (GetEventBool(hEvent, "full_reset") && (intEnabled == int:1))
	{
		ServerCommand("mp_disable_respawn_times 1");
		ScoutCheck();
	}
}

public OnPostInventoryApplicationAndPlayerSpawn( Handle:hEvent, const String:strEventName[], bool:bDontBroadcast )
{
	
	if (intEnabled == int:1) //these need to be fired constantly in case of new people
	{
		new iClient = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
		if( iClient <= 0 || iClient > MaxClients || !IsClientInGame(iClient) /*|| !IsPlayerAlive(iClient)*/ )
		return;
	
		//if scout only game mode set this person to scout
		if (StrEqual("SCOUT_PLAY_ALL_WEAPONS", String:gameMode, false) || StrEqual("SCOUT_PLAY_BAT_ONLY", String:gameMode, false))
		{
			TF2_SetPlayerClass(iClient, TFClass_Scout, false, true);
		}
		
		RemoveAllWeapons(iClient);
		GiveArray(iClient);
		
		//make everyone fast like scout (this is inefficient)
		if (StrEqual("ALL_PLAY_BAT_ONLY", gameMode, false) || StrEqual("ALL_PLAY_ALL_WEAPONS", gameMode, false))
		{
			ServerCommand("sm_setspeed @all 400");
		}
		
		//disable sentry targeting on this person
		new flags = GetEntityFlags(iClient)|FL_NOTARGET;
		SetEntityFlags(iClient, flags);
	}
}

//crits should always be enabled while the game modifier is active
public Action:TF2_CalcIsAttackCritical(client, weapon, String:weaponname[], &bool:result)
{
	if (intEnabled == int:1)
	{
		result = true; //100% crits
		return Plugin_Handled;
	}
	else
	{
		return Plugin_Continue;
	}
}

//Disable building if the plugin is enabled
public Action:CommandListener_Build(client, const String:command[], argc)
{
	if (intEnabled == int:1)
	{
		return Plugin_Handled;
	}
	else
	{
		return Plugin_Continue;
	}
}
