/**************************************************************
--------------------------------------------------------------
 NEOTOKYOｰ Deathmatch

 Plugin licensed under the GPLv3
 
 Coded by Agiel.
--------------------------------------------------------------

Changelog

	0.0.1
		* Extended pre-game timer for rudimentary deathmatch
	0.1.0
		* Added cvars, spawn protection and hooked up team score
	0.1.1
		* Added cvar hook for enable,
		Here is what to do to activate DM after a standard CTG map start:
		starts off by default (gametype 1 CTG)
		change gametype from 2 to 0 (optional)
		stop DM gametype 0 to 1 (how come?) and gamestate 0 to 1
		start DM gametype 1 to 0 and gamestate 1 to 1 (DM works!)
		stop DM again: gametype 0 to 1 and gamestate 1 to 1 (back to CTG!) -glub
	0.1.2
		*Added random player spawns -glub
	0.1.3
		*Added random ammopacks spawns -glub
	0.1.4
		*Added grenade packs spawns -glub
	0.1.5
		*Added ladder spawns -glub
	0.1.6
		*Added dogtags / Kill Confirmed game mode -glub
	0.1.7
		*Added votes -glub
		
		TODO:	fix map changing after votetdm (probably related to mp_timelimit)
		TODO:	fix grenades not always picked up
		TODO:	fix weapon crates not respawning after some occurences
		TODO:	clear unused detapacks after a while with timer (check for no ownership)
		TODO:	respawn props on round restart (in case someone does neo_restart_this)
		TODO:	rendermode for spawn protected players (transparency?)
		TODO:	parse an autostart file containing a selection of maps (fopen() + StrContains())
				instead of hardcoding them (must parse it first).
		TODO:	physics props for dogtags, facing top on z axis always (in progress) 
		
**************************************************************/
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <adminmenu>
//#include <smlib>
#define MAXENTITIES 2048
#define PLUGIN_VERSION	"0.1.7"
#include "nt_votes.sp"

#define DEBUG 0 //1 or 2


public Plugin:myinfo =
{
    name = "NEOTOKYO Team Deathmatch",
    author = "glub, based on Agiel's",
    description = "Neotokyo team deathmatch and other sub-modes",
    version = PLUGIN_VERSION,
    url = "https://github.com/glubsy/nt-deathmatch"
};
//new Handle:convar_nt_tdm_version = INVALID_HANDLE;
new Handle:convar_nt_tdm_enabled = INVALID_HANDLE;
ConVar convar_nt_tdm_kf_enabled; 
new Handle:convar_nt_tdm_timelimit = INVALID_HANDLE;
new Handle:convar_nt_tdm_spawnprotect = INVALID_HANDLE;
new Handle:convar_nt_tdm_randomplayerspawns = INVALID_HANDLE;
new Handle:convar_nt_tdm_ammo_respawn_time = INVALID_HANDLE;
new Handle:convar_nt_tdm_grenade_respawn_time = INVALID_HANDLE;
new Handle:convar_nt_dogtag_remove_timer = INVALID_HANDLE;
ConVar convar_nt_tdm_kf_hardcore_enabled;

new bool:g_DMStarted = false;
new bool:g_KF_enabled = false;
new bool:g_KF_Hardcore_enabled = false;

new Float:g_AmmoRespawnTime;
new Float:g_GrenadeRespawnTime;
new Float:g_DogTagRemoveTime;

new clientProtected[MAXPLAYERS+1];
new clientHP[MAXPLAYERS+1];

new Handle:DogTagDropTimer[MAXENTITIES+1] = INVALID_HANDLE;

new Float:coordinates_array[100][3];  //initializing big array of floats for coordinates
new Float:angles_array[100][3];	
new bool:g_kvfilefound = false;

int lines = 200;
int randomint;

int randomint_allowing_array[100];  //if set to 1, the number corresponding to the cell is forbidden for use, it set to 0 it's allowed.
int randomint_prev = -1;

int randomint_history[32];
int history_cursor;
int tobereset_int_cursor = 0;

new bool:g_RandomPlayerSpawns = false;
new bool:g_PlayerCoordsKeyPresent = false;

int ammolines = 200;
new bool:g_AmmoPackKeyPresent = false;
new bool:g_AmmoPackCoordsPresent = false;
new Float:ammocoords_array[60][3];  //60 is hard coded 30 max possible ammo pack locations, might have to change that
new Float:ammoangles_array[60][3];
new ammo_coords_cursor;
new const String:g_AmmoPackModel[] = "models/items/boxsrounds.mdl";
new const String:g_AmmoPickupSound[] = "items/ammo_pickup.wav";


new gOffsetMyWeapons;
//new gOffsetAmmo;

int grenadelines = 200;
new bool:g_GrenadePacksKeyPresent = false;
new bool:g_GrenadePacksCoordsPresent = false;
new Float:grenadecoords_array[60][3];
new Float:grenadeangles_array[60][3];
new grenade_coords_cursor;
new const String:g_GrenadePackModel[] = "models/items/boxmrounds.mdl";
new const String:g_GrenadePickupSound[] = "common/wpn_moveselect.wav";

new grenadeprop[30];


int ladderlines = 200;
new bool:g_LaddersKeyPresent = false;
new bool:g_LaddersCoordsPresent = false;
new Float:laddercoords_array[60][3];
new Float:ladderangles_array[60][3];
new const String:g_LadderModel[] = "models/ladder/ladder4.mdl";



//new bool:bUp = true;
//new bool:b_movestart = false;

new const String:g_DogTagModelNSF[] = "models/logo/nsf_logo.mdl";
new const String:g_DogTagModelJINRAI[] = "models/logo/jinrai_logo.mdl";
new const String:g_DogTagModelNSFphysics[] = "models/logo/nsf_logo2.mdl";
new const String:g_DogTagModelJINRAIphysics[] = "models/logo/jinrai_logo2.mdl";

new const String:g_DogTagPickupSound[] = "common/warning.wav";
new const String:g_DogTagPickupSoundDenied[] = "buttons/combine_button5.wav";

/*
new const String:gSpawnSounds[][] =
{
	"saitama_corp_i.mp3"
};
*/

new const String:g_ConflictingPlugins[][] = 
{
	"nt_ghostcap.smx",
	"nt_assist.smx",
	"nt_competitive.smx",
	"nt_autosquad.smx",
	"nt_damage-noassist.smx",
	"nt_mirrordamage.smx",
	"nt_playercount.smx",
	"nt_unlimitedsquads.smx"
	//"nt_tkpenaltyfix.smx" to remove -1 on tk, on top of ours
};



