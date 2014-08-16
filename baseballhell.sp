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

#define PROJ_MODE 2;

#define PLUGIN_VERSION  "1.62.1.0nw"

#if !defined _tf2itemsinfo_included
new TF2ItemSlot = 8;
#endif

/*
#define LOCH_ID 9090
#define CLEAVER_ID 9092
#define DETON_ID 9093
#define HUNTS_ID 9094
#define ROCKET_ID 9095

 
static const int:BASEBALL_ID = int:9200; 
*/
new Handle:handleEnabled = INVALID_HANDLE;
new Handle:handleSpeed = INVALID_HANDLE;
new Handle:handleGameMode = INVALID_HANDLE;

//this is the global delay multiplier, set by baseballhell_delay_multi
static Float:delayFloatMultiplier = Float:1.0;

static const ids[6] =
{
	9200,
	9092,
	9090,
	9093,
	9094,
	9095
}

//in order, ball delay, cleaver multi, loch multi, deton multi, hunts multi, rocket multi,
static const Float:floatMultiplier[6] =
{
	0.2500,
	0.3000,
	0.4167,
	0.1250,
	0.0834,
	0.3125
};

static String:concatString[6][200];

static String:stringMultiplier[6][6];

static workingFloat[6] =
{
	0.25,
	0.25,
	0.25,
	0.25,
	0.25,
	0.25
}

/*
//this is the bat's base fire rate, don't change this
static const Float:ballDelay = Float:0.25;
//this is the modifier to affect the natural rate of these weapons, don't change these
static const Float:cleaverFloatMultiplier = Float:0.3;
static const Float:lochFloatMultiplier = Float:0.417;
static const Float:detonFloatMultiplier = Float:0.125;
static const Float:huntsFloatMultiplier = Float:0.0834;
static const Float:rocketFloatMultiplier = Float:0.3125;

//these are for concatenation, you shouldn't touch these
new String:baseBallString[100];
new String:cleaverString[100];
new String:lochString[200];
new String:detonString[200];
new String:huntsString[200];
new String:rocketString[200];


new String:cleaverStringSpeedMultiplier[5];
new String:lochStringSpeedMultiplier[5];
new String:detonStringSpeedMultiplier[5];
new String:huntsStringSpeedMultiplier[5];
new String:rocketStringSpeedMultiplier[5];

//these are working multipliers
static Float:cleaverFloatSpeed = Float:0.25;
static Float:lochFloatSpeed = Float:0.25;
static Float:detonFloatSpeed = Float:0.25;
static Float:huntsFloatSpeed = Float:0.25;
static Float:rocketFloatSpeed = Float:0.25;
*/

new String:announceString[100];

//gamemode handlers
new String:gameMode[100] = "SCOUT_PLAY_ALL_WEAPONS";
new classMode = 1; //0 = all classes, 1 = scouts only, 8 = snipers only
new weaponMode = 0; //0 = all weapons, 1 = bat only, 2 = detonator only, 3 = huntsman only, 4 = rocket launcher only
static int:intEnabled = int:0; //0 = gamemode disabled, 1 = enabled

//sandman cooldown helpers
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
	description = "A laggy projectile based game modifier that promotes baseball and other projectile spam.",
	version = PLUGIN_VERSION,
	url = "http://steamcommunity.com/id/BlazinH"
};

