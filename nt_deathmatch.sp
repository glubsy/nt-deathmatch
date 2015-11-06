/**************************************************************
--------------------------------------------------------------
 NEOTOKYOРDeathmatch

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
	0.1.2
		* Added hook to disable, added random spawns for players
		Note
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
#define PLUGIN_VERSION	"0.1.2"

#define DEBUG 0
//#define DEBUG 1
//define DEBUG 2


public Plugin:myinfo =
{
    name = "NEOTOKYO Deathmatch",
    author = "Agiel then glub",
    description = "Neotokyo team deathmatch",
    version = PLUGIN_VERSION,
    url = "https://github.com/Agiel/nt-deathmatch"
};

//new Handle:convar_nt_dm_version = INVALID_HANDLE;
new Handle:convar_nt_dm_enabled = INVALID_HANDLE;
new Handle:convar_nt_dm_timelimit = INVALID_HANDLE;
new Handle:convar_nt_dm_spawnprotect = INVALID_HANDLE;
new Handle:convar_nt_dm_randomplayerspawns = INVALID_HANDLE;

new bool:g_DMStarted = false;

new clientProtected[MAXPLAYERS+1];
new clientHP[MAXPLAYERS+1];

	
new Float:coordinates_array[100][3];  //initializing big array of floats for coordinates
new Float:angles_array[100][3];	


int lines = 200;
int randomint;

int randomint_allowing_array[100];  //if set to 1, the number corresponding to the cell is forbidden for use, it set to 0 it's allowed.
int randomint_prev = -1;

int randomint_history[12];
int history_cursor;
int tobereset_int_cursor = 0;

new bool:g_RandomPlayerSpawns = false;
new bool:g_PlayerCoordsKeyPresent = false;

/*
new const String:gSpawnSounds[][] =
{
	"saitama_corp_i.mp3"
};
*/