public OnPluginStart()
{
	//convar_nt_tdm_version = CreateConVar("nt_tdm_version", PLUGIN_VERSION, "NEOTOKYO Team Deathmatch.", FCVAR_PLUGIN | FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);
	convar_nt_tdm_enabled = CreateConVar("nt_tdm_enabled", "0", "Enables or Disables team deathmatch.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	convar_nt_tdm_timelimit = CreateConVar("nt_tdm_timelimit", "20", "Sets team deathmatch timelimit.", FCVAR_PLUGIN, true, 0.0, true, 60.0);
	convar_nt_tdm_spawnprotect = CreateConVar("nt_tdm_spawnprotect", "5.0", "Length of time to protect spawned players", FCVAR_PLUGIN, true, 0.0, true, 30.0);
	convar_nt_tdm_randomplayerspawns = CreateConVar("nt_tdm_randomplayerspawns", "1", "Activates or deactivates random spawns from keyvalue file", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	convar_nt_tdm_kf_enabled = CreateConVar("nt_tdm_kf_enabled", "0", "Enables or Disables Kill Confirmed.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	convar_nt_tdm_kf_hardcore_enabled = CreateConVar("nt_tdm_kf_hardcore_enabled", "0", "Enables or Disables gaining points ONLY by pickup up dogtags.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	convar_nt_tdm_ammo_respawn_time = CreateConVar("nt_tdm_ammo_respawn_time", "45.0", "Time in seconds before an ammo pack will respawn", FCVAR_PLUGIN);
	convar_nt_tdm_grenade_respawn_time = CreateConVar("nt_tdm_grenade_respawn_time", "60.0", "Time in seconds before a grenade pack will respawn", FCVAR_PLUGIN);
	convar_nt_dogtag_remove_timer = CreateConVar("nt_dogtag_remove_time", "30.0", "Time in seconds before a dogtag disappears", FCVAR_PLUGIN);

	//vote initialization 
	InitVoteCvars();
	
	AutoExecConfig(true);
	
	RegAdminCmd("sm_tdm_enable", Command_TDM_Enable, ADMFLAG_KICK, "Enables or disables team deathmatch game mode.");
	RegAdminCmd("sm_kf_enable", Command_KF_Enable, ADMFLAG_KICK, "Enables or disables Kill Confirmed game mode.");
	RegAdminCmd("sm_randomplayerspawns", Command_Randomplayerspawns, ADMFLAG_KICK, "Enables or disables random player spawns.");
	RegAdminCmd("sm_tdm_timelimit", Command_TDM_Timelimit, ADMFLAG_KICK, "Sets team deathmatch timelimit.");
	RegAdminCmd("sm_kf_hardcore_enable", Command_KF_Hardcore_Enable, ADMFLAG_KICK, "Enables or disables gaining points ONLY by pickup up dogtags.");
	
	
	#if DEBUG > 1
	RegAdminCmd("sm_forcestartdm", CommandRestartDeatchmatch, ADMFLAG_SLAY, "forces deathmatch-debug command for testing");
	RegAdminCmd("sm_forcestopdm", CommandStopDeatchmatch, ADMFLAG_SLAY, "stops deathmatch- debug command for testing");
	RegAdminCmd("change_gamestate_gr", ChangeGameStateGR, ADMFLAG_SLAY, "change gamestate through the GameRules: change_gamestate_gr <0/1/2>");
	RegAdminCmd("change_gamestate_proxy", ChangeGameStateProxy, ADMFLAG_SLAY, "change gamestate through proxy: change_gamestate_proxy <0/1/2>");
	RegAdminCmd("check_gamestate_gr", CheckGameStateGR, ADMFLAG_SLAY, "check gamestate through Gamerules");
	RegAdminCmd("check_gamestate_proxy", CheckGameStateProxy, ADMFLAG_SLAY, "check gamestate through proxy");	
	RegAdminCmd("check_gametype", CheckGameType, ADMFLAG_SLAY, "check gametype");
	RegAdminCmd("change_gametype", ChangeGameType, ADMFLAG_SLAY, "change gametype: change_gametype <1/2>");
	RegAdminCmd("change_gametype_gr", ChangeGameTypeGR, ADMFLAG_SLAY, "change gametype through GameRules: change_gametype_gr <1/2>");
	#endif
	
	HookConVarChange(convar_nt_tdm_timelimit, OnTimeLimitChanged);
	HookConVarChange(convar_nt_tdm_enabled, OnConfigsExecutedHook);  //added glub
	HookConVarChange(convar_nt_tdm_randomplayerspawns, OnChangePlayerRandomSpawnsCvar);
	HookConVarChange(convar_nt_tdm_ammo_respawn_time, OnChangeAmmoRespawnTimeCvar);
	HookConVarChange(convar_nt_tdm_grenade_respawn_time, OnChangeGrenadeRespawnTimeCvar);
	HookConVarChange(convar_nt_tdm_kf_enabled, OnChangeKFEnabledCvar);
	HookConVarChange(convar_nt_tdm_kf_hardcore_enabled, OnChangeKF_Hardcore_EnabledCvar);
	HookConVarChange(convar_nt_dogtag_remove_timer, OnChangeDogTagTimer);
	
	
	
	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("player_hurt", OnPlayerHurt);
	HookEvent("player_death", OnPlayerDeath);
	
	
	// Get offsets
	gOffsetMyWeapons = FindSendPropInfo("CBasePlayer", "m_hMyWeapons");
	//gOffsetAmmo = FindSendPropInfo("CBasePlayer", "m_iAmmo");
	
/*	for(new snd = 0; snd < sizeof(gSpawnSounds); snd++)
	PrecacheSound(gSpawnSounds[snd]);    //precaching sound effect for spawn*/

	// init random number generator
	SetRandomSeed(RoundToFloor(GetEngineTime()));

	/*
	//Precaching models
	PrecacheModel(g_LadderModel, true);
	PrecacheModel(g_GrenadePackModel, true);
	PrecacheModel(g_AmmoPackModel, true);
	PrecacheModel(g_DogTagModelNSF, true);
	PrecacheModel(g_DogTagModelJINRAI, true);
	//Precaching sounds
	PrecacheSound(g_AmmoPickupSound, true);
	PrecacheSound(g_GrenadePickupSound, true);
	PrecacheSound(g_DogTagPickupSound, true);
	PrecacheSound(g_DogTagPickupSoundDenied, true);
	
	//Adding custom models to forced download
	AddFileToDownloadsTable("models/ladder/ladder4.mdl");
	AddFileToDownloadsTable("models/ladder/ladder4.dx80.vtx");
	AddFileToDownloadsTable("models/ladder/ladder4.dx90.vtx");
	AddFileToDownloadsTable("models/ladder/ladder4.phy");
	AddFileToDownloadsTable("models/ladder/ladder4.sw.vtx");
	AddFileToDownloadsTable("models/ladder/ladder4.vvd");
	AddFileToDownloadsTable("models/ladder/ladder4.xbox.vtx");
	AddFileToDownloadsTable("materials/models/ladder/ladder4.vmt");
	AddFileToDownloadsTable("materials/models/ladder/ladder4.vtf");
	AddFileToDownloadsTable("models/logo/jinrai_logo.mdl");
	AddFileToDownloadsTable("models/logo/jinrai_logo.dx80.vtx");
	AddFileToDownloadsTable("models/logo/jinrai_logo.dx90.vtx");
	AddFileToDownloadsTable("models/logo/jinrai_logo.phy");
	AddFileToDownloadsTable("models/logo/jinrai_logo.sw.vtx");
	AddFileToDownloadsTable("models/logo/jinrai_logo.vvd");
	AddFileToDownloadsTable("models/logo/jinrai_logo.xbox.vtx");
	AddFileToDownloadsTable("models/logo/nsf_logo.mdl");
	AddFileToDownloadsTable("models/logo/nsf_logo.dx80.vtx");
	AddFileToDownloadsTable("models/logo/nsf_logo.dx90.vtx");
	AddFileToDownloadsTable("models/logo/nsf_logo.phy");
	AddFileToDownloadsTable("models/logo/nsf_logo.sw.vtx");
	AddFileToDownloadsTable("models/logo/nsf_logo.vvd");
	AddFileToDownloadsTable("models/logo/nsf_logo.xbox.vtx");
	AddFileToDownloadsTable("materials/models/logo/jinrai_logo.vmt");
	AddFileToDownloadsTable("materials/models/logo/nsf_logo.vmt");*/		//FIXME: remove this and test model precaching again

}


public OnConfigsExecuted() 
{
	g_DMStarted = false;
	if (GetConVarBool(convar_nt_tdm_enabled))
	{
		StartDeathmatch();
		g_DMStarted = true;
		PrintToChatAll("Team DeathMatch enabled!");
	}
	
	if (GetConVarBool(convar_nt_tdm_randomplayerspawns))
	{
		g_RandomPlayerSpawns = true;
		PrintToChatAll("Random player spawns enabled!");
	}
	if (!GetConVarBool(convar_nt_tdm_randomplayerspawns))
	{
		g_RandomPlayerSpawns = false;
		PrintToChatAll("Random player spawns disabled!");
	}
	g_AmmoRespawnTime = GetConVarFloat(convar_nt_tdm_ammo_respawn_time);
	g_GrenadeRespawnTime = GetConVarFloat(convar_nt_tdm_grenade_respawn_time);
	g_DogTagRemoveTime = GetConVarFloat(convar_nt_dogtag_remove_timer);
	
	CheckConvarsOnMapLoaded();
	

	//Precaching models
	PrecacheModel(g_LadderModel, true);
	PrecacheModel(g_GrenadePackModel, true);
	PrecacheModel(g_AmmoPackModel, true);
	PrecacheModel(g_DogTagModelNSF, true);
	PrecacheModel(g_DogTagModelJINRAI, true);
	//Precaching sounds
	PrecacheSound(g_AmmoPickupSound, true);
	PrecacheSound(g_GrenadePickupSound, true);
	PrecacheSound(g_DogTagPickupSound, true);
	PrecacheSound(g_DogTagPickupSoundDenied, true);
	
	//Adding custom models to forced download
	AddFileToDownloadsTable("models/ladder/ladder4.mdl");
	AddFileToDownloadsTable("models/ladder/ladder4.dx80.vtx");
	AddFileToDownloadsTable("models/ladder/ladder4.dx90.vtx");
	AddFileToDownloadsTable("models/ladder/ladder4.phy");
	AddFileToDownloadsTable("models/ladder/ladder4.sw.vtx");
	AddFileToDownloadsTable("models/ladder/ladder4.vvd");
	AddFileToDownloadsTable("models/ladder/ladder4.xbox.vtx");
	AddFileToDownloadsTable("materials/models/ladder/ladder4.vmt");
	AddFileToDownloadsTable("materials/models/ladder/ladder4.vtf");
	AddFileToDownloadsTable("models/logo/jinrai_logo.mdl");
	AddFileToDownloadsTable("models/logo/jinrai_logo.dx80.vtx");
	AddFileToDownloadsTable("models/logo/jinrai_logo.dx90.vtx");
	AddFileToDownloadsTable("models/logo/jinrai_logo.phy");
	AddFileToDownloadsTable("models/logo/jinrai_logo.sw.vtx");
	AddFileToDownloadsTable("models/logo/jinrai_logo.vvd");
	AddFileToDownloadsTable("models/logo/jinrai_logo.xbox.vtx");
	AddFileToDownloadsTable("models/logo/nsf_logo.mdl");
	AddFileToDownloadsTable("models/logo/nsf_logo.dx80.vtx");
	AddFileToDownloadsTable("models/logo/nsf_logo.dx90.vtx");
	AddFileToDownloadsTable("models/logo/nsf_logo.phy");
	AddFileToDownloadsTable("models/logo/nsf_logo.sw.vtx");
	AddFileToDownloadsTable("models/logo/nsf_logo.vvd");
	AddFileToDownloadsTable("models/logo/nsf_logo.xbox.vtx");
	AddFileToDownloadsTable("materials/models/logo/jinrai_logo.vmt");
	AddFileToDownloadsTable("materials/models/logo/nsf_logo.vmt");

}

/*
public OnAutoConfigsBuffered() {
	decl String:currentMap[64];
	GetCurrentMap(currentMap, 64);

	if(StrEqual(currentMap, "nt_terminal_ctg") || StrEqual(currentMap, "nt_sentinel_ctg") || StrEqual(currentMap, "nt_bullet_tdm") || StrEqual(currentMap, "nt_zaibatsu_ctg") && GetConVarInt(convar_nt_tdm_enabled) == 0)
		SetConVarInt(convar_nt_tdm_enabled, 1); // we enable the convar for TDM automatically on these maps
	else
		SetConVarInt(convar_nt_tdm_enabled, 0);
}*/

public CheckConvarsOnMapLoaded()
{
	decl String:currentMap[64];
	GetCurrentMap(currentMap, 64);

	if(StrEqual(currentMap, "nt_terminal_ctg") || StrEqual(currentMap, "nt_sentinel_ctg") || StrEqual(currentMap, "nt_sentinel_tdm") || StrEqual(currentMap, "nt_bullet_tdm") && GetConVarInt(convar_nt_tdm_enabled) == 0)
		SetConVarInt(convar_nt_tdm_enabled, 1); // we enable the convar for TDM automatically on these maps
	else
		SetConVarInt(convar_nt_tdm_enabled, 0);
}

public OnConfigsExecutedHook(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	if (!GetConVarBool(convar_nt_tdm_enabled))   // Cvar is set to 0, we are stopping
	{
		StopDeathMatch();
		g_DMStarted = false;
		PrintToChatAll("========================================");
		PrintToChatAll("                  Team DeathMatch ended!");
		PrintToChatAll("========================================");
		PrintToServer("Team DeathMatch stopped!");
		ServerCommand("neo_restart_this 1");

		ReloadConflictingPlugins();
		ServerCommand("nt_healthkitdrop 0");
		//ServerCommand("sm_cv tpr_enabled 0"); //disabling projectile replacements for fun here (needs tpr_replacer.smx and cvar squelcher)
		SetConVarInt(convar_nt_tdm_kf_enabled, 0); 
		SetConVarInt(convar_nt_tdm_kf_hardcore_enabled, 0); 

	}
	if (GetConVarBool(convar_nt_tdm_enabled))   // Cvar is set to 1, we are starting
	{
		StopDeathMatch();
		
		CreateTimer(5.0, StartDeatchmatch);   // needs a timer to properly start. Very weird, I know. -glub
		
		//g_DMStarted = true;
		PrintToChatAll("========================================");
		PrintToChatAll("                Team DeathMatch started!");
		PrintToChatAll("========================================");
		PrintToServer("Team DeathMatch started!");
		//GameRules_SetPropFloat("m_fRoundTimeLeft", 10.0);    
		//GameRules_SetProp("m_iGameState", 1);    // if gamestate change from 0 to 1 and neo_restart_this 1, CTG back to normal, no respawn
		//ServerCommand("neo_restart_this 1");
		
		CreateTimer(1.5, UnloadConflictingPlugins);
		ServerCommand("nt_healthkitdrop 1");
		//ServerCommand("sm_cv tpr_enabled 1");  //enabling projectile replacements for fun here (needs tpr_replacer.smx and cvar squelcher)
		
		SetConVarInt(convar_nt_tdm_kf_enabled, 1); //we start KF enabled by default with TDM for now. FIXME: remove later.
		//SetConVarInt(convar_nt_tdm_kf_hardcore_enabled, 1); //if we want hardcore by default
	}
} 


public Action:UnloadConflictingPlugins(Handle:timer)
{
	for(new i; i < sizeof(g_ConflictingPlugins); i++)
	{
		if(FindPluginByFile(g_ConflictingPlugins[i]) != INVALID_HANDLE)
		{
			ServerCommand("sm plugins unload %s", g_ConflictingPlugins[i]);
		}
	}

}

void ReloadConflictingPlugins()
{
	for(new i; i < sizeof(g_ConflictingPlugins); i++)
	{
		if(FindPluginByFile(g_ConflictingPlugins[i]) != INVALID_HANDLE)
		{
			ServerCommand("sm plugins load %s", g_ConflictingPlugins[i]);
		}
	}
}


public OnChangePlayerRandomSpawnsCvar(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	if (GetConVarBool(convar_nt_tdm_randomplayerspawns))
	{
		g_RandomPlayerSpawns = true;
		PrintToChatAll("[TDM] Random player spawns enabled!");
	}
	if (!GetConVarBool(convar_nt_tdm_randomplayerspawns))
	{
		g_RandomPlayerSpawns = false;
		PrintToChatAll("[TDM] Random player spawns disabled!");
	}
}

public OnChangeAmmoRespawnTimeCvar(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	g_AmmoRespawnTime = GetConVarFloat(convar_nt_tdm_ammo_respawn_time);
}


public OnChangeGrenadeRespawnTimeCvar(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	g_GrenadeRespawnTime = GetConVarFloat(convar_nt_tdm_grenade_respawn_time);
}

public OnChangeDogTagTimer(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	g_DogTagRemoveTime = GetConVarFloat(convar_nt_dogtag_remove_timer);
}

public OnChangeKFEnabledCvar(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	if (GetConVarBool(convar_nt_tdm_kf_enabled))
	{
		g_KF_enabled = true;
		PrintToChatAll("========================================");
		PrintToChatAll("       Kill Confirmed mode is now enabled!");
		PrintToChatAll("========================================");
	}
	if (!GetConVarBool(convar_nt_tdm_kf_enabled))
	{
		g_KF_enabled = false;
		PrintToChatAll("========================================");
		PrintToChatAll("       Kill Confirmed mode is now disabled.");
		PrintToChatAll("========================================");
	}
}

public OnChangeKF_Hardcore_EnabledCvar(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	if (GetConVarBool(convar_nt_tdm_kf_hardcore_enabled))
	{
		g_KF_Hardcore_enabled = true;
		PrintToChatAll("========================================");
		PrintToChatAll("       Kill Confirmed HARDCORE mode is now enabled!");
		PrintToChatAll("========================================");
	}
	if (!GetConVarBool(convar_nt_tdm_kf_hardcore_enabled))
	{
		g_KF_Hardcore_enabled = false;
		PrintToChatAll("========================================");
		PrintToChatAll("       Kill Confirmed HARDCORE mode is now disabled.");
		PrintToChatAll("========================================");
	}
}



public Action:Command_TDM_Enable(client, args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_tdm_enable <1|0>");
		ReplyToCommand(client, "[SM] sm_tdm_enable is currently %i", GetConVarInt(convar_nt_tdm_enabled));
		return Plugin_Handled;
	}
	else{	
		decl String:enabled[PLATFORM_MAX_PATH];
		GetCmdArg(1, enabled, sizeof(enabled));
		if(StrEqual(enabled, "1"))
		{
			SetConVarInt(convar_nt_tdm_enabled, 1);
			ReplyToCommand(client, "[SM] TDM is now %i", GetConVarInt(convar_nt_tdm_enabled));
		}
		else
		{
			SetConVarInt(convar_nt_tdm_enabled, 0);
			ReplyToCommand(client, "[SM] TDM is now %i", GetConVarInt(convar_nt_tdm_enabled));
		}
	}
	return Plugin_Handled;
}

public Action:Command_KF_Enable(client, args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_kf_enable <1|0>");
		ReplyToCommand(client, "[SM] sm_kf_enable is currently %i", GetConVarInt(convar_nt_tdm_kf_enabled));
		return Plugin_Handled;
	}
	else{	
		decl String:enabled[PLATFORM_MAX_PATH];
		GetCmdArg(1, enabled, sizeof(enabled));
		if(StrEqual(enabled, "1"))
		{
			SetConVarInt(convar_nt_tdm_kf_enabled, 1);
			//ReplyToCommand(client, "[SM] Kill Confirmed is now %i", GetConVarInt(convar_nt_tdm_kf_enabled));
		}
		else
		{
			SetConVarInt(convar_nt_tdm_kf_enabled, 0);
			//ReplyToCommand(client, "[SM] Kill Confirmed is now %i", GetConVarInt(convar_nt_tdm_kf_enabled));
		}
	}
	return Plugin_Handled;
}

public Action:Command_KF_Hardcore_Enable(client, args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_kf_hardcore_enable <1|0>");
		ReplyToCommand(client, "[SM] sm_kf_hardcore_enable is currently %i", GetConVarInt(convar_nt_tdm_kf_hardcore_enabled));
		return Plugin_Handled;
	}
	else{	
		decl String:enabled[PLATFORM_MAX_PATH];
		GetCmdArg(1, enabled, sizeof(enabled));
		if(StrEqual(enabled, "1"))
		{
			SetConVarInt(convar_nt_tdm_kf_hardcore_enabled, 1);
			//ReplyToCommand(client, "[SM] Kill Confirmed is now %i", GetConVarInt(convar_nt_tdm_kf_hardcore_enabled));
		}
		else
		{
			SetConVarInt(convar_nt_tdm_kf_hardcore_enabled, 0);
			//ReplyToCommand(client, "[SM] Kill Confirmed is now %i", GetConVarInt(convar_nt_tdm_kf_hardcore_enabled));
		}
	}
	return Plugin_Handled;
}