public OnPluginStart()
{
	//Create all these dumb ConVars and hook them
	CreateConVar("baseballhell_version", PLUGIN_VERSION, "Baseball Hell Version.", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	handleEnabled = CreateConVar("baseballhell_enabled", "0", "Enable/Disable Baseball Hell", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 1.0);
	handleSpeed = CreateConVar("baseballhell_delay_multi", "1", "Fire Rate for projectiles. Increase this if the server lags.", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_NOTIFY, true, 1.0, true, 10.0);
	handleGameMode = CreateConVar("baseballhell_mode", "SCOUT_PLAY_ALL_WEAPONS", "The mode of Baseball hell. \n SCOUT_PLAY_ALL_WEAPONS - Scouts only, all weapons, special scout implements. \n SCOUT_PLAY_BAT_ONLY - Same as above, but only the sandman is equipped. \n ALL_PLAY_ALL_WEAPONS - All classes can play, with all weapons. Scouts have no double jump. \n ALL_PLAY_BAT_ONLY - Same as above, but only the sandman is equipped. \n FLAK_CANNON - Scouts armed with the detonator! RIP", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_NOTIFY);
	HookConVarChange(handleGameMode, GameModeChanged);
	HookConVarChange(handleSpeed, cvarSpeed);
	HookConVarChange(handleEnabled, EnableThis);
	
	//inventory hook
	HookEvent( "post_inventory_application", OnPostInventoryApplicationAndPlayerSpawn );
	HookEvent( "player_spawn", OnPostInventoryApplicationAndPlayerSpawn );
	
	//hook for disabling respawn timer
	HookEvent( "teamplay_round_start", OnMapChange );
	
	//hook for sounds
	AddNormalSoundHook(SHook);
	
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
			//set all health to 40 (prevents overheal carryover)
			for(new i = 1; i <= MAXPLAYERS; i++)
			{
				if (IsValidClient(i)) { SetEntData(i, FindDataMapOffs(i, "m_iHealth"), startingHealth, 4, true); }
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

public Action:SHook(clients[64], &numClients, String:sample[PLATFORM_MAX_PATH], &entity, &channel, &Float:volume, &level, &pitch, &flags)
{	//hook pull sounds because they cause pitch errors
	if ( pitch >= 256 ) { pitch = 255; return Plugin_Changed; }
	if ( volume > 1.0 ) { volume = 1.0; return Plugin_Changed; }
	return Plugin_Continue;
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
	if ((buttons & IN_ATTACK2) && (GetSpeshulAmmo(client , TFWeaponSlot_Melee) > 0) && (FloatMul(Float:ballDelay, Float:delayFloatMultiplier) > ballDelay)) 
	{ ResetTimer(int:client); }
	else if ((GetSpeshulAmmo(client, TFWeaponSlot_Melee) < 1) && (FloatMul(Float:ballDelay, Float:delayFloatMultiplier) <= ballDelay)) 
	{ SetSpeshulAmmo(client, TFWeaponSlot_Melee, 1); }
	if (weaponMode == 0 && (GetSpeshulAmmo(client, TFWeaponSlot_Secondary) < 1))
	{ SetSpeshulAmmo(client, TFWeaponSlot_Secondary, 1); }
}

//reset ammo when fired
public Action:timerRegen(Handle:timer, any:data)
{
	if(cooldownArray[int:data]) { cooldownArray[int:data] = false; }
	if(IsValidClient(int:data) && (GetSpeshulAmmo(int:data, TFWeaponSlot_Melee) < 1)) { SetSpeshulAmmo(int:data, TFWeaponSlot_Melee, 1); }
	timerArray[int:data] = INVALID_HANDLE;
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
	if (intEnabled == int:1) { ServerCommand("sm_smj_global_enabled 1"); }
	
	//the scout only modes enable infinitejump
	if (classMode == 1 && (intEnabled == int:1)) { ServerCommand("sm_smj_global_limit 0"); }
	else { ServerCommand("sm_smj_global_limit 1"); }
} 

//create weapons dependent on the situation
public CreateWeapons()
{
	if (weaponMode == 0 || weaponMode == 1)
	{
		if (weaponMode == 0)
		{
			//in order: 100% crit (visual), shatter, proj speed * 2.45, attach particle, reload speed 10%, blast radius 4%
			//clip size 25%, ammo regen 100%, max ammo 200%, switch speed 10%, attack rate ??
			concatString[2] = "408 ; 1 ; 127 ; 2 ; 103 ; 2.45 ; 370 ; 68 ; 97 ; 0.1 ; 100 ; 0.04 ; 3 ; 0.25 ; 112 ; 1 ; 76 ; 2 ; 178 ; 0.1 ; 6 ; ";
			
			//concatenate the fire delay multiplier onto the attributes of the loch-n-load
			workingFloat[2] = FloatMul(delayFloatMultiplier, floatMultiplier[2]) ;
			workingFloat[2] = FloatSub(workingFloat[2], floatMultiplier[2] / Float:2.0 ) ; //compensate for reload animation
			FloatToString(workingFloat[2], stringMultiplier[2], 6);
			StrCat(concatString[2], 200, stringMultiplier[2]);

			TF2Items_CreateWeapon( ids[2], "tf_weapon_grenadelauncher", 308, 0, 9, 10, concatString[2], -1, _, true ); 
			
			concatString[1] = "408 ; 1 ; 370 ; 56 ; 178 ; 0.1 ; 6 ; ";
			
			//concatenate the fire delay multiplier onto the attributes of the cleaver
			workingFloat[1] = FloatMul(delayFloatMultiplier, floatMultiplier[1]) ;
			FloatToString(workingFloat[1], stringMultiplier[1], 6);
			StrCat(concatString[1], 200, stringMultiplier[1]);
			
			TF2Items_CreateWeapon( ids[1], "tf_weapon_cleaver", 812, 1, 9, 10, concatString[1], -1, _, true ); 
		}
		
		//for each class
		for (new int:class = int:0 ; class < int:9 ; class++)
		{
			if ((class != int:0) && classMode == 1)
			{ break; } //only create the scout bat if scouts only mode
			//in order: launch balls, set switch speed to 10%, attach a particle
			concatString[0] = "408 ; 1 ; 38 ; 1 ; 178 ; 0.1 ; 370 ; 43";
			
			if (class != int:0) //if this class isnt a scout
			{
				//concatenate better cap speed
				StrCat(concatString[0], 200, " ; 68 ; 1");
			}
			
			//concatenate the health reduction
			StrCat(concatString[0], 200, " ; 125 ; ");
			StrCat(concatString[0], 200, healthReduc[class]);

			//concatenate an attribute on engineer's bat; bots can only build minisentries, if they can at all
			if (class == int:5)
			{
				StrCat(concatString[0], 200, " ; 124 ; 1");
			}
			//concatenate no double jumps onto a scout's bat if a scout only mode is not on
			else if ((classMode != 1) && (class == int:0))
			{
				StrCat(concatString[0], 200, " ; 49 ; 1"); //no double jumps on all player modes
			}
			TF2Items_CreateWeapon( (ids[0] + class) , "tf_weapon_bat_wood", 44, 2, 9, 10, baseBallString, -1, _, true ); 
		}
	}
	else if (weaponMode == 2)
	{
		//in order: 100% crit (visual), proj speed * 1.5, attach particle, ammo regen 100%, max ammo 200%, switch speed 10%, set detonator weapon mode, attack rate ??
		concatString[3] = "408 ; 1 ; 103 ; 1.5 ; 370 ; 1 ; 112 ; 1 ; 76 ; 2 ; 178 ; 0.1 ; 144 ; 1.0 ; 6 ; ";
			
		//concatenate the fire delay multiplier onto the attributes of the detonator
		workingFloat[3] = FloatMul(delayFloatMultiplier, floatMultiplier[3]) ;
		FloatToString(workingFloat[3], stringMultiplier[3], 6);
		StrCat(concatString[3], 200, stringMultiplier[3]);
			
		//concatenate the health reduction
		StrCat(concatString[3], 200, " ; 125 ; ");
		StrCat(concatString[3], 200, healthReduc[0]);
			
		TF2Items_CreateWeapon( ids[3], "tf_weapon_flaregun", 351, 1, 9, 10, concatString[3], -1, _, true );
	}
	else if (weaponMode == 3)
	{
		//in order: 100% crit (visual), attach particle, ammo regen 100%, max ammo 200%, switch speed 10%, attack rate ??
		concatString[4] = "408 ; 1 ; 370 ; 1 ; 112 ; 1 ; 76 ; 2 ; 178 ; 0.1 ; 6 ; ";
			
		//concatenate the fire delay multiplier onto the attributes of the huntsman
		workingFloat[4] = FloatMul(delayFloatMultiplier, floatMultiplier[4]) ;
		FloatToString(workingFloat[4], stringMultiplier[4], 6);
		StrCat(concatString[4], 200, stringMultiplier[4]);
			
		//concatenate the health reduction
		StrCat(concatString[4], 200, " ; 125 ; ");
		StrCat(concatString[4], 200, healthReduc[7]);
		
		//if (class != int:0) //if this class isnt a scout
		//{
			//concatenate better cap speed
		StrCat(concatString[4], 200, " ; 68 ; 1");
		//}
			
		TF2Items_CreateWeapon( ids[4], "tf_weapon_compound_bow", 56, 0, 9, 10, concatString[4], -1, _, true ); 
	}
	else if (weaponMode == 4) // valve rocket launcher
	{
		//in order: 100% crit (visual), proj speed * 2.72, attach particle, reload speed 10%, blast radius 4%
		//clip size 25%, ammo regen 100%, max ammo 200%, switch speed 10%, attack rate ??
		concatString[5] = "408 ; 1 ; 103 ; 2.72 ; 370 ; 68 ; 97 ; 0.1 ; 100 ; 0.04 ; 3 ; 0.25 ; 112 ; 1 ; 76 ; 2 ; 178 ; 0.1 ; 6 ; ";
			
		//concatenate the fire delay multiplier onto the attributes of the loch-n-load
		workingFloat[5] = FloatMul(delayFloatMultiplier, floatMultiplier[5]) ;
		workingFloat[5] = FloatSub(workingFloat[5], 0.115 ) ; //compensate for reload animation
		FloatToString(workingFloat[5], stringMultiplier[5], 6);
		StrCat(concatString[5], 200, stringMultiplier[5]);

		TF2Items_CreateWeapon( ids[5], "tf_weapon_rocketlauncher", 18, 0, 9, 10, concatString[5], -1, _, true ); 
	}
}

//sets the global fire rate multiplier, then announces
public cvarSpeed(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	delayFloatMultiplier = Float:StringToFloat(newVal);

	if (intEnabled == int:1)
	{
		announceString = "Fire rate set to ";
		new String:damn[6];
		if (weaponMode != 3)
		{
			FloatToString(FloatMul(Float:ballDelay, Float:delayFloatMultiplier), damn, 6);
			StrCat(announceString, 100, damn);
			StrCat(announceString, 100, " seconds");
		}
		else
		{
			FloatToString(ballDelay * delayFloatMultiplier * 2 / 3 , damn, 6);
			StrCat(announceString, 100, damn);
			StrCat(announceString, 100, " seconds at no charge, ");
			FloatToString(FloatMul(Float:ballDelay, Float:delayFloatMultiplier), damn, 6);
			StrCat(announceString, 100, damn);
			StrCat(announceString, 100, " seconds at full charge");
		}
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
	announceString = "Baseball Hell mode set ";
	new String:daMode[60];

	if (StrEqual("SCOUT_PLAY_ALL_WEAPONS", gameMode, false)){ daMode = "to Scouts only, with all weapons"; classMode = 1; weaponMode = 0; }
	else if (StrEqual("SCOUT_PLAY_BAT_ONLY", gameMode, false)){ daMode = "to Scouts with bat only"; classMode = 1; weaponMode = 1; }
	else if (StrEqual("ALL_PLAY_ALL_WEAPONS", gameMode, false)){ daMode = "to All classes with all weapons"; classMode = 0; weaponMode = 0; }
	else if (StrEqual("ALL_PLAY_BAT_ONLY", gameMode, false)){ daMode = "to All classes, with bat only"; classMode = 0; weaponMode = 1; }
	else if (StrEqual("FLAK_CANNON", gameMode, false)){ daMode = "to Scouts with detonators only"; classMode = 1; weaponMode = 2; }
	else if (StrEqual("HUNTSMAN", gameMode, false)){ daMode = "to Snipers with Huntsman only"; classMode = 8; weaponMode = 3; }
	else if (StrEqual("ROCKETMAN", gameMode, false)){ daMode = "to Scouts with Valve Launchers only"; classMode = 1; weaponMode = 4; }
	else { daMode = "invalidly, setting to all scouts only, with all weapons"; classMode = 1; weaponMode = 0;}
	StrCat(announceString, 100, daMode);
	AnnounceAll();
	ScoutCheck();
}

public ScoutCheck()
{
	if (intEnabled == int:1)
	{
		//scout only
		if (classMode == 1)
		{
			for(new i = 1; i <= MAXPLAYERS; i++)
			{ if (IsValidClient(i)) { TF2_SetPlayerClass(i, TFClass_Scout, false, true); } }
		}
		else if (classMode == 8)
		{
			for(new i = 1; i <= MAXPLAYERS; i++)
			{ if (IsValidClient(i)) { TF2_SetPlayerClass(i, TFClass_Sniper, false, true); } }
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
	//all weapons only
	if (weaponMode == 0)
	{
		TF2Items_GiveWeapon( client, ids[1] );
		TF2Items_GiveWeapon( client, ids[2] );
	}
	
	if (weaponMode == 2 && classMode == 1)
	{
		TF2Items_GiveWeapon( client, ids[3] ); //scout deton only
	}	
	else if (weaponMode == 3 && classMode == 8)
	{
		TF2Items_GiveWeapon( client, ids[4] ); //sniper huntsman only
	}
	else if (weaponMode == 4 && classMode == 1)
	{
		TF2Items_GiveWeapon( client, ids[5] ); //sniper huntsman only
	}
	else
	{
		//each sandman has a different health decrease assigned to it, for different classes
		switch(TF2_GetPlayerClass(client))
		{
			case TFClass_Scout: TF2Items_GiveWeapon( client, ids[0] );
			case TFClass_Soldier: TF2Items_GiveWeapon( client, ids[0] + int:1 );
			case TFClass_Pyro: TF2Items_GiveWeapon( client, ids[0] + int:2 );
			case TFClass_DemoMan: TF2Items_GiveWeapon( client, ids[0] + int:3 );
			case TFClass_Heavy: TF2Items_GiveWeapon( client, ids[0] + int:4 );
			case TFClass_Engineer: TF2Items_GiveWeapon( client, ids[0] + int:5 );
			case TFClass_Medic: TF2Items_GiveWeapon( client, ids[0] + int:6 );
			case TFClass_Sniper: TF2Items_GiveWeapon( client, ids[0] + int:7 );
			case TFClass_Spy: TF2Items_GiveWeapon( client, ids[0] + int:8 );
		}
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
		if (classMode == 1) { TF2_SetPlayerClass(iClient, TFClass_Scout, false, true); }
		else if (classMode == 8) { TF2_SetPlayerClass(iClient, TFClass_Sniper, false, true); }
		//make everyone fast like scout (this is inefficient but least console spam)
		if (classMode != 1) { ServerCommand("sm_setspeed @all 400"); }
		
		RemoveAllWeapons(iClient);
		GiveArray(iClient);

		//disable sentry targeting on this person
		new flags = GetEntityFlags(iClient)|FL_NOTARGET;
		SetEntityFlags(iClient, flags);
	}
}

//crits should always be enabled while the game modifier is active
public Action:TF2_CalcIsAttackCritical(client, weapon, String:weaponname[], &bool:result)
{
	if (intEnabled == int:1) { result = true; return Plugin_Handled; }
	else { return Plugin_Continue; }
}

//Disable building if the plugin is enabled
public Action:CommandListener_Build(client, const String:command[], argc)
{
	if (intEnabled == int:1) { return Plugin_Handled; }
	else { return Plugin_Continue; }
}