public OnPluginStart()
{
	//convar_nt_dm_version = CreateConVar("sm_nt_dm_version", PLUGIN_VERSION, "NEOTOKYO Deathmatch.", FCVAR_PLUGIN | FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);
	convar_nt_dm_enabled = CreateConVar("sm_nt_dm_enabled", "0", "Enables or Disables deathmatch.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	convar_nt_dm_timelimit = CreateConVar("sm_nt_dm_timelimit", "20", "Sets deathmatch timelimit.", FCVAR_PLUGIN, true, 0.0, true, 60.0);
	convar_nt_dm_spawnprotect = CreateConVar("sm_nt_dm_spawnprotect", "5.0", "Length of time to protect spawned players", FCVAR_PLUGIN, true, 0.0, true, 30.0);
	convar_nt_dm_randomplayerspawns = CreateConVar("sm_nt_dm_randomplayerspawns", "1", "Activates or deactivates random spawns from keyvalue file", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	AutoExecConfig(true);
	
	#if DEBUG > 1
	RegAdminCmd("sm_dres", CommandRestartDeatchmatch, ADMFLAG_SLAY, "restats deathmatch? debug command for testing");
	RegAdminCmd("sm_ds", CommandStopDeatchmatch, ADMFLAG_SLAY, "stops deathmatch? debug command for testing");
	
	RegAdminCmd("change_gamestate_gr", ChangeGameStateGR, ADMFLAG_SLAY, "change gamestate through the GameRules");
	RegAdminCmd("change_gamestate_proxy", ChangeGameStateProxy, ADMFLAG_SLAY, "change gamestate through proxy");
	RegAdminCmd("check_gamestate_gr", CheckGameStateGR, ADMFLAG_SLAY, "check gamestate through Gamerules");
	RegAdminCmd("check_gamestate_proxy", CheckGameStateProxy, ADMFLAG_SLAY, "check gamestate through proxy");	
	RegAdminCmd("check_gametype", CheckGameType, ADMFLAG_SLAY, "check gametype");
	#endif
	
	HookConVarChange(convar_nt_dm_timelimit, OnTimeLimitChanged);
	HookConVarChange(convar_nt_dm_enabled, OnConfigsExecutedHook);  //added glub
	HookConVarChange(convar_nt_dm_randomplayerspawns, OnChangePlayerRandomSpawnsCvar);
	
	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("player_hurt", OnPlayerHurt);
	HookEvent("player_death", OnPlayerDeath);
	
	
//	for(new snd = 0; snd < sizeof(gSpawnSounds); snd++)
//	PrecacheSound(gSpawnSounds[snd]);    //precaching sound effect on spawn
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
	
	if (GetConVarBool(convar_nt_dm_randomplayerspawns))
	{
		g_RandomPlayerSpawns = true;
		PrintToChatAll("Random player spawns enabled!");
	}
	if (!GetConVarBool(convar_nt_dm_randomplayerspawns))
	{
		g_RandomPlayerSpawns = false;
		PrintToChatAll("Random player spawns disabled!");
	}
}


public OnAutoConfigsBuffered() {
	decl String:currentMap[64];
	GetCurrentMap(currentMap, 64);

	if(StrEqual(currentMap, "nt_terminal_ctg") || StrEqual(currentMap, "nt_sentinel_ctg") || StrEqual(currentMap, "nt_bullet_tdm") || StrEqual(currentMap, "nt_zaibatsu_ctg"))
		SetConVarInt(convar_nt_dm_enabled, 1); // we enable the convar for TDM automatically on these maps
	else
		SetConVarInt(convar_nt_dm_enabled, 0);
}

public OnMapStart()
{
	//InitArray();
	if(GetConVarBool(convar_nt_dm_enabled))
	{
		ServerCommand("sm plugins unload nt_assist.smx");
	}
}

public OnConfigsExecutedHook(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	if (!GetConVarBool(convar_nt_dm_enabled))
	{
		StopDeathMatch();
		g_DMStarted = false;
		PrintToChatAll("Team DeathMatch stopped!");
		PrintToServer("Team DeathMatch stopped!");
		ServerCommand("neo_restart_this 1");
	}
	if (GetConVarBool(convar_nt_dm_enabled))
	{
		StopDeathMatch();
		
		CreateTimer(5.0, StartDeatchmatch);   // needs a timer of 5sec to properly start... very weird, I know. -glub
		//g_DMStarted = true;
		PrintToChatAll("Team DeathMatch started!");
		PrintToServer("Team DeathMatch started!");
		//GameRules_SetPropFloat("m_fRoundTimeLeft", 10.0);    
		//GameRules_SetProp("m_iGameState", 1);    // if gamestate change from 0 to 1 and neo_restart_this 1, CTG back to normal, no respawn
		//ServerCommand("neo_restart_this 1");
	}
}


public OnChangePlayerRandomSpawnsCvar(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	if (GetConVarBool(convar_nt_dm_randomplayerspawns))
	{
		g_RandomPlayerSpawns = true;
		PrintToChatAll("Random player spawns enabled!");
	}
	if (!GetConVarBool(convar_nt_dm_randomplayerspawns))
	{
		g_RandomPlayerSpawns = false;
		PrintToChatAll("Random player spawns disabled!");
	}
}


public Action:StartDeatchmatch(Handle:timer)
{
	StartDeathmatch();
}


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

public Action:CheckGameStateGR(client, args)
{ 
	new statevalue = GameRules_GetProp("m_iGameState");
	PrintToServer("GR m_iGameState is %i", statevalue);
	PrintToConsole(client, "GR m_iGameState is %i", statevalue);
	return Plugin_Handled;
}

public CheckGamestate2()
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

public CheckGameType2()
{ 
	new typevalue = GameRules_GetProp("m_iGameType");
	PrintToServer("In GR m_iGameType is %i", typevalue);
}


public Action:CheckGameStateProxy(client, args)
{
	CheckGamestate3();
	return Plugin_Handled;
}

public CheckGamestate3()  //through proxy
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

public StartDeathmatch() 
{
	g_DMStarted = true; 
	new timeLimit = GetConVarInt(convar_nt_dm_timelimit);
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
}


public StopDeathMatch()
{
	InitArray();
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
		new attackerTeam = GetClientTeam(attacker);   // error Native "GetClientTeam" reported: Client index 0 is invalid when suiciding with world

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
			
			if(g_RandomPlayerSpawns == true)
			{
				if(g_PlayerCoordsKeyPresent == true)  //if map name is found in the keyvalue file of the same name
				{

				GenerateRandomInt();  										//RANDOM COORDINATES
				//if(randomint == randomint_allowing_array)
				
				do
				{
					if((randomint == randomint_prev) || randomint_allowing_array[randomint] != 0)
					{
						GenerateRandomInt();
					}
					randomint_prev = randomint;  //storing current randomint 
					
					GenerateRandomInt();
				}while(randomint_allowing_array[randomint] != 0);
				
				
				
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
				
				CreateTimer(12.0, ClearLock);

				#if DEBUG > 1
				PrintToServer("SPAWNING: randomint=%d, randomint_allowing_array=%d origin %f %f %f coordsarray: %f %f %f", randomint, randomint_allowing_array[randomint], NewOrigin[0], NewOrigin[1], NewOrigin[2], coordinates_array[randomint][0], coordinates_array[randomint][1], coordinates_array[randomint][2]);
				PrintToServer("------");
				#endif
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
	randomint = GetRandomInt(0, lines -1);
	return randomint;
}

void InitArray()
{
	decl String:CurrentMap[64];
	GetCurrentMap(CurrentMap, 64);		
	
	//new String:MapConfig[PLATFORM_MAX_PATH];
	//Format(MapConfig, sizeof(MapConfig), "config/%s.txt", Ma );
	
	
	static String:file[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, file, sizeof(file), "configs/%s.txt", CurrentMap);
	new Handle:kv = CreateKeyValues("Coordinates");
	do
	{
		if(!FileToKeyValues(kv, file))
		{
			PrintToServer("%s.txt not found!", CurrentMap);
			break;
		}
		if(!KvJumpToKey(kv, "player coordinates"))
		{
			PrintToServer("player coordinates key was not found in the keyvalues file!");
			g_PlayerCoordsKeyPresent = false;
			break;
		}
		else{ g_PlayerCoordsKeyPresent = true; }

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
		#if DEBUG > 1
		PrintToServer("lines : %d", lines);
		#endif
		
		
		
		
		
		
		KvRewind(kv);
	} while (false);
	CloseHandle(kv);
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

// in case we use on-map basis plugin load, unload the plugin after this map
public OnMapEnd()
{
	g_DMStarted = false;
	ServerCommand("sm_nt_dm_enabled 0");
	//ServerCommand("sm plugins unload disabled/nt_deathmatch-glub.smx");
	ServerCommand("sm plugins load nt_assist.smx");
}