public Action:Command_Randomplayerspawns(client, args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_randomplayerspawns <1|0>");
		ReplyToCommand(client, "[SM] randomplayerspawns is %i", GetConVarInt(convar_nt_tdm_randomplayerspawns));
		return Plugin_Handled;
	}
	else{
		decl String:enabled[PLATFORM_MAX_PATH];
		GetCmdArg(1, enabled, sizeof(enabled));
		if(StrEqual(enabled, "1"))
		{
			SetConVarInt(convar_nt_tdm_randomplayerspawns, 1);
			ReplyToCommand(client, "[SM] randomplayerspawns is now %i", GetConVarInt(convar_nt_tdm_randomplayerspawns));
		}
		else
		{
			SetConVarInt(convar_nt_tdm_randomplayerspawns, 0);
			ReplyToCommand(client, "[SM] randomplayerspawns is now %i", GetConVarInt(convar_nt_tdm_randomplayerspawns));
		}
	}
	return Plugin_Handled;
}

public Action:Command_TDM_Timelimit(client, args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_tdm_timelimit <x.x>");
		ReplyToCommand(client, "[SM] Current timelimit is set to %f", GetConVarFloat(convar_nt_tdm_timelimit));
		return Plugin_Handled;
	}
	decl String:time[PLATFORM_MAX_PATH];
	GetCmdArg(1, time, sizeof(time));
	SetConVarFloat(convar_nt_tdm_timelimit, StringToFloat(time));
	ReplyToCommand(client, "[SM] Current timelimit is set to %f", GetConVarFloat(convar_nt_tdm_timelimit));
	return Plugin_Handled;
} 



public Action:StartDeatchmatch(Handle:timer)
{
	StartDeathmatch();
}


/*======================================

		Start of debugging commands
		
========================================*/
#if DEBUG > 1
public Action:CommandRestartDeatchmatch(client, args)
{
	StartDeathmatch();
	return Plugin_Handled;
}

public Action:CommandStopDeatchmatch(client, args)
{
	StopDeathMatch();
	return Plugin_Handled;
}

public Action:ChangeGameStateGR(client, args)
{ 
	new String:arg1[130];
	GetCmdArg(1, arg1, sizeof(arg1));
	new state = StringToInt(arg1);
	
	new statevalue = GameRules_GetProp("m_iGameState");
	PrintToServer("Before in GR: m_iGameState %i", statevalue);	
	
	GameRules_SetProp("m_iGameState", state);
	
	statevalue = GameRules_GetProp("m_iGameState");
	PrintToServer("After in GR: m_iGameState %i", statevalue);	

	return Plugin_Handled;
}
public Action:ChangeGameTypeGR(client, args)
{ 
	new String:arg1[130];
	GetCmdArg(1, arg1, sizeof(arg1));
	new state = StringToInt(arg1);
	
	new statevalue = GameRules_GetProp("m_iGameType");
	PrintToServer("Before in GR: m_iGameType %i", statevalue);	
	
	GameRules_SetProp("m_iGameType", state);
	
	statevalue = GameRules_GetProp("m_iGameType");
	PrintToServer("After in GR: m_iGameType %i", statevalue);	
	PrintToChatAll("After in GR: m_iGameType %i", statevalue);	
	return Plugin_Handled;
}

public Action:ChangeGameType(client, args)
{ 
	new String:arg1[130];
	GetCmdArg(1, arg1, sizeof(arg1));
	new typevalue = StringToInt(arg1);
	
	new index = -1;
	index = FindEntityByClassname(index, "neo_gamerules");
	
	
	typevalue = GetEntData(index, GetEntSendPropOffs(index, "m_iGameType"));
	
	PrintToServer("Before in GR: m_iGameType %i", typevalue);	
	
	SetEntData(index, GetEntSendPropOffs(index, "m_iGameType"), typevalue);
	
	PrintToServer("After in GR: m_iGameType %i", GetEntProp(index, Prop_Data, "m_iGameType"));	
	PrintToChatAll("After in GR: m_iGameType %i", typevalue);	
	return Plugin_Handled;
}



public Action:CheckGameStateGR(client, args)
{ 
	new statevalue = GameRules_GetProp("m_iGameState");
	PrintToServer("GR m_iGameState is %i", statevalue);
	PrintToConsole(client, "GR m_iGameState is %i", statevalue);
	return Plugin_Handled;
}

stock CheckGamestate2()
{ 
	new statevalue = GameRules_GetProp("m_iGameState");
	PrintToServer("m_iGameState is %i", statevalue);
}

public Action:CheckGameType(client, args)
{ 
	new typevalue = GameRules_GetProp("m_iGameType");
	PrintToServer("m_iGameType is %i", typevalue);
	PrintToConsole(client, "In GR m_iGameType is %i", typevalue);
	return Plugin_Handled;
}

stock CheckGameType2()
{ 
	new typevalue = GameRules_GetProp("m_iGameType");
	PrintToServer("In GR m_iGameType is %i", typevalue);
}


public Action:CheckGameStateProxy(client, args)
{
	CheckGamestate3();
	return Plugin_Handled;
}

stock CheckGamestate3()  //through proxy
{ 
	new index = -1;
	index = FindEntityByClassname(index, "neo_gamerules"); 
	new statevalue = GetEntData(index, GetEntSendPropOffs(index, "m_iGameState")); 
	PrintToServer("In proxy: m_iGameState is %i", statevalue);
}

public Action:ChangeGameStateProxy(client, args)
{
	new String:arg1[3];
	GetCmdArg(1, arg1, sizeof(arg1));
	new state = StringToInt(arg1);

	new index = -1;
	index = FindEntityByClassname(index, "neo_gamerules");	
	SetEntData(index, GetEntSendPropOffs(index, "m_iGameState"), state); 
	CheckGamestate3();
	return Plugin_Handled;
}
#endif
/*======================================

		End of debugging commands
		
========================================*/


public StartDeathmatch() 
{
	g_DMStarted = true; 
	new timeLimit = GetConVarInt(convar_nt_tdm_timelimit);
	new Handle:hTimeLimit = FindConVar("mp_timelimit");
	#if DEBUG > 1
	new gamerulesentity;
	new gamestateoffset;
	#endif 
	
	new index = -1;
	InitArray();

	#if DEBUG > 1
	CheckGameType2();
	CheckGamestate2();
	#endif
	
	GameRules_SetProp("m_iGameType", 0);    				//1 is CTG, 0 is TDM 
	GameRules_SetProp("m_iGameState", 1);    				//m_iGameState 1 is round preparation coundown / waiting for players. m_iGameState 2 is round in progress
	GameRules_SetProp("m_bFreezePeriod", 0);
	
	index = FindEntityByClassname(index, "neo_gamerules");  // this should be the gamerules proxy
	/*
	new weaponcontrol = -1;
	weaponcontrol = FindEntityByClassname(weaponcontrol, "game_weapon_manager");
	PrintToServer("weaponcontrol = %d", weaponcontrol);
	PrintToServer("weaponcontrol = %d, maxpieces = %d", weaponcontrol, GetEntData(weaponcontrol, GetEntSendPropOffs(weaponcontrol, "m_iMaxPieces")));
	SetEntData(weaponcontrol, GetEntSendPropOffs(weaponcontrol, "m_iMaxPieces"), 5);
	PrintToServer("weaponcontrol = %d, maxpieces = %d", weaponcontrol, GetEntData(weaponcontrol, GetEntSendPropOffs(weaponcontrol, "m_iMaxPieces")));
	*/
	#if DEBUG > 1
	new typevalue, statevalue;	
	typevalue = GetEntData(index, GetEntSendPropOffs(index, "m_iGameType"));
	statevalue = GetEntData(index, GetEntSendPropOffs(index, "m_iGameState"));  
	PrintToServer("Before: in proxy index %i m_iGameType %i m_iGameState %i", index, typevalue, statevalue);
	PrintToChatAll("Before: in proxy index %i m_iGameType %i m_iGameState %i", index, typevalue, statevalue);	
	#endif
	
	SetEntData(index, GetEntSendPropOffs(index, "m_iGameType"), 0);
	SetEntData(index, GetEntSendPropOffs(index, "m_iGameState"), 1);  
	SetEntData(index, GetEntSendPropOffs(index, "m_bFreezePeriod"), 1);
	
	#if DEBUG > 1
	CheckGameType2();
	CheckGamestate2();
	
	gamerulesentity = GetEntSendPropOffs(index, "m_iGameType");
	gamestateoffset = GetEntSendPropOffs(index, "m_iGameState");

	typevalue = GetEntData(index, GetEntSendPropOffs(index, "m_iGameType"));
	statevalue = GetEntData(index, GetEntSendPropOffs(index, "m_iGameState"));  
	PrintToServer("in proxyindex %i m_iGameType offset %i m_iGameState offset %i", index, gamerulesentity, gamestateoffset);
	PrintToChatAll("in proxy index %i m_iGameType offset %i m_iGameState offset %i", index, gamerulesentity, gamestateoffset);
	PrintToServer("After: in proxy index %i m_iGameType %i m_iGameState %i", index, typevalue, statevalue);
	PrintToChatAll("After: in proxy index %i m_iGameType %i m_iGameState %i", index, typevalue, statevalue);
	#endif 
	
	SetConVarInt(hTimeLimit, timeLimit);
	GameRules_SetPropFloat("m_fRoundTimeLeft", timeLimit * 60.0); 
	//ServerCommand("neo_restart_this 1");   // this doesn't make sense.
	GameRules_SetProp("m_iGameState", 1);  
	
	
	if(g_kvfilefound && g_AmmoPackKeyPresent && g_AmmoPackCoordsPresent) //if we have AmmoPacks keyvalues, spawn the first batch
	{
		SpawnAmmoPack();
	}
	
	if(g_kvfilefound && g_GrenadePacksKeyPresent && g_GrenadePacksCoordsPresent) //if we have GrenadePacks keyvalues, spawn the first batch
	{
		SpawnGrenadePack();
	}
	
	if(g_kvfilefound && g_LaddersKeyPresent && g_LaddersCoordsPresent) //if we have Ladder keyvalues, spawn them
	{
		SpawnLadder();
	}
	
	KillRemainingGhost();
}


public StopDeathMatch()
{
	g_DMStarted = false;
	new timeLimit = 320;
	new Handle:hTimeLimit = FindConVar("mp_timelimit");
	new index = -1;

	#if DEBUG > 1
	CheckGameType2();
	CheckGamestate2();
	#endif
	
	GameRules_SetProp("m_iGameType", 1); 					  //1 is CTG, 0 is TDM 
	GameRules_SetProp("m_iGameState", 1); 
	

	index = FindEntityByClassname(index, "neo_gamerules");						// this may not have any effect?
	
	#if DEBUG > 1
	new typevalue, statevalue;	
	typevalue = GetEntData(index, GetEntSendPropOffs(index, "m_iGameType"));    // this may not have any effect!
	statevalue = GetEntData(index, GetEntSendPropOffs(index, "m_iGameState"));

	PrintToServer("Before: in proxy index %i m_iGameType %i m_iGameState %i", index, typevalue, statevalue);
	PrintToChatAll("Before: in proxy index %i m_iGameType %i m_iGameState %i", index, typevalue, statevalue);
	#endif
	
	SetEntData(index, GetEntSendPropOffs(index, "m_iGameType"), 1);
	SetEntData(index, GetEntSendPropOffs(index, "m_iGameState"), 1); 
	
	#if DEBUG > 1
	CheckGameType2();
	CheckGamestate2();
	
	typevalue = GetEntData(index, GetEntSendPropOffs(index, "m_iGameType"));
	statevalue = GetEntData(index, GetEntSendPropOffs(index, "m_iGameState"));
	
	PrintToServer("After: in proxy index %i m_iGameType %i m_iGameState %i", index, typevalue, statevalue);
	PrintToChatAll("After: in proxy index %i m_iGameType %i m_iGameState %i", index, typevalue, statevalue);
	#endif
	
	ServerCommand("neo_restart_this 1");
	SetConVarInt(hTimeLimit, timeLimit);
	GameRules_SetPropFloat("m_fRoundTimeLeft", 30.25);   //testing. -glub
}

