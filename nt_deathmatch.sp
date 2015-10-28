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
				
		
**************************************************************/
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#define PLUGIN_VERSION	"0.1.1"

public Plugin:myinfo =
{
    name = "NEOTOKYOｰ Deathmatch",
    author = "Agiel",
    description = "Neotokyo team deathmatch",
    version = PLUGIN_VERSION,
    url = "https://github.com/Agiel/nt-deathmatch"
};

//new Handle:convar_nt_dm_version = INVALID_HANDLE;
new Handle:convar_nt_dm_enabled = INVALID_HANDLE;
new Handle:convar_nt_dm_timelimit = INVALID_HANDLE;
new Handle:convar_nt_dm_spawnprotect = INVALID_HANDLE;

new bool:g_DMStarted = false;

new clientProtected[MAXPLAYERS+1];
new clientHP[MAXPLAYERS+1];

new const String:gSpawnSounds[][] =
{
	"saitama_corp_i.mp3"
};

public OnPluginStart()
{
	//convar_nt_dm_version = CreateConVar("sm_nt_dm_version", PLUGIN_VERSION, "NEOTOKYOｰ Deathmatch.", FCVAR_PLUGIN | FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);
	convar_nt_dm_enabled = CreateConVar("sm_nt_dm_enabled", "0", "Enables or Disables deathmatch.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	convar_nt_dm_timelimit = CreateConVar("sm_nt_dm_timelimit", "20", "Sets deathmatch timelimit.", FCVAR_PLUGIN, true, 0.0, true, 60.0);
	convar_nt_dm_spawnprotect = CreateConVar("sm_nt_dm_spawnprotect", "5.0", "Length of time to protect spawned players", FCVAR_PLUGIN, true, 0.0, true, 30.0);
	AutoExecConfig(true);
	RegAdminCmd("sm_dres", CommandRestartDeatchmatch, ADMFLAG_SLAY, "restats deathmatch? debug command for testing");
	RegAdminCmd("sm_ds", CommandStopDeatchmatch, ADMFLAG_SLAY, "stops deathmatch? debug command for testing");
	RegAdminCmd("sm_gamestate", CommandGamestate, ADMFLAG_SLAY, "change gamestate");
	RegAdminCmd("check_gamestate", CheckGamestate, ADMFLAG_SLAY, "check gamestate");

	HookConVarChange(convar_nt_dm_timelimit, OnTimeLimitChanged);
	HookConVarChange(convar_nt_dm_enabled, OnConfigsExecutedHook);  //added glub
	
	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("player_hurt", OnPlayerHurt);
	HookEvent("player_death", OnPlayerDeath);
	
	for(new snd = 0; snd < sizeof(gSpawnSounds); snd++)
	PrecacheSound(gSpawnSounds[snd]);
}



public OnConfigsExecuted()
{
	g_DMStarted = false;
	if (GetConVarBool(convar_nt_dm_enabled))
	{
		StartDeathmatch();
		g_DMStarted = true;
		PrintToChatAll("Team DeathMatch enabled!");
	}
}


public OnAutoConfigsBuffered() {
	decl String:currentMap[64];
	GetCurrentMap(currentMap, 64);

	if(StrEqual(currentMap, "nt_terminal_ctg") || StrEqual(currentMap, "nt_sentinel_ctg") || StrEqual(currentMap, "nt_bullet_tdm") || StrEqual(currentMap, "nt_zaibatsu_ctg"))
		SetConVarInt(convar_nt_dm_enabled, 1);
	else
		SetConVarInt(convar_nt_dm_enabled, 0);
}



public OnConfigsExecutedHook(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	if (!GetConVarBool(convar_nt_dm_enabled))
	{
		StopDeathMatch();
		g_DMStarted = false;
		PrintToChatAll("Team DeathMatch stop!");
		PrintToServer("Team DeathMatch stop!");
		ServerCommand("neo_restart_this 1");
	}
	if (GetConVarBool(convar_nt_dm_enabled))
	{
		StopDeathMatch();
		StartDeathmatch();
		g_DMStarted = true;
		PrintToChatAll("Team DeathMatch start!");
		PrintToServer("Team DeathMatch start!");
		GameRules_SetPropFloat("m_fRoundTimeLeft", 10.0);    // if gamestate change from 0 to 1 and neo_restart_this 1, CTG back to normal, no respawn
		//GameRules_SetProp("m_iGameState", 1);    
		ServerCommand("neo_restart_this 1");
	}
}




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

public Action:CommandGamestate(client, args)
{ 
	new String:arg1[130];
	GetCmdArg(1, arg1, sizeof(arg1));
	new state = StringToInt(arg1);
	
	new statevalue = GameRules_GetProp("m_iGameState");
	PrintToServer("Before: m_iGameState %i", statevalue);	
	
	GameRules_SetProp("m_iGameState", state);
	
	statevalue = GameRules_GetProp("m_iGameState");
	PrintToServer("After: m_iGameState %i", statevalue);	

	return Plugin_Handled;
}

public Action:CheckGamestate(client, args)
{ 
	new statevalue = GameRules_GetProp("m_iGameState");
	PrintToServer("m_iGameState is %i", statevalue);
	PrintToConsole(client, "m_iGameState is %i", statevalue);
	return Plugin_Handled;
}


public StartDeathmatch() 
{
	new timeLimit = GetConVarInt(convar_nt_dm_timelimit);
	new Handle:hTimeLimit = FindConVar("mp_timelimit");
	new gamerulesentity;
	new gamestateoffset;
	new index = -1;
	GameRules_SetProp("m_iGameType", 0);    				//1 is CTG, 0 is TDM 
	GameRules_SetProp("m_iGameState", 1);    				//m_iGameState 1 is round preparation coundown / waiting for players. m_iGameState 2 is round in progress
	GameRules_SetProp("m_bFreezePeriod", 1);
	
	index = FindEntityByClassname(index, "neo_gamerules");  // this should be the gamerules proxy
	
	new typevalue, statevalue;	
	typevalue = GetEntData(index, GetEntSendPropOffs(index, "m_iGameType"));
	statevalue = GetEntData(index, GetEntSendPropOffs(index, "m_iGameState"));  

	PrintToServer("Before: index %i m_iGameType %i m_iGameState %i", index, typevalue, statevalue);
	PrintToChatAll("Before: index %i m_iGameType %i m_iGameState %i", index, typevalue, statevalue);	
	
	
	SetEntData(index, GetEntSendPropOffs(index, "m_iGameType"), 0);
	SetEntData(index, GetEntSendPropOffs(index, "m_iGameState"), 1);  
	SetEntData(index, GetEntSendPropOffs(index, "m_bFreezePeriod"), 1);
	gamerulesentity = GetEntSendPropOffs(index, "m_iGameType");
	gamestateoffset = GetEntSendPropOffs(index, "m_iGameState");
	
	typevalue = GetEntData(index, GetEntSendPropOffs(index, "m_iGameType"));
	statevalue = GetEntData(index, GetEntSendPropOffs(index, "m_iGameState"));  
	
	PrintToServer("index %i m_iGameType offset %i m_iGameState offset %i", index, gamerulesentity, gamestateoffset);
	PrintToChatAll("index %i m_iGameType offset %i m_iGameState offset %i", index, gamerulesentity, gamestateoffset);
	PrintToServer("After: index %i m_iGameType %i m_iGameState %i", index, typevalue, statevalue);
	PrintToChatAll("After: index %i m_iGameType %i m_iGameState %i", index, typevalue, statevalue);
	
	SetConVarInt(hTimeLimit, timeLimit);
	GameRules_SetPropFloat("m_fRoundTimeLeft", timeLimit * 60.0); 
}


public StopDeathMatch()
{
	g_DMStarted = false;
	new timeLimit = 320;
	new Handle:hTimeLimit = FindConVar("mp_timelimit");
	new index = -1;

	GameRules_SetProp("m_iGameType", 1); 					  //1 is CTG, 0 is TDM 
	GameRules_SetProp("m_iGameState", 1); 
	

	index = FindEntityByClassname(index, "neo_gamerules");
	new typevalue, statevalue;	
	typevalue = GetEntData(index, GetEntSendPropOffs(index, "m_iGameType"));
	statevalue = GetEntData(index, GetEntSendPropOffs(index, "m_iGameState"));
	PrintToServer("Before: index %i m_iGameType %i m_iGameState %i", index, typevalue, statevalue);
	PrintToChatAll("Before: index %i m_iGameType %i m_iGameState %i", index, typevalue, statevalue);

	
	SetEntData(index, GetEntSendPropOffs(index, "m_iGameType"), 1);
	SetEntData(index, GetEntSendPropOffs(index, "m_iGameState"), 1); 

	typevalue = GetEntData(index, GetEntSendPropOffs(index, "m_iGameType"));
	statevalue = GetEntData(index, GetEntSendPropOffs(index, "m_iGameState"));
	PrintToServer("After: index %i m_iGameType %i m_iGameState %i", index, typevalue, statevalue);
	PrintToChatAll("After: index %i m_iGameType %i m_iGameState %i", index, typevalue, statevalue);
	
	ServerCommand("neo_restart_this 1");
	SetConVarInt(hTimeLimit, timeLimit);
	GameRules_SetPropFloat("m_fRoundTimeLeft", 220.0);   //testing. -glub
}

public OnTimeLimitChanged(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	if (g_DMStarted)
	{
		new timeLimit = GetConVarInt(convar_nt_dm_timelimit);
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
		new victim = GetClientOfUserId(GetEventInt(event, "userid"));
		new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

		new victimTeam = GetClientTeam(victim);
		new attackerTeam = GetClientTeam(attacker);

		new score = 1;
		if (attackerTeam == victimTeam)
			score = -1;

		SetTeamScore(attackerTeam, GetTeamScore(attackerTeam) + score);
	}
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

			CreateTimer(GetConVarFloat(convar_nt_dm_spawnprotect), timer_PlayerProtect, client);
		}
	}
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
		PrintToChat(client, "[nt-dm] Your spawn protection is now disabled");
		//EmitSoundToClient(client, "saitama_corp_i.mp3", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
		EmitSoundToClient(client, gSpawnSounds[GetRandomInt(0, sizeof(gSpawnSounds)-1)]);
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

public OnMapEnd()
{
	g_DMStarted = false;
	ServerCommand("sm_nt_dm_enabled 0");
	ServerCommand("sm plugins unload disabled/nt_deathmatch-glub.smx");

}