public OnTimeLimitChanged(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	if (g_DMStarted)
	{
		new timeLimit = GetConVarInt(convar_nt_tdm_timelimit);
		new Handle:hTimeLimit = FindConVar("mp_timelimit");

		SetConVarInt(hTimeLimit, timeLimit);
		GetMapTimeLeft(timeLimit);
		GameRules_SetPropFloat("m_fRoundTimeLeft", timeLimit * 1.0);
	}
}

public OnPlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (g_DMStarted)
	{
		if(!g_KF_enabled)
		{
			new victim = GetClientOfUserId(GetEventInt(event, "userid"));
			new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

			new victimTeam = GetClientTeam(victim);
			new attackerTeam = GetClientTeam(attacker);   //FIXME! error Native "GetClientTeam" reported: Client index 0 is invalid when suiciding with world

			new score = 1;
			if (attackerTeam == victimTeam)
				score = -1;								//FIXME! might be redundant with other plugins, thus doing -2 (probably not that bad)

			SetTeamScore(attackerTeam, GetTeamScore(attackerTeam) + score);
		}
	
		if (g_KF_enabled)				//Question: do we give a player point for killing, and a team point for picking up a dogtag?
		{
			new victim = GetClientOfUserId(GetEventInt(event, "userid"));
			new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
			new victimTeam = GetClientTeam(victim);
			new attackerTeam = GetClientTeam(attacker);

			if (attackerTeam == victimTeam)
			{
				SetTeamScore(attackerTeam, GetTeamScore(attackerTeam) - 1 ); //FIXME! might be redundant with other plugins, thus doing -2 (probably not that bad)
			}
			
			//removing the kill point for the player in HardCore mode
			if(g_KF_Hardcore_enabled)
				SetEntProp(attacker, Prop_Data, "m_iFrags", GetEntProp(attacker, Prop_Data, "m_iFrags") - 1 ); 
			

			new Float:deathorigin[3];
			GetClientAbsOrigin(victim,deathorigin);
			//GetEntPropVector(victim, Prop_Send, "m_vecOrigin", deathorigin);
			
			
			if(victimTeam == 3)  //3 is NSF
			{
				SpawnDogTag(deathorigin, g_DogTagModelNSF);
			}
			if(victimTeam == 2)  //2 is JINRAI
			{
				SpawnDogTag(deathorigin, g_DogTagModelJINRAI);
			}
		}
		
		
		//TODO: clear unused smokes and detpacks
		
		
		
	}
	if (!g_DMStarted) 
	{
		if (g_KF_enabled)				//if we want KF in CTG for example
		{
			new victim = GetClientOfUserId(GetEventInt(event, "userid"));
			new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
			new victimTeam = GetClientTeam(victim);
			new attackerTeam = GetClientTeam(attacker);

			if (attackerTeam == victimTeam)
			{
				SetTeamScore(attackerTeam, GetTeamScore(attackerTeam) - 1 ); //FIXME! might be redundant with other plugins, thus doing -2 (probably not that bad)
			}
			
			//removing the kill point for the player in HardCore mode
			if(g_KF_Hardcore_enabled)
				SetEntProp(attacker, Prop_Data, "m_iFrags", GetEntProp(attacker, Prop_Data, "m_iFrags") - 1 ); 

			new Float:deathorigin[3];
			GetClientAbsOrigin(victim,deathorigin);
			//GetEntPropVector(victim, Prop_Send, "m_vecOrigin", deathorigin);
			
			
			if(victimTeam == 3)  //3 is NSF
			{
				SpawnDogTag(deathorigin, g_DogTagModelNSF);
			}
			if(victimTeam == 2)  //2 is JINRAI
			{
				SpawnDogTag(deathorigin, g_DogTagModelJINRAI);
			}
		}
	}	
}

public Action:SpawnDogTag(Float:deathlocation[3], const String:modelname[])
{
	if(StrEqual(modelname, g_DogTagModelNSF) || (StrEqual(modelname, g_DogTagModelJINRAI)))
	{
		decl m_iDogTag;

		if((m_iDogTag = CreateEntityByName("prop_dynamic_override")) != -1)
		{
			new String:targetname[100];

			if(StrEqual(modelname, g_DogTagModelNSF, false))
			{
				Format(targetname, sizeof(targetname), "DogTag_%i", m_iDogTag);   //FIXME! probably won't work
			}
			if(StrEqual(modelname, g_DogTagModelJINRAI, false))
			{
				Format(targetname, sizeof(targetname), "DogTag_%i", m_iDogTag);
			}

			DispatchKeyValue(m_iDogTag, "model", modelname);
			//DispatchKeyValue(m_iDogTag, "physicsmode", "2");
			//DispatchKeyValue(m_iDogTag, "massScale", "1.0");
			DispatchKeyValue(m_iDogTag, "targetname", targetname);

			
			SetEntProp(m_iDogTag, Prop_Send, "m_usSolidFlags", 136);  //8 was default, 136 is OK for dynamic
			SetEntProp(m_iDogTag, Prop_Send, "m_CollisionGroup", 11); //1 was default, 11 is ok for dynamic
			DispatchKeyValueVector(m_iDogTag, "Origin", deathlocation);
			DispatchSpawn(m_iDogTag);

			SDKHook(m_iDogTag, SDKHook_StartTouch, OnDogTagTouched);

			
			new m_iRotator = CreateEntityByName("func_rotating");
			DispatchKeyValueVector(m_iRotator, "Origin", deathlocation);
			DispatchKeyValue(m_iRotator, "targetname", targetname);
			DispatchKeyValue(m_iRotator, "maxspeed", "50"); //100 is good!
			DispatchKeyValue(m_iRotator, "friction", "0");
			DispatchKeyValue(m_iRotator, "dmg", "0");
			DispatchKeyValue(m_iRotator, "solid", "0");  //0 default
			DispatchKeyValue(m_iRotator, "spawnflags", "64");  //64 default
			DispatchSpawn(m_iRotator);
			
			SetVariantString("!activator");
			AcceptEntityInput(m_iDogTag, "SetParent", m_iRotator, m_iRotator); 
			AcceptEntityInput(m_iRotator, "Start");

			SetEntPropEnt(m_iDogTag, Prop_Send, "m_hEffectEntity", m_iRotator); 
			
			DogTagDropTimer[m_iRotator] = CreateTimer(g_DogTagRemoveTime, RemoveDogTag, m_iRotator);
			DogTagDropTimer[m_iDogTag] = CreateTimer(g_DogTagRemoveTime + 0.1, RemoveDogTag, m_iDogTag); // delaying parent just in case
			
		}	
		return Plugin_Handled;
	}
	
	if(StrEqual(modelname, g_DogTagModelNSFphysics) || (StrEqual(modelname, g_DogTagModelJINRAIphysics)))
	{
		decl m_iDogTag;

		if((m_iDogTag = CreateEntityByName("prop_physics_override")) != -1)
		{
			new String:targetname[100];

			if(StrEqual(modelname, g_DogTagModelNSF, false))
			{
				Format(targetname, sizeof(targetname), "DogTag_%i", m_iDogTag);   //FIXME! probably won't work
			}
			if(StrEqual(modelname, g_DogTagModelJINRAI, false))
			{
				Format(targetname, sizeof(targetname), "DogTag_%i", m_iDogTag);
			}

			DispatchKeyValue(m_iDogTag, "model", modelname);
			//DispatchKeyValue(m_iDogTag, "physicsmode", "2");
			DispatchKeyValue(m_iDogTag, "massScale", "100.0");
			DispatchKeyValue(m_iDogTag, "targetname", targetname);

			
			SetEntProp(m_iDogTag, Prop_Send, "m_usSolidFlags", 136);  //8 was default, 136 is OK for dynamic
			SetEntProp(m_iDogTag, Prop_Send, "m_CollisionGroup", 6); //1 was default, 11 is ok for dynamic
			DispatchKeyValueVector(m_iDogTag, "Origin", deathlocation);
			AcceptEntityInput(m_iDogTag, "DisableShadow"); 
			DispatchSpawn(m_iDogTag);

			SDKHook(m_iDogTag, SDKHook_StartTouch, OnDogTagTouched);

			DogTagDropTimer[m_iDogTag] = CreateTimer(g_DogTagRemoveTime + 0.1, RemoveDogTag, m_iDogTag); // delaying parent just in case
			
		}	
		return Plugin_Handled;
	}
	return Plugin_Handled;
}

public Action:OnDogTagTouched(propi, client)
{
	if(client > 0 && client <= GetMaxClients() && propi > 0 && !IsFakeClient(client) && IsValidEntity(client) && IsClientInGame(client) && IsPlayerAlive(client) && IsValidEdict(propi))
	{
 		// kill the linked func_rotating first
		new m_iRotator = GetEntPropEnt(propi, Prop_Send, "m_hEffectEntity");
		if(m_iRotator > 0 && IsValidEdict(m_iRotator) && DogTagDropTimer[m_iRotator] != INVALID_HANDLE)
		AcceptEntityInput(m_iRotator, "Kill");
		
		#if DEBUG > 0
		PrintToChatAll("[DEBUG] Killed rotator dogtag %i", m_iRotator);
		#endif

		//check team affiliation
		new playerteam = GetClientTeam(client);
		
		if(playerteam == 3) //3 is NSF
		{

			//checking model name, which determines dogtag ownership (bad method, needs improvement)
			new String:modelname[128];
			GetEntPropString(propi, Prop_Data, "m_ModelName", modelname, 128);
			
			if(StrEqual(modelname, g_DogTagModelNSF, false))  // model is NSF, we deny
			{
				if(GetTeamScore(playerteam) < 0)
				{
					SetTeamScore(playerteam, GetTeamScore(playerteam) + 1);  //adding one point to team score board, because we're nice
				}
				
				if(GetEntProp(client, Prop_Data, "m_iFrags") < 0)  //same, if player score is negative (after a TK), we are nice and increment back up
					SetEntProp(client, Prop_Data, "m_iFrags", GetEntProp(client, Prop_Data, "m_iFrags") + 1 );

				
				// emit sound effect
				new Float:coords_KilledEnt[3];
				GetEntPropVector(propi, Prop_Send, "m_vecOrigin", coords_KilledEnt);
				EmitSoundToAll(g_DogTagPickupSoundDenied, SOUND_FROM_WORLD, SNDCHAN_AUTO, 130, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, coords_KilledEnt);
				
				
				#if DEBUG > 0
				PrintToChatAll("Denied a dogtag");
				PrintToConsole(client, "Denied a dogtag, coords %f %f %f", coords_KilledEnt[0], coords_KilledEnt[1], coords_KilledEnt[2]);
				#endif
				PrintToChat(client, "You denied a Memory Footprint!");
				KillItemTimer(propi);					 //killing timer handle that was supposed to remove it after a while
				CreateTimer(0.1, RemoveDogTag, propi);
				return Plugin_Handled;
			}
			
			if(StrEqual(modelname, g_DogTagModelJINRAI, false))  // model is JINRAI, we add point
			{

				SetTeamScore(playerteam, GetTeamScore(playerteam) + 1);  // adding one point to team score board
				
				if(g_KF_Hardcore_enabled)
				{
					SetEntProp(client, Prop_Data, "m_iFrags", GetEntProp(client, Prop_Data, "m_iFrags") + 1 ); //adding one point to player (if hardcore mode enabled)
				}
				
				// emit sound effect
				new Float:coords_KilledEnt[3];
				GetEntPropVector(propi, Prop_Send, "m_vecOrigin", coords_KilledEnt);
				EmitSoundToAll(g_DogTagPickupSound, SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_HIGH, -1, coords_KilledEnt);
			
				#if DEBUG > 0
				PrintToChatAll("Picked up a dogtag");
				PrintToConsole(client, "Picked up a dogtag, coords %f %f %f", coords_KilledEnt[0], coords_KilledEnt[1], coords_KilledEnt[2]);
				#endif
				PrintToChat(client, "You picked up a Memory Footprint!");
				KillItemTimer(propi);
				CreateTimer(0.1, RemoveDogTag, propi);
				return Plugin_Handled;
			}
		}
		
		if(playerteam == 2) //2 is JINRAI
		{

			//checking model name, which determines dogtag ownership (bad method, needs improvement)
			new String:modelname[128];
			GetEntPropString(propi, Prop_Data, "m_ModelName", modelname, 128);
			
			if(StrEqual(modelname, g_DogTagModelJINRAI, false))  // model is JINRAI, we deny
			{
				if(GetTeamScore(playerteam) < 0)
				{
					SetTeamScore(playerteam, GetTeamScore(playerteam) + 1);  //adding one point to team score board, because we're nice
				}
				
				if(GetEntProp(client, Prop_Data, "m_iFrags") < 0)  //if player score is negative (after a TK), we are kind and increment
					SetEntProp(client, Prop_Data, "m_iFrags", GetEntProp(client, Prop_Data, "m_iFrags") + 1 );

				
				// emit sound effect
				new Float:coords_KilledEnt[3];
				GetEntPropVector(propi, Prop_Send, "m_vecOrigin", coords_KilledEnt);
				EmitSoundToAll(g_DogTagPickupSoundDenied, SOUND_FROM_WORLD, SNDCHAN_AUTO, 130, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, coords_KilledEnt);
				
				#if DEBUG > 0
				PrintToChatAll("Denied a dogtag");
				PrintToConsole(client, "Denied a dogtag, coords %f %f %f", coords_KilledEnt[0], coords_KilledEnt[1], coords_KilledEnt[2]);
				#endif
				PrintToChat(client, "You denied a Memory Footprint!");
				KillItemTimer(propi);
				CreateTimer(0.1, RemoveDogTag, propi);
				return Plugin_Handled;
			}
			
			if(StrEqual(modelname, g_DogTagModelNSF, false))  // model is NSF, we add point
			{

				SetTeamScore(playerteam, GetTeamScore(playerteam) + 1);  // adding one point to team score board
				if(g_KF_Hardcore_enabled)
				{
					SetEntProp(client, Prop_Data, "m_iFrags", GetEntProp(client, Prop_Data, "m_iFrags") + 1 ); //adding one point to player (if hardcore mode enabled)
				}
				
				// emit sound effect
				new Float:coords_KilledEnt[3];
				GetEntPropVector(propi, Prop_Send, "m_vecOrigin", coords_KilledEnt);
				EmitSoundToAll(g_DogTagPickupSound, SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_HIGH, -1, coords_KilledEnt);
			
				#if DEBUG > 0
				PrintToChatAll("Picked up a dogtag");
				PrintToConsole(client, "Picked up a dogtag, coords %f %f %f", coords_KilledEnt[0], coords_KilledEnt[1], coords_KilledEnt[2]);
				#endif
				PrintToChat(client, "You picked up a Memory Footprint!");
				KillItemTimer(propi);
				CreateTimer(0.1, RemoveDogTag, propi);
				return Plugin_Handled;
			}
			
		}
		
	}
	#if DEBUG > 1
	if(client > 0 && client <= GetMaxClients() && propi > 0 && IsValidEntity(client) && !IsFakeClient(client) && IsClientInGame(client) && IsPlayerAlive(client) && IsValidEdict(propi))
	{
		new Float:coords_KilledEnt[3];
		new m_iRotator = GetEntPropEnt(propi, Prop_Send, "m_hEffectEntity");
		if(m_iRotator >= 0)
		{
			GetEntPropVector(m_iRotator, Prop_Send, "m_vecOrigin", coords_KilledEnt);
			PrintToChatAll("[DEBUG] skipped condition for dogtag? prop = %i %f %f %f", propi, coords_KilledEnt[0], coords_KilledEnt[1], coords_KilledEnt[2]);
			PrintToServer("[DEBUG] skipped condition for dogtag? prop = %i %f %f %f", propi, coords_KilledEnt[0], coords_KilledEnt[1], coords_KilledEnt[2]);
		}
	}
	#endif
	
	return Plugin_Handled;
}


public OnPlayerSpawn(Handle:event,const String:name[],bool:dontBroadcast)
{
	if (g_DMStarted)
	{
		new client = GetClientOfUserId(GetEventInt(event, "userid"));
		if (GetClientTeam(client) > 1)
		{
			CreateTimer(0.1, timer_GetHealth, client);
			
			//Enable Protection on the client
			clientProtected[client] = true;

			CreateTimer(GetConVarFloat(convar_nt_tdm_spawnprotect), timer_PlayerProtect, client);
			
			if(g_kvfilefound)
			{
				if(g_RandomPlayerSpawns == true)
				{
					if(g_PlayerCoordsKeyPresent == true)  //if map name is found in the keyvalue file of the same name
					{

					//randomint = GenerateRandomInt();  			//RANDOM COORDINATES GO!
					randomint = UTIL_GetRandomInt(0, lines -1);
					
					#if DEBUG > 1
					PrintToServer("1st Randomint: %i", randomint);
					#endif 
					
					//if(randomint == randomint_allowing_array)
					
					do
					{
						if((randomint == randomint_prev) || randomint_allowing_array[randomint] != 0) //checking if not the same number rolled right before AND if the number is allowed now (=1)
						{
							//randomint = GenerateRandomInt();
							randomint = UTIL_GetRandomInt(0, lines -1);
							
							#if DEBUG > 1
							PrintToServer("2nd Randomint: %i", randomint);
							#endif
						}
						randomint_prev = randomint;  //storing current randomint 
						
						//randomint = GenerateRandomInt();
						randomint = UTIL_GetRandomInt(0, lines -1);
						
						#if DEBUG > 1
						PrintToServer("3rd Randomint: %i", randomint);
						#endif
						
					}while(randomint_allowing_array[randomint] != 0);
					
					#if DEBUG > 1
					PrintToServer("Final Randomint: %i", randomint);
					#endif
					
					//new randomint = GetRandomInt(0, lines -1);
					//new String:randomvaluenumber[4] = IntToString(randomint, randomvaluenumber, sizeof(randomvaluenumber));
			
					new Float:NewOrigin[3];
					new Float:NewAngles[3];
					NewOrigin[0] = coordinates_array[randomint][0];
					NewOrigin[1] = coordinates_array[randomint][1];
					NewOrigin[2] = coordinates_array[randomint][2];
					NewAngles[0] = angles_array[randomint][0];
					NewAngles[1] = angles_array[randomint][1];
					NewAngles[2] = angles_array[randomint][2];
					
					DispatchKeyValueVector(client, "Origin", NewOrigin);
					DispatchKeyValueVector(client, "Angles", NewAngles);
					
					
					WriteNumberHistory(randomint);
					
					CreateTimer(12.0, ClearLock);  // Clears lock after 12 seconds for this set of spawn coordinates

					#if DEBUG > 1
					PrintToServer("SPAWNING: randomint=%d, randomint_allowing_array=%d origin %f %f %f coordsarray: %f %f %f", randomint, randomint_allowing_array[randomint], NewOrigin[0], NewOrigin[1], NewOrigin[2], coordinates_array[randomint][0], coordinates_array[randomint][1], coordinates_array[randomint][2]);
					PrintToServer("------");
					#endif
					}
				}
			}
		}
	}
}

public WriteNumberHistory(int randominteger)
{	
	if(history_cursor >= sizeof(randomint_history))
	{
		history_cursor = 0;
	}
	new randomint_for_history = randomint;
	do
	{
	randomint_history[history_cursor] = randomint_for_history;  //or randominteger?
	randomint_allowing_array[randomint_for_history] = 1;  //used this randomint just now, forbids using it for 10sec
	
	#if DEBUG > 1
	PrintToServer("HISTORY. randomint_history = %i, history_cursor = %i", randomint_history[history_cursor], history_cursor);
	PrintToServer("PERMISSION? randomint_allowing_array=%i, randomint %i set to 1, forbidden!", randomint_allowing_array[randomint_for_history], randomint_for_history);
	PrintToServer("------");
	#endif
	
	history_cursor++;
	//PrintToServer("After ++: randomint_history[history_cursor]: %i, history_cursor %i", randomint_history[history_cursor], history_cursor);
	break;
	}while (history_cursor < sizeof(randomint_history));
}



public Action:ClearLock(Handle:timer)
{
	int retrieved_value_from_history;  
	if(tobereset_int_cursor >= sizeof(randomint_history))
	{
		tobereset_int_cursor = 0;
	}	
	
	retrieved_value_from_history = randomint_history[tobereset_int_cursor];    //we retrieve the very first integer stored	

	#if DEBUG > 1
	PrintToServer("TIMER. Before randomint_allowing_array[%i] is %i about to reset to 0", retrieved_value_from_history, randomint_allowing_array[retrieved_value_from_history]);	
	PrintToServer("TIMER. retrieved_value_from_history is %i tobereset_int_cursor is at %i", retrieved_value_from_history, tobereset_int_cursor);	
	#endif 
	
	tobereset_int_cursor++;
	
	
	randomint_allowing_array[retrieved_value_from_history] = 0;  //we allow the int to be used
	
	#if DEBUG > 1
	PrintToServer("TIMER. After randomint_allowing_array[%i] is %i. Now reset to 0 = now allowed!", retrieved_value_from_history, randomint_allowing_array[retrieved_value_from_history]);
	PrintToServer("------");
	#endif
}


public GenerateRandomInt()
{
	return GetRandomInt(1, lines)-1;
}

UTIL_GetRandomInt(start, end) {
    new rand;
    rand = GetURandomInt();
    return ( rand % (1 + end - start) ) + start;
}

/*
UTIL_ArrayIntRand(array[], size)
{
    if ( size < 2 )
    {
        return;
    }
    new tmpIndex, tmpValue;
    for ( new i = 0; i < size-1; i++ )
    {
        tmpIndex = UTIL_GetRandomInt(i, size-1);
        if ( tmpIndex == i )
        {
            continue;
        }
        tmpValue = array[tmpIndex];
        
        array[tmpIndex] = array[i];
        array[i] = tmpValue;
    }
}
*/

void InitArray()
{
	g_kvfilefound = false;
	decl String:CurrentMap[64];
	GetCurrentMap(CurrentMap, 64);		
	
	//new String:MapConfig[PLATFORM_MAX_PATH];
	//Format(MapConfig, sizeof(MapConfig), "config/%s.txt", Ma );
	
	
	static String:file[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, file, sizeof(file), "configs/%s.txt", CurrentMap);
	new Handle:kv = CreateKeyValues("Coordinates");
	
	if(FileExists(file))
	{
		g_kvfilefound = true;
	}
	
	if(FileToKeyValues(kv, file) && g_kvfilefound)
	{
		do
		{
			//if(!FileToKeyValues(kv, file))
			//{
			//	PrintToServer("%s.txt was not found! No custom spawns!", CurrentMap);
			//	g_kvfilefound = false;
			//	break;
			//} 
			//->removed, otherwise randomed spawns not working
			
			if(!KvJumpToKey(kv, "player coordinates"))
			{
				PrintToServer("[TDM] player coordinates key was not found in the keyvalues file!");
				g_PlayerCoordsKeyPresent = false;
				break;
			}else{ g_PlayerCoordsKeyPresent = true; }

			if(!KvGotoFirstSubKey(kv))  //we place ourselves at the first entry
			{
				PrintToServer("Error finding first subkey for entry %s", CurrentMap);
				break;
			}
			/*
			int count;
			for(count = 0; (count <= 100 ) && (KvGotoNextKey(kv)); count++)  //ok I'm dumb, this is redundant -glub
			{
				continue;    
			}
			
			KvRewind(kv);
			KvJumpToKey(kv, CurrentMap);
			KvGotoFirstSubKey(kv);
			lines = count + 1;
			*/
			
			int i;
			do
			{
				if(i >= lines)
					break;
			
				KvGetVector(kv, "coordinates", coordinates_array[i]);
				KvGetVector(kv, "angles", angles_array[i]); 
				
				#if DEBUG > 1
				PrintToServer("%d: %f, %f, %f; %f, %f, %f", i, coordinates_array[i][0], coordinates_array[i][1], coordinates_array[i][2], angles_array[i][0], angles_array[i][1], angles_array[i][2]);
				#endif
				
				i++;
			} while (KvGotoNextKey(kv));
			lines = i;
			
			#if DEBUG >= 1
			PrintToServer("lines : %d", lines);
			#endif
			
			KvRewind(kv);  //going back to top of kv
			
			
			
			if(!KvJumpToKey(kv, "Ammopacks"))
			{
				PrintToServer("Ammopacks coordinates key was not found in the keyvalues file!");
				g_AmmoPackKeyPresent = false;
				break;
			}
			else{ g_AmmoPackKeyPresent = true; }

			if(!KvGotoFirstSubKey(kv)) 
			{
				PrintToServer("Error finding first subkey for entry in Ammopacks. Assuming we don't want any.");
				g_AmmoPackCoordsPresent = false;
				break;
			}
			else{ g_AmmoPackCoordsPresent = true; }
			
			i = 0;
			do
			{
				if(i >= ammolines)
					break;
			
				KvGetVector(kv, "coordinates", ammocoords_array[i]);
				KvGetVector(kv, "angles", ammoangles_array[i]); 
				
				#if DEBUG > 1
				PrintToServer("Ammo %d: %f, %f, %f; %f, %f, %f", i, ammocoords_array[i][0], ammocoords_array[i][1], ammocoords_array[i][2], ammoangles_array[i][0], ammoangles_array[i][1], ammoangles_array[i][2]);
				#endif
				
				i++;
			} while (KvGotoNextKey(kv));
			ammolines = i; //number of ammo subkeys counted
			
			#if DEBUG >= 1
			PrintToServer("ammolines : %d", ammolines);
			#endif
			
			KvRewind(kv);  //going back to top of kv again

			
			
			if(!KvJumpToKey(kv, "Grenadepacks"))
			{
				PrintToServer("Grenadepacks coordinates key was not found in the keyvalues file!");
				g_GrenadePacksKeyPresent = false;
				break;
			}
			else{ g_GrenadePacksKeyPresent = true; }

			if(!KvGotoFirstSubKey(kv)) 
			{
				PrintToServer("Error finding first subkey for coordinates entry in Grenadepacks. Assuming we don't want any.");
				g_GrenadePacksCoordsPresent = false;
				break;
			}
			else{ g_GrenadePacksCoordsPresent = true; }
			
			i = 0;
			do
			{
				if(i >= grenadelines)
					break;
			
				KvGetVector(kv, "coordinates", grenadecoords_array[i]);
				KvGetVector(kv, "angles", grenadeangles_array[i]); 
				
				#if DEBUG > 1
				PrintToServer("Grenade %d: %f, %f, %f; %f, %f, %f", i, grenadecoords_array[i][0], grenadecoords_array[i][1], grenadecoords_array[i][2], grenadecoords_array[i][0], grenadecoords_array[i][1], grenadecoords_array[i][2]);
				#endif
				
				i++;
			} while (KvGotoNextKey(kv));
			grenadelines = i; //number of grenadepack subkeys counted
			
			#if DEBUG >= 1
			PrintToServer("grenadelines : %d", grenadelines);
			#endif


			KvRewind(kv);  //going back to top of kv one last time

			
			
			if(!KvJumpToKey(kv, "Ladders"))
			{
				PrintToServer("Ladders key was not found in the keyvalues file!");
				g_LaddersKeyPresent = false;
				break;
			}
			else{ g_LaddersKeyPresent = true; }

			if(!KvGotoFirstSubKey(kv)) 
			{
				PrintToServer("Error finding first subkey for coordinates entry in Ladders. Assuming we don't want any.");
				g_LaddersCoordsPresent = false;
				break;
			}
			else{ g_LaddersCoordsPresent = true; }
			
			i = 0;
			do
			{
				if(i >= ladderlines)
					break;
			
				KvGetVector(kv, "coordinates", laddercoords_array[i]);
				KvGetVector(kv, "angles", ladderangles_array[i]); 
				
				#if DEBUG > 1
				PrintToServer("Ladder %d: %f, %f, %f; %f, %f, %f", i, laddercoords_array[i][0], laddercoords_array[i][1], laddercoords_array[i][2], ladderangles_array[i][0], ladderangles_array[i][1], ladderangles_array[i][2]);
				#endif
				
				i++;
			} while (KvGotoNextKey(kv));
			ladderlines = i; //number of ladder subkeys counted
			#if DEBUG > 1
			PrintToServer("ladderlines : %d", ladderlines);
			#endif		
			
			
		} while (false);
		CloseHandle(kv);
	}
	#if DEBUG > 0
	PrintToServer("KeyValues file for %s not found in %s", CurrentMap, file);
	#endif
}


public SpawnAmmoPack()
{
	new prop[30];

	
	for(new i; i < ammolines; i++)
	{

		
		new Float:temp_ammo_coords[3];
		new Float:temp_ammo_angle[3]; 
		
		temp_ammo_coords[0] = ammocoords_array[i][0];
		temp_ammo_coords[1] = ammocoords_array[i][1];
		temp_ammo_coords[2] = ammocoords_array[i][2];
		temp_ammo_angle[0] = ammoangles_array[i][0];
		temp_ammo_angle[1] = ammoangles_array[i][1];
		temp_ammo_angle[2] = ammoangles_array[i][2];
		
		

		//SetEntProp(prop[i], Prop_Data, "m_usSolidFlags", 136);
		
		prop[i] = ReSpawnAmmo(temp_ammo_coords, g_AmmoPackModel);
		
		
		/*DispatchKeyValue(prop[i], "model", "models/d/d_s02.mdl");
		//DispatchKeyValueVector(prop[i], "Origin", temp_ammo_coords);
		//DispatchKeyValueVector(prop[i], "Angles", temp_ammo_angle);
		
		
		if(DispatchSpawn(prop[i]))
		{
			SetEntProp(prop[i], Prop_Send, "m_usSolidFlags", 136);
			SetEntProp(prop[i], Prop_Send, "m_CollisionGroup", 11);
			//TODO make them unbreakable
		}
		
		
		//new String:EntityTargetName[256];
		//Format(EntityTargetName, sizeof(EntityTargetName), "%d", i);
		//DispatchKeyValue(prop[i], "targetname", EntityTargetName);*/
		
		//SDKHook(prop[i], SDKHook_StartTouch, OnAmmoPackTouched);
		
		#if DEBUG > 1
		PrintToServer("Dropped ammopack! number %i", i);
		#endif
	}
}

public SpawnGrenadePack()
{
	for(new i; i < grenadelines; i++)
	{

		
		new Float:temp_grenade_coords[3];
		new Float:temp_grenade_angle[3]; 
		
		temp_grenade_coords[0] = grenadecoords_array[i][0];
		temp_grenade_coords[1] = grenadecoords_array[i][1];
		temp_grenade_coords[2] = grenadecoords_array[i][2];
		temp_grenade_angle[0] = grenadeangles_array[i][0];
		temp_grenade_angle[1] = grenadeangles_array[i][1];
		temp_grenade_angle[2] = grenadeangles_array[i][2];
		
		

		//SetEntProp(prop[i], Prop_Data, "m_usSolidFlags", 136);
		
		grenadeprop[i] = ReSpawnGrenade(temp_grenade_coords, g_GrenadePackModel);	

		
		/*DispatchKeyValue(grenadeprop[i], "model", "models/items/boxmrounds.mdl");
		//DispatchKeyValueVector(grenadeprop[i], "Origin", temp_grenade_coords);
		//DispatchKeyValueVector(grenadeprop[i], "Angles", temp_grenade_angle);
		
		
		if(DispatchSpawn(grenadeprop[i]))
		{
			SetEntProp(grenadeprop[i], Prop_Send, "m_usSolidFlags", 136);
			SetEntProp(grenadeprop[i], Prop_Send, "m_CollisionGroup", 11);
			//TODO make them unbreakable
		}
		
		
		//new String:EntityTargetName[256];
		//Format(EntityTargetName, sizeof(EntityTargetName), "%d", i);
		//DispatchKeyValue(grenadeprop[i], "targetname", EntityTargetName);*/
		
		//SDKHook(grenadeprop[i], SDKHook_StartTouch, OnGrenadePackTouched);
		
		#if DEBUG > 1
		PrintToServer("Dropped grenadepack! number %i", i);
		#endif
	}
}


/*
public OnGameFrame()
{
	MoveUp();
}

public MoveUp()
{
	for(new i = 0; i <= grenadelines; i++)
	{
		if(grenadeprop[i] > 0 && IsValidEntity(grenadeprop[i]))
		{
			decl Float:coods_new[3];
			decl Float:coods_temps[3];
			GetEntPropVector(grenadeprop[i], Prop_Send, "m_vecOrigin", coods_temps);
			coods_temps[2] = 60.0;
			coods_new[0] = coods_temps[0];
			coods_new[1] = coods_temps[1];
			coods_new[2] = coods_temps[2];
			DispatchKeyValueVector(grenadeprop[i], "Origin", coods_new);
			PrintToServer("done :%d, entity %d %i %i %i", i, grenadeprop[i], coods_new[0], coods_new[1], coods_new[2]);
		}
	}
	
	//for(new i = 0; i <= grenadelines; i++)
	//{
	
		if(b_movestart == true){
		new i = 1;
		new Float:fPos[3];
		GetEntPropVector(grenadeprop[i], Prop_Send, "m_vecOrigin", fPos);
		if(bUp) {
			fPos[2] += 1.0;
			if(fPos[2] > 30.0) bUp = false;
		} else {
			fPos[2] -= 1.0;
			if(fPos[2] < -30.0) bUp = true;
		}
		//DispatchKeyValueVector(grenadeprop[i], "Origin", fPos);
		ChangeEdictState(grenadeprop[i], GetEntSendPropOffs(grenadeprop[i], "m_vecOrigin", true));
		PrintToServer("done :%d, entity %d %f %f %f", i, grenadeprop[i], fPos[0], fPos[1], fPos[2]);
		}
	//}
}
*/


public SpawnLadder()
{
	new ladderprop[60];

	
	for(new i; i < ladderlines; i++)
	{
		new Float:temp_ladder_coords[3];
		new Float:temp_ladder_angle[3]; 
		
		temp_ladder_coords[0] = laddercoords_array[i][0];
		temp_ladder_coords[1] = laddercoords_array[i][1];
		temp_ladder_coords[2] = laddercoords_array[i][2];
		temp_ladder_angle[0] = ladderangles_array[i][0];
		temp_ladder_angle[1] = ladderangles_array[i][1];
		temp_ladder_angle[2] = ladderangles_array[i][2];
		
		ladderprop[i] = CreateEntityByName("prop_dynamic");
		DispatchKeyValue(ladderprop[i], "model", g_LadderModel);
		DispatchKeyValueVector(ladderprop[i], "Origin", temp_ladder_coords);
		DispatchKeyValueVector(ladderprop[i], "Angles", temp_ladder_angle);
		
		
		if(DispatchSpawn(ladderprop[i]))
		{
			SetEntProp(ladderprop[i], Prop_Send, "m_usSolidFlags", 136);
			SetEntProp(ladderprop[i], Prop_Send, "m_CollisionGroup", 6);   //FIX make solid
			#if DEBUG > 1
			PrintToServer("Spawned ladder number %i", i);
			#endif
		}
	}
}




stock ReSpawnAmmo(Float:position[3], const String:model[])
{
	decl m_iGift;

	if((m_iGift = CreateEntityByName("prop_dynamic_override")) != -1)
	{
		new String:targetname[100];

		Format(targetname, sizeof(targetname), "ammo_%i", m_iGift);

		DispatchKeyValue(m_iGift, "model", model);
		//DispatchKeyValue(m_iGift, "physicsmode", "2");
		//DispatchKeyValue(m_iGift, "massScale", "1.0");
		DispatchKeyValue(m_iGift, "targetname", targetname);

		
		SetEntProp(m_iGift, Prop_Send, "m_usSolidFlags", 136);  //8 was default 
		SetEntProp(m_iGift, Prop_Send, "m_CollisionGroup", 11); //1 was default
		DispatchKeyValueVector(m_iGift, "Origin", position);
		DispatchSpawn(m_iGift);

		SDKHook(m_iGift, SDKHook_StartTouch, OnAmmoPackTouched);

		
		new m_iRotator = CreateEntityByName("func_rotating");
		DispatchKeyValueVector(m_iRotator, "Origin", position);
		DispatchKeyValue(m_iRotator, "targetname", targetname);
		DispatchKeyValue(m_iRotator, "maxspeed", "100"); //100 is good!
		DispatchKeyValue(m_iRotator, "friction", "0");
		DispatchKeyValue(m_iRotator, "dmg", "0");
		DispatchKeyValue(m_iRotator, "solid", "0");  //0 default
		DispatchKeyValue(m_iRotator, "spawnflags", "64");  //64 default
		DispatchSpawn(m_iRotator);
		
		SetVariantString("!activator");
		AcceptEntityInput(m_iGift, "SetParent", m_iRotator, m_iRotator);
		AcceptEntityInput(m_iRotator, "Start");

		SetEntPropEnt(m_iGift, Prop_Send, "m_hEffectEntity", m_iRotator);
		
	}	
	return m_iGift;
}


stock ReSpawnGrenade(Float:position[3], const String:model[])
{
	decl m_iGrenade;

	if((m_iGrenade = CreateEntityByName("prop_dynamic_override")) != -1)
	{
		new String:targetname[100];

		Format(targetname, sizeof(targetname), "grenade_%i", m_iGrenade);

		DispatchKeyValue(m_iGrenade, "model", model);
		//DispatchKeyValue(m_iGrenade, "physicsmode", "2");
		//DispatchKeyValue(m_iGrenade, "massScale", "1.0");
		DispatchKeyValue(m_iGrenade, "targetname", targetname);

		DispatchKeyValue(m_iGrenade, "solid", "0");
		//DispatchKeyValue(m_iGrenade, "spawnflags", "4");
		//SetEntProp(m_iGrenade, Prop_Data, "m_spawnflags", 4); //works, but no effect?
		
		SetEntProp(m_iGrenade, Prop_Send, "m_usSolidFlags", 136);  //8 was default -> 136 is needed for prop_dynamic in order for SDKhook to work
		SetEntProp(m_iGrenade, Prop_Send, "m_CollisionGroup", 11); //1 was default -> 11 works too, not mandatory
		DispatchKeyValueVector(m_iGrenade, "Origin", position);
		DispatchSpawn(m_iGrenade);

		SDKHook(m_iGrenade, SDKHook_StartTouch, OnGrenadePackTouched);

		
		new m_iRotator = CreateEntityByName("func_rotating");
		DispatchKeyValueVector(m_iRotator, "Origin", position);
		DispatchKeyValue(m_iRotator, "targetname", targetname);
		DispatchKeyValue(m_iRotator, "maxspeed", "100");
		DispatchKeyValue(m_iRotator, "friction", "0");
		DispatchKeyValue(m_iRotator, "dmg", "0");
		DispatchKeyValue(m_iRotator, "solid", "0");  //0 default
		DispatchKeyValue(m_iRotator, "spawnflags", "64");  //64 default = "Not Solid"
		DispatchSpawn(m_iRotator);
		
		SetVariantString("!activator");
		AcceptEntityInput(m_iGrenade, "SetParent", m_iRotator, m_iRotator);
		AcceptEntityInput(m_iRotator, "Start");

		SetEntPropEnt(m_iGrenade, Prop_Send, "m_hEffectEntity", m_iRotator);
		
	}
	return m_iGrenade;
}

public Action:OnAmmoPackTouched(propi, client)
{
	if(client > 0 && client <= GetMaxClients() && propi > 0 && !IsFakeClient(client) && IsValidEntity(client) && IsClientInGame(client) && IsPlayerAlive(client) && IsValidEdict(propi))
	{
		
		new String:classname[13];
		new Float:coords_KilledEnt[3];
		#if DEBUG > 1
		new AmmoType;
		#endif
		

		for(new weapon = 0; weapon <= 5; weapon++) 		// NT has only five weapon slots, loop trough them and remove all valid weapons
		{
			// Get entity id from offset
			new wpn = GetEntDataEnt2(client, gOffsetMyWeapons + (weapon * 4));

			if(!IsValidEntity(wpn))
				continue;

			if(!GetEdictClassname(wpn, classname, 13))
				continue; // Skip if we for some reason can't get classname

			if(StrEqual(classname, "weapon_knife"))
				continue; // Skip if it's knife
		
			if(StrEqual(classname, "weapon_mpn")) 
			{
				SetWeaponAmmo(client, UTIL_GetAmmoType(wpn), GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)) + 60); // 2mags of 30 bullets
				#if DEBUG > 1
				AmmoType = UTIL_GetAmmoType(wpn); // returns 4
				PrintToChatAll("AmmoType: %d wpn: %d WeaponAmmo: %d", AmmoType, wpn, GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)));
				#endif
				PrintToChat(client, "You picked up some ammo!");
				continue;
			}
			if(StrEqual(classname, "weapon_milso"))
			{
				SetWeaponAmmo(client, UTIL_GetAmmoType(wpn), GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)) + 24); // 2mags of 12 bullets
				#if DEBUG > 1
				AmmoType = UTIL_GetAmmoType(wpn);
				PrintToChatAll("AmmoType: %d wpn: %d WeaponAmmo: %d", AmmoType, wpn, GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)));
				#endif
				continue;
			}
			if(StrEqual(classname, "weapon_supa7"))
			{
				SetWeaponAmmo(client, UTIL_GetAmmoType(wpn), GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)) + 14); // 2*7 shells  // not sure about slugs
				#if DEBUG > 1
				AmmoType = UTIL_GetAmmoType(wpn);
				PrintToChatAll("AmmoType: %d wpn: %d WeaponAmmo: %d", AmmoType, wpn, GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)));
				#endif
				PrintToChat(client, "You picked up some ammo!");
				continue;
			}
			if(StrEqual(classname, "weapon_zr68c") || StrEqual(classname, "weapon_zr68s"))
			{
				SetWeaponAmmo(client, UTIL_GetAmmoType(wpn), GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)) + 60); // 2x30
				#if DEBUG > 1
				AmmoType = UTIL_GetAmmoType(wpn);
				PrintToChatAll("AmmoType: %d wpn: %d WeaponAmmo: %d", AmmoType, wpn, GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)));
				#endif
				PrintToChat(client, "You picked up some ammo!");
				continue;
			}
			if(StrEqual(classname, "weapon_mx") || StrEqual(classname, "weapon_mx_silenced"))
			{
				SetWeaponAmmo(client, UTIL_GetAmmoType(wpn), GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)) + 60); // 2x30
				#if DEBUG > 1
				AmmoType = UTIL_GetAmmoType(wpn);
				PrintToChatAll("AmmoType: %d wpn: %d WeaponAmmo: %d", AmmoType, wpn, GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)));
				#endif
				PrintToChat(client, "You picked up some ammo!");
				continue;
			}
			if(StrEqual(classname, "weapon_m41") || StrEqual(classname, "weapon_m41s"))
			{
				SetWeaponAmmo(client, UTIL_GetAmmoType(wpn), GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)) + 30); // 2x15
				#if DEBUG > 1
				AmmoType = UTIL_GetAmmoType(wpn);
				PrintToChatAll("AmmoType: %d wpn: %d WeaponAmmo: %d", AmmoType, wpn, GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)));
				#endif
				PrintToChat(client, "You picked up some ammo!");
				continue;
			}
			if(StrEqual(classname, "weapon_jitte") || StrEqual(classname, "weapon_jittescoped"))
			{
				SetWeaponAmmo(client, UTIL_GetAmmoType(wpn), GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)) + 60); // 2x30
				#if DEBUG > 1
				AmmoType = UTIL_GetAmmoType(wpn);
				PrintToChatAll("AmmoType: %d wpn: %d WeaponAmmo: %d", AmmoType, wpn, GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)));
				#endif
				PrintToChat(client, "You picked up some ammo!");
				continue;
			}
			if(StrEqual(classname, "weapon_srm") || StrEqual(classname, "weapon_srm_s"))
			{
				SetWeaponAmmo(client, UTIL_GetAmmoType(wpn), GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)) + 100); // 2x50
				#if DEBUG > 1
				AmmoType = UTIL_GetAmmoType(wpn);
				PrintToChatAll("AmmoType: %d wpn: %d WeaponAmmo: %d", AmmoType, wpn, GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)));
				#endif
				PrintToChat(client, "You picked up some ammo!");
				continue;
			}
			if(StrEqual(classname, "weapon_kyla"))
			{
				SetWeaponAmmo(client, UTIL_GetAmmoType(wpn), GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)) + 24); // 4*6 bullets
				#if DEBUG > 1
				AmmoType = UTIL_GetAmmoType(wpn);
				PrintToChatAll("AmmoType: %d wpn: %d WeaponAmmo: %d", AmmoType, wpn, GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)));
				#endif
				continue;
			}
			if(StrEqual(classname, "weapon_pz"))
			{
				SetWeaponAmmo(client, UTIL_GetAmmoType(wpn), GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)) + 200); // 2*100
				#if DEBUG > 1
				AmmoType = UTIL_GetAmmoType(wpn);
				PrintToChatAll("AmmoType: %d wpn: %d WeaponAmmo: %d", AmmoType, wpn, GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)));
				#endif
				PrintToChat(client, "You picked up some ammo!");
				continue;
			}
			if(StrEqual(classname, "weapon_srs"))
			{
				SetWeaponAmmo(client, UTIL_GetAmmoType(wpn), GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)) + 15); // 3*5 bullets
				#if DEBUG > 1
				AmmoType = UTIL_GetAmmoType(wpn);
				PrintToChatAll("AmmoType: %d wpn: %d WeaponAmmo: %d", AmmoType, wpn, GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)));
				#endif
				PrintToChat(client, "You picked up some ammo!");
				continue;
			}
			if(StrEqual(classname, "weapon_tachi"))
			{
				SetWeaponAmmo(client, UTIL_GetAmmoType(wpn), GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)) + 30); // 3*15
				#if DEBUG > 1
				AmmoType = UTIL_GetAmmoType(wpn);
				PrintToChatAll("AmmoType: %d wpn: %d WeaponAmmo: %d", AmmoType, wpn, GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)));
				#endif
				continue;
			}
			if(StrEqual(classname, "weapon_zr68l"))
			{
				SetWeaponAmmo(client, UTIL_GetAmmoType(wpn), GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)) + 20); // 2*10 
				#if DEBUG > 1
				AmmoType = UTIL_GetAmmoType(wpn);
				PrintToChatAll("AmmoType: %d wpn: %d WeaponAmmo: %d", AmmoType, wpn, GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)));
				#endif 
				PrintToChat(client, "You picked up some ammo!");
				continue;
			}
			if(StrEqual(classname, "weapon_aa13"))
			{
				SetWeaponAmmo(client, UTIL_GetAmmoType(wpn), GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)) + 32); // 2*16
				#if DEBUG > 1
				AmmoType = UTIL_GetAmmoType(wpn);
				PrintToChatAll("AmmoType: %d wpn: %d WeaponAmmo: %d", AmmoType, wpn, GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)));
				#endif 
				PrintToChat(client, "You picked up some ammo!");
				continue;
			}
			
			
			//GetWeaponAmmo(client, UTIL_GetAmmoType(wpn))
			
			//SetWeaponAmmo(client, UTIL_GetAmmoType(wpn), GetWeaponAmmo(client, UTIL_GetAmmoType(wpn)) + 30); // 30 bullets no matter what
		
			//SetWeaponAmmo(client, 11, 92); // shotgun ammo + 7 shells in magazine
			//SetWeaponAmmo(client, 5, 54);  // secondary ammo + 6 shells in magazine
			
		}

		new m_iRotator = GetEntPropEnt(propi, Prop_Send, "m_hEffectEntity");
		if(m_iRotator && IsValidEdict(m_iRotator))
		AcceptEntityInput(m_iRotator, "Kill");  			// need to kill the func_rotating first otherwise the origin coordinates will be 0,0,0 (local coordinates versus global?)
	
		GetEntPropVector(propi, Prop_Send, "m_vecOrigin", coords_KilledEnt);
		
		if(ammo_coords_cursor >= sizeof(ammocoords_array))
		{
			ammo_coords_cursor = 0;		
		}
		
		ammocoords_array[ammo_coords_cursor][0] = coords_KilledEnt[0];
		ammocoords_array[ammo_coords_cursor][1] = coords_KilledEnt[1];
		ammocoords_array[ammo_coords_cursor][2] = coords_KilledEnt[2];
		
		#if DEBUG > 1
		PrintToServer("origin of killed ammopack: %f %f %f cursor=%d", coords_KilledEnt[0], coords_KilledEnt[1], coords_KilledEnt[2], ammo_coords_cursor);
		PrintToServer("origin new ammopack to spawn: %f %f %f", ammocoords_array[ammo_coords_cursor][0], ammocoords_array[ammo_coords_cursor][1], ammocoords_array[ammo_coords_cursor][2]);
		#endif

		//EmitSoundToClient(client, "ammo_pickup.wav", SOUND_FROM_PLAYER,SNDCHAN_AUTO,SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL);
		
		EmitSoundToAll(g_AmmoPickupSound, SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, coords_KilledEnt);
		
		//ClientCommand(client, "playgamesound HL2Player.PickupWeapon"); //this works if all else fails, only to player though
		// OR Player.PickupWeapon instead of HL2Player.PickupWeapon (NT specific) or BaseCombatCharacter.AmmoPickup because same file pointed at
		//EmitGameSound*() don't work in Neotokyo because PrecacheScriptSound() and GetGameSoundParams() crash NT server
		
		
		CreateTimer(g_AmmoRespawnTime, timer_RespawnAmmoPack, ammo_coords_cursor);
		
		#if DEBUG > 1
		PrintToChatAll("refilled done");
		#endif

	
		CreateTimer(0.0, RemoveEntity, propi);
		//AcceptEntityInput(propi, "kill");
		ammo_coords_cursor++;
		return Plugin_Handled;
	}
	#if DEBUG > 1
	if(client > 0 && client <= GetMaxClients() && propi > 0 && IsValidEntity(client) && !IsFakeClient(client) && IsClientInGame(client) && IsPlayerAlive(client) && IsValidEdict(propi))
	{
		new Float:coords_KilledEnt[3];
		new m_iRotator = GetEntPropEnt(propi, Prop_Send, "m_hEffectEntity");
		GetEntPropVector(m_iRotator, Prop_Send, "m_vecOrigin", coords_KilledEnt);
		//PrintToChatAll("skipped condition for ammopack? prop = %i %f %f %f", propi, coords_KilledEnt[0], coords_KilledEnt[1], coords_KilledEnt[2]);
		PrintToServer("skipped condition for ammopack? prop = %i %f %f %f", propi, coords_KilledEnt[0], coords_KilledEnt[1], coords_KilledEnt[2]);
	}
	#endif
	
	return Plugin_Handled;
}



stock GetAmmoType(weapon)
{
	return GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
}


UTIL_GetAmmoType(weapon) {
	new g_iOffs_iPrimaryAmmoType = -1;
	g_iOffs_iPrimaryAmmoType = FindSendPropInfo("CBaseCombatWeapon","m_iPrimaryAmmoType"); 

	if ( g_iOffs_iPrimaryAmmoType == -1 )
	{
		PrintToServer("FATAL ERROR g_iOffs_iPrimaryAmmoType [%d].", g_iOffs_iPrimaryAmmoType);
	} 
	return GetEntData(weapon, g_iOffs_iPrimaryAmmoType, 1);
}


stock GetWeaponAmmo(client, type)
{
    new g_iOffsetAmmo = FindSendPropInfo("CBasePlayer", "m_iAmmo");

    return GetEntData(client, g_iOffsetAmmo + (type * 4));
}  

stock SetWeaponAmmo(client, type, ammo)
{
    new g_iOffsetAmmo = FindSendPropInfo("CBasePlayer", "m_iAmmo");

    return SetEntData(client, g_iOffsetAmmo + (type * 4), ammo);
}

stock GetActiveWeapon(client)
{
	return GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
} 


/*
{
    g_iOffsetAmmo = FindSendPropInfo("CBasePlayer", "m_iAmmo");
    if (g_iOffsetAmmo == INVALID_OFFSET) {
        PrintToServer("FATAL ERROR: Offset \"CBasePlayer::m_iAmmo\" was not found.");
    }

    OffsetMovement = FindSendPropOffs("CBasePlayer", "m_flLaggedMovementValue");
    if(OffsetMovement == INVALID_OFFSET)
    {
        PrintToServer("FATAL ERROR OffsetMovement [%d]. Please contact the author.", OffsetMovement);
    } 

    m_hMyWeapons = FindSendPropOffs("CBasePlayer", "m_hMyWeapons");
    if(m_hMyWeapons == INVALID_OFFSET)
    {
        PrintToServer("FATAL ERROR m_hMyWeapons [%d]. Please contact the author.", m_hMyWeapons);
    }

    OffsetWeaponParent = FindSendPropOffs("CBaseCombatWeapon", "m_hOwnerEntity");
    if ( OffsetWeaponParent == INVALID_OFFSET )
    {
        PrintToServer("FATAL ERROR OffsetWeaponParent [%d]. Please contact the author.", OffsetWeaponParent);
    }

    
    FindOffset();
}
*/

public Action:OnGrenadePackTouched(propi, client)
{

	if(client > 0 && client <= GetMaxClients() && propi > 0 && !IsFakeClient(client) && IsValidEntity(client) && IsClientInGame(client) && IsPlayerAlive(client) && IsValidEdict(propi))
	{
		
		new String:classname[24];
		new bool:hasdetpack = false;		

		for(new weapon = 0; weapon <= 5; weapon++) 		// NT has only five weapon slots, loop trough them and remove all valid weapons
		{
			// Get entity id from offset
			new wpn = GetEntDataEnt2(client, gOffsetMyWeapons + (weapon * 4));
			
			if(!IsValidEntity(wpn))
				continue;

			if(!GetEdictClassname(wpn, classname, 24))
				continue; // Skip if we for some reason can't get classname

			if(StrEqual(classname, "weapon_knife"))
				continue; // Skip if it's knife
			
			if(StrEqual(classname, "weapon_remotedet"))
				#if DEBUG > 1
				PrintToChat(client, "You already have a detpack!");
				#endif 
				hasdetpack = true;
				continue;
		}
		new randomcase = UTIL_GetRandomInt(1, 8);
		
		#if DEBUG > 1
		PrintToChatAll("random grenade case is %d", randomcase);
		#endif
		
		switch (randomcase)
		{
			case 1:
			{
				GivePlayerItem(client, "weapon_grenade");
				PrintToChat(client, "You picked up a grenade!");
			}
			case 2:
			{
				GivePlayerItem(client, "weapon_smokegrenade");
				PrintToChat(client, "You picked up two smoke grenades!");
			}
			case 3:
			{
				if(hasdetpack == false)
				{
					GivePlayerItem(client, "weapon_smokegrenade");
					PrintToChat(client, "You picked up two smoke grenades!");
				}
				if(hasdetpack == true)
				{
					GivePlayerItem(client, "weapon_remotedet");
					PrintToChat(client, "You picked up a remote detpack!");
				}
			}
			case 4:
			{
				GivePlayerItem(client, "weapon_grenade");
				PrintToChat(client, "You picked up a grenade!");
				//break;
			}
			case 5:
			{
				GivePlayerItem(client, "weapon_smokegrenade");
				PrintToChat(client, "You picked up two smoke grenades!");
			}
			case 6:
			{				
				GivePlayerItem(client, "weapon_grenade");
				PrintToChat(client, "You picked up a grenade!");
			}
			case 7:
			{
				GivePlayerItem(client, "weapon_grenade");
				PrintToChat(client, "You picked up a grenade!");
			}
			case 8:
			{
				GivePlayerItem(client, "weapon_grenade");
				PrintToChat(client, "You picked up a grenade!");
			}
		}

		new m_iRotator = GetEntPropEnt(propi, Prop_Send, "m_hEffectEntity");
		if(m_iRotator && IsValidEdict(m_iRotator))
		AcceptEntityInput(m_iRotator, "Kill");  			// need to kill the func_rotating first otherwise the origin coordinates will be 0,0,0 (local coordinates versus global?)

		new Float:coords_KilledEnt[3];	
		GetEntPropVector(propi, Prop_Send, "m_vecOrigin", coords_KilledEnt);
		
		if(grenade_coords_cursor >= sizeof(grenadecoords_array))
		{
			grenade_coords_cursor = 0;		
		}
		
		grenadecoords_array[grenade_coords_cursor][0] = coords_KilledEnt[0];
		grenadecoords_array[grenade_coords_cursor][1] = coords_KilledEnt[1];
		grenadecoords_array[grenade_coords_cursor][2] = coords_KilledEnt[2];

		#if DEBUG > 1
		PrintToServer("origin of killed grenadepack: %f %f %f grenade_coords_cursor = %i", coords_KilledEnt[0], coords_KilledEnt[1], coords_KilledEnt[2], grenade_coords_cursor);
		PrintToServer("origin new grenadepack to spawn: %f %f %f", grenadecoords_array[grenade_coords_cursor][0], grenadecoords_array[grenade_coords_cursor][1], grenadecoords_array[grenade_coords_cursor][2]);
		#endif

		//EmitSoundToClient(client, "ammo_pickup.wav", SOUND_FROM_PLAYER,SNDCHAN_AUTO,SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL);
		
		EmitSoundToAll(g_GrenadePickupSound, SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, coords_KilledEnt);
		
		//ClientCommand(client, "playgamesound HL2Player.PickupWeapon"); //this works if all else fails, only to player though
		// OR Player.PickupWeapon instead of HL2Player.PickupWeapon (NT specific) or BaseCombatCharacter.AmmoPickup because same file pointed at
		//EmitGameSound*() don't work in Neotokyo because PrecacheScriptSound() and GetGameSoundParams() crash NT server
		
		#if DEBUG > 1
		PrintToChatAll("Picked up grenade pack");		
		#endif
		
		CreateTimer(g_GrenadeRespawnTime, timer_RespawnGrenadePack, grenade_coords_cursor);  //respawns after x secs
		CreateTimer(0.0, RemoveEntity, propi);
		//AcceptEntityInput(propi, "kill");
	
		grenade_coords_cursor++;
		return Plugin_Handled;
	}
	#if DEBUG > 1
	if(client > 0 && client <= GetMaxClients() && propi > 0 && IsValidEntity(client) && !IsFakeClient(client) && IsClientInGame(client) && IsPlayerAlive(client) && IsValidEdict(propi))
	{
		new Float:coords_KilledEnt[3];
		new m_iRotator = GetEntPropEnt(propi, Prop_Send, "m_hEffectEntity");
		GetEntPropVector(m_iRotator, Prop_Send, "m_vecOrigin", coords_KilledEnt);
		PrintToChatAll("skipped condition for grenadepack? prop = %i %f %f %f", propi, coords_KilledEnt[0], coords_KilledEnt[1], coords_KilledEnt[2]);
		PrintToServer("skipped condition for grenadepack? prop = %i %f %f %f", propi, coords_KilledEnt[0], coords_KilledEnt[1], coords_KilledEnt[2]);
	}
	#endif
	
	return Plugin_Handled;
}

stock KillItemTimer(entity)   // do as the healthkit plugin does, place this function in all ontouch, right before killing the prop
{
	if(DogTagDropTimer[entity] != INVALID_HANDLE)
	{
		CloseHandle(DogTagDropTimer[entity]);
	}
	DogTagDropTimer[entity] = INVALID_HANDLE;
}

public Action:RemoveDogTag(Handle:timer, any:entity)  // place in all timers that remove after a while
{
	DogTagDropTimer[entity] = INVALID_HANDLE;
	
	new String:EntName[256];
	//Entity_GetName(entity, EntName, sizeof(EntName)); //smlib
	if(IsValidEntity(entity))
	{
		if(GetEntPropString(entity, Prop_Data, "m_iName", EntName, sizeof(EntName)))
		{
			if(StrContains(EntName, "DogTag") || StrContains(EntName, "Rotator") || StrContains(EntName, "AmmoPack") || StrContains(EntName, "GrenadePack"))
			{
				if(entity > -1)
					AcceptEntityInput(entity, "KillHierarchy");
			}
		}
	}
}


public Action:RemoveEntity(Handle:timer, any:entity)  // place in all timers that remove after a while
{
	DogTagDropTimer[entity] = INVALID_HANDLE;
	if(IsValidEntity(entity))
		AcceptEntityInput(entity, "Kill");
		#if DEBUG > 1
		PrintToServer("Removed Entity: %d", entity);
		#endif
	return Plugin_Handled;
}

public Action:timer_RespawnAmmoPack(Handle:timer, cursor_position)
{
	//new ammopack;
	new Float:newcoords[3];
	newcoords[0] = ammocoords_array[cursor_position][0];
	newcoords[1] = ammocoords_array[cursor_position][1];
	newcoords[2] = ammocoords_array[cursor_position][2];
	#if DEBUG > 1
	PrintToServer("Dispatching according to cursor number: %d", cursor_position);
	#endif
	
	ReSpawnAmmo(newcoords, g_AmmoPackModel);	
	/*
	ammopack = CreateEntityByName("prop_dynamic");
	DispatchKeyValue(ammopack, "model", "models/d/d_s02.mdl");
	DispatchKeyValueVector(ammopack, "Origin", newcoords);
	
	if(DispatchSpawn(ammopack))
	{
		SetEntProp(ammopack, Prop_Send, "m_usSolidFlags", 136);
		SetEntProp(ammopack, Prop_Send, "m_CollisionGroup", 11);
		
		//TODO make them unbreakable
	}
	SDKHook(ammopack, SDKHook_StartTouch, OnAmmoPackTouched); // Obsolete -glub */
	
	//return Plugin_Handled;
}


public Action:timer_RespawnGrenadePack(Handle:timer, cursor_position)
{
	//new grenadepack;
	new Float:newcoords[3];
	newcoords[0] = grenadecoords_array[cursor_position][0];
	newcoords[1] = grenadecoords_array[cursor_position][1];
	newcoords[2] = grenadecoords_array[cursor_position][2];
	
	#if DEBUG > 1
	PrintToServer("Dispatching according to cursor number: %d", cursor_position);
	#endif 
	
	ReSpawnGrenade(newcoords, g_GrenadePackModel);
	//return Plugin_Handled;
}


//Get the player's health after they spawn
public Action:timer_GetHealth(Handle:timer, any:client)
{
	if(IsClientConnected(client) && IsClientInGame(client))
	{
		clientHP[client] = GetClientHealth(client);
	}
}

//Player protection expires
public Action:timer_PlayerProtect(Handle:timer, any:client)
{
	//Disable protection on the Client
	clientProtected[client] = false;
	
	if(IsClientConnected(client) && IsClientInGame(client))
	{
		PrintToChat(client, "[TDM] Your spawn protection is now disabled");
		//EmitSoundToClient(client, "saitama_corp_i.mp3", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
		//EmitSoundToClient(client, gSpawnSounds[GetRandomInt(0, sizeof(gSpawnSounds)-1)]);  // this works! -glub
	}
}

// Restore players health if they take damage while protected
public OnPlayerHurt(Handle:event,const String:name[],bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	if (clientProtected[client])
	{
		SetEntData(client, FindDataMapOffs(client, "m_iMaxHealth"), clientHP[client], 4, true);
		SetEntData(client, FindDataMapOffs(client, "m_iHealth"), clientHP[client], 4, true);
	}
}

public KillRemainingGhost()
{ 
	new String:classname[14];
	for(new i; i <= GetEntityCount(); i++)
	{

		if(IsValidEntity(i))
		{
			if(!GetEdictClassname(i, classname, 14))
			continue;
		
			if(StrEqual(classname, "weapon_ghost"))
			{
				AcceptEntityInput(i, "Kill");
			}
		}
	}
}


// in case we use on-map basis plugin load, unload the plugin after this map
public OnMapEnd()
{
	g_DMStarted = false;
	SetConVarInt(convar_nt_tdm_enabled, 0);
	SetConVarInt(convar_nt_tdm_kf_enabled, 0);
	SetConVarInt(convar_nt_tdm_kf_hardcore_enabled, 0);

	ReloadConflictingPlugins();
	ServerCommand("nt_healthkitdrop 0");
	//ServerCommand("tpr_enabled 0");
}
