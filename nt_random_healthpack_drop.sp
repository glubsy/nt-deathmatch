#include <sourcemod>
#include <sdktools>
#include <sdktools_sound>
#include <sdkhooks>
#define MAXENTITIES 2048
#define MAX_FILE_LEN 80
#define PLUGIN_VERSION "2.8"
#define DEBUG 0

public Plugin:myinfo = 
{
	name = "Drop Random Healthpack",
	author = "Darkranger & glub",
	description = "a dead player drops random a Healthpack",
	version = PLUGIN_VERSION,
	url = ""
}

static const String:g_HealthKit_Model[2][] = { "models/items/healthkit.mdl", "models/nt/a_lil_tiger.mdl" }
new String:soundName[MAX_FILE_LEN]
new Handle:HealthKitDropTimer[MAXENTITIES+1] = INVALID_HANDLE
new String:g_HealthKit_Sound[] = "items/smallmedkit1.wav";
new String:g_HealthKitdenied_Sound[] = "items/medshotno1.wav";
new g_HealthKit_Skin[2] = { 0, 0 }
new Handle:kithealth = INVALID_HANDLE
new Handle:kithealthmax = INVALID_HANDLE
new Handle:kithealthmaxvar = INVALID_HANDLE
new Handle:kittime = INVALID_HANDLE
new Handle:kitcount = INVALID_HANDLE
new Handle:dropmodel = INVALID_HANDLE
new Handle:messagedropenabled = INVALID_HANDLE
new Handle:messagepickupenabled = INVALID_HANDLE
new Handle:PickUpSoundName = INVALID_HANDLE
new Handle:UseOwnPickUpSound = INVALID_HANDLE
new kitcountcounter = 0
new deadkitammount = 0 
ConVar g_healthkitenabled;

public OnPluginStart()
{	
	CreateConVar("nt_drop_random_health_version", PLUGIN_VERSION, "Healthpack drop Plugin Version", FCVAR_DONTRECORD|FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY)
	SetConVarString(FindConVar("nt_drop_random_health_version"), PLUGIN_VERSION)
	g_healthkitenabled = CreateConVar("nt_healthkitdrop", "0", "Enables or disables random healthkit drops on death", FCVAR_PLUGIN);
	kithealth = CreateConVar("nt_drop_health_amount", "30", "<#> = Amount of HP to add to a player when pick up a Healthpack", FCVAR_PLUGIN, true, 5.0, true, 300.0)
	kithealthmax = CreateConVar("nt_drop_health_maximum", "100", "max. Amount of Health a Player can have to pickup a Healthpack", FCVAR_PLUGIN, true, 100.0, true, 600.0)
	kithealthmaxvar = CreateConVar("nt_drop_health_maximum_var", "0", "what happens when max. Health is reached: 0 = delete Healthpack , 1 = Healthpack will dropped from next dead player , 2 = do nothing with Healthpack", FCVAR_PLUGIN, true, 0.0, true, 2.0)
	kittime = CreateConVar("nt_drop_health_lifetime", "30", "<#> = number of seconds a dropped Healthpackage stays on the map", FCVAR_PLUGIN, true, 10.0, true, 180.0)
	kitcount = CreateConVar("nt_drop_health_counter", "0", "drop a Package every X deaths! 0 = disable - when enabled random drop is disabled", FCVAR_PLUGIN, true, 0.0, true, 60.0)
	dropmodel = CreateConVar("nt_drop_model", "0", "Model to use: 0=hl2_kit 1=lil_tiger", FCVAR_PLUGIN, true, 0.0, true, 6.0)
	messagedropenabled    = CreateConVar("nt_drop_message_dropped",    "0", "Enable(1) or disable(0) message when a Pack was dropped", FCVAR_PLUGIN)
	messagepickupenabled    = CreateConVar("nt_drop_message_pickup",    "1", "Enable (1) or disable(0) message when Pickup a Pack", FCVAR_PLUGIN)
	PickUpSoundName = CreateConVar("nt_drop_pickup_sound", "medshot4.wav", "Own Sound played when Pickup the Pack(must be MP3 and in sound folder!)")
	UseOwnPickUpSound    = CreateConVar("nt_drop_own_pickup_sound",    "0", "Enable (1) or disable(0) your own PickUp Soundfile", FCVAR_PLUGIN)
	AutoExecConfig(true, "nt_drop_random_health", "nt_drop_random_health")
	HookEvent("player_death", OnPlayerDeath, EventHookMode_Pre)
}

public OnMapStart()
{
//	AddFileToDownloadsTable("models/items/medkit_large.dx80.vtx")
	PrecacheModel(g_HealthKit_Model[0],true)
	PrecacheModel(g_HealthKit_Model[1],true)
//	PrecacheModel(g_HealthKit_Model[2],true)

	PrecacheSound(g_HealthKit_Sound, true)
	PrecacheSound(g_HealthKitdenied_Sound, true)
	kitcountcounter = 0
	deadkitammount = 0
	
/*	GetConVarString(PickUpSoundName, soundName, MAX_FILE_LEN)
	decl String:buffer[MAX_FILE_LEN]
	PrecacheSound(soundName, true)			// custom sound file, not needed
	Format(buffer, sizeof(buffer), "sound/%s", soundName)
	AddFileToDownloadsTable(buffer)
*/
	// init random number generator
	SetRandomSeed(RoundToFloor(GetEngineTime()));
}


public Action:OnPlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(GetConVarBool(g_healthkitenabled))
	{
		// LOG MESSAGE IF MAX. ENTITIES REACHED
		if (GetEntityCount() >= GetMaxEntities() - 64)
		{
			LogMessage("too many Entities spawned %i : max. is %i ( -64 )", GetEntityCount(), GetMaxEntities())
			SetFailState("Plugin unloaded because of too much entities!")
		}

		if ((GetConVarInt(kitcount) == 0) && (GetEntityCount() < GetMaxEntities() - 64))
		{
			if (deadkitammount == 1)
			{
				new client = GetClientOfUserId(GetEventInt(event, "userid"))
				new Float:deathorigin[3]
				GetClientAbsOrigin(client,deathorigin)
				deathorigin[2] += 20.0 // above
				//deathorigin[1] -= 0.0 // + = left from front
				deathorigin[0] -= 10.0 // + = front
				new healthkit = CreateEntityByName("prop_physics_override")
				//SetEntityModel(healthkit,g_HealthKit_Model[GetConVarInt(dropmodel)])  //out-glub
				DispatchKeyValue(healthkit, "model", g_HealthKit_Model[GetConVarInt(dropmodel)]); //fixed-glub
				//SetEntProp(healthkit, Prop_Send, "m_nSkin", g_HealthKit_Skin[0])  //out-glub
				DispatchKeyValueVector(healthkit, "Origin", deathorigin); //fixed-glub
				if (DispatchSpawn(healthkit))
				{
					SetEntProp(healthkit, Prop_Send, "m_usSolidFlags",  136)
					SetEntProp(healthkit, Prop_Send, "m_CollisionGroup", 11)
				}
				TeleportEntity(healthkit, deathorigin, NULL_VECTOR, NULL_VECTOR) //out-glub
				SDKHook(healthkit, SDKHook_Touch, OnHealthKitTouched)
				HealthKitDropTimer[healthkit] = CreateTimer(GetConVarFloat(kittime), RemoveDroppedHealthKit, healthkit, TIMER_FLAG_NO_MAPCHANGE)
				if (GetConVarInt(messagedropenabled) == 1)
				{
					PrintToServer("Dropped healthpack!")
				}
				deadkitammount = 0
				return Plugin_Continue		
			}
				
			//new randomplayercount = 12+GetClientCount()
			//new randomdeath = GetURandomInt() % randomplayercount  // I don't like this -glub
			new randomdeath = GetRandomInt(0, 10);
			#if DEBUG
			PrintToChatAll("randomdeath random num= %i", randomdeath);
			#endif
			if(randomdeath <= 3)
			{
				new client = GetClientOfUserId(GetEventInt(event, "userid"))
				new Float:deathorigin[3]
				GetClientAbsOrigin(client,deathorigin)
				deathorigin[2] += 30.0 // above
				//deathorigin[1] -= 0.0 // + = left from front
				deathorigin[0] -= 40.0 // + = front
				new healthkit = CreateEntityByName("prop_physics_override")
				//SetEntityModel(healthkit,g_HealthKit_Model[GetConVarInt(dropmodel)])   //out-glub
				DispatchKeyValue(healthkit, "model", g_HealthKit_Model[GetConVarInt(dropmodel)]); //fixed-glub
				//SetEntProp(healthkit, Prop_Send, "m_nSkin", g_HealthKit_Skin[0]) //out-glub
				DispatchKeyValueVector(healthkit, "Origin", deathorigin); //fixed-glub
				if (DispatchSpawn(healthkit))
				{
					SetEntProp(healthkit, Prop_Send, "m_usSolidFlags",  136)
					SetEntProp(healthkit, Prop_Send, "m_CollisionGroup", 11)
				}
				TeleportEntity(healthkit, deathorigin, NULL_VECTOR, NULL_VECTOR)
				SDKHook(healthkit, SDKHook_StartTouch, OnHealthKitTouched)
				HealthKitDropTimer[healthkit] = CreateTimer(GetConVarFloat(kittime), RemoveDroppedHealthKit, healthkit, TIMER_FLAG_NO_MAPCHANGE)
				if (GetConVarInt(messagedropenabled) == 1)
				{
					PrintToServer("Dropped healthpack!")
				}	
				return Plugin_Continue
			}
		}
		kitcountcounter++
		if ((GetConVarInt(kitcount) == kitcountcounter) && (GetEntityCount() < GetMaxEntities() - 64))
		{
			new client = GetClientOfUserId(GetEventInt(event, "userid"))
			new Float:deathorigin[3]
			GetClientAbsOrigin(client,deathorigin)
			deathorigin[2] += 20.0 // above
			//deathorigin[1] -= 0.0 // + = left from front
			deathorigin[0] -= 10.0 // + = front
			new healthkit = CreateEntityByName("prop_physics_override")
			//SetEntityModel(healthkit,g_HealthKit_Model[GetConVarInt(dropmodel)])
			DispatchKeyValue(healthkit, "model", g_HealthKit_Model[GetConVarInt(dropmodel)]); //fixed-glub
			//SetEntProp(healthkit, Prop_Send, "m_nSkin", g_HealthKit_Skin[0])   //out-glub
			DispatchKeyValueVector(healthkit, "Origin", deathorigin); //fixed-glub
			//TeleportEntity(healthkit, deathorigin, NULL_VECTOR, NULL_VECTOR)
			if (DispatchSpawn(healthkit))
			{
				SetEntProp(healthkit, Prop_Send, "m_usSolidFlags",  136)  //was 152 -glub
				SetEntProp(healthkit, Prop_Send, "m_CollisionGroup", 11)
			}
			SDKHook(healthkit, SDKHook_StartTouch, OnHealthKitTouched)
			HealthKitDropTimer[healthkit] = CreateTimer(GetConVarFloat(kittime), RemoveDroppedHealthKit, healthkit, TIMER_FLAG_NO_MAPCHANGE)
			if (GetConVarInt(messagedropenabled) == 1)
			{
				PrintToServer("Dropped healthpack!")
			}	
			kitcountcounter = 0
			return Plugin_Continue
		}
	}
	return Plugin_Continue
}

public Action:OnHealthKitTouched(healthkit, client)
{
	if(client > 0 && client <= GetMaxClients() && healthkit > 0 && !IsFakeClient(client) && IsValidEntity(client) && IsClientInGame(client) && IsPlayerAlive(client) && IsValidEdict(healthkit))
	{
		new Float:coords_KilledEnt[3];
		GetEntPropVector(healthkit, Prop_Send, "m_vecOrigin", coords_KilledEnt);
		
		new health = GetClientHealth(client)
		new healthkitadd = GetConVarInt(kithealth)
		new healthkitmax = GetConVarInt(kithealthmax)
		if (health < healthkitmax)
		{
			new healthtemp = 0
			if((health + healthkitadd) > healthkitmax)
			{
				healthtemp = healthkitmax
			}
			else
			{
				healthtemp = health + healthkitadd
			}
			SetEntityHealth(client,healthtemp)
			//SetEntProp(client, Prop_Data, "m_iHealth", healthtemp, 1)  //-glub
			
			KillHealthKitTimer(healthkit)
			if (GetConVarInt(UseOwnPickUpSound) == 0)
			{
				PlayPickUpSound(client, coords_KilledEnt)
			}
			else
			{
				//EmitSoundToClient(client,soundName)
				ClientCommand(client, "play *%s" , soundName)  
			}
			
			//RemoveEdict(healthkit)  //crash! -glub
			AcceptEntityInput(healthkit, "kill");
			
			if (GetConVarInt(messagepickupenabled) == 1)
			{
				PrintToChat(client, "You picked up a healthkit for %i HP.", GetConVarInt(kithealth))
			}	
		}
		else
		{
			if (GetConVarInt(kithealthmaxvar) == 0)
			{
				KillHealthKitTimer(healthkit)
				//RemoveEdict(healthkit)  //crash! -glub
				AcceptEntityInput(healthkit, "kill");
				PlayDeniedSound(client, coords_KilledEnt) //out -glub
				//if (GetConVarInt(messagepickupenabled) == 1)
				//{
				//	PrintToChat(client, "You have too much Health - HealthPack destroyed!")
				//}	
			}
			if (GetConVarInt(kithealthmaxvar) == 1)
			{
				KillHealthKitTimer(healthkit)
				AcceptEntityInput(healthkit, "kill");
				//RemoveEdict(healthkit) //crash! -glub
				PlayDeniedSound(client, coords_KilledEnt) //out -glub
				//if (GetConVarInt(messagepickupenabled) == 1)
				//{
				//	PrintToChat(client, "You have too much Health. The next dead Player will drop a new one.")
				//}	
				deadkitammount = 1
			}
			if (GetConVarInt(kithealthmaxvar) == 2)
			{
				//if (GetConVarInt(messagepickupenabled) == 1)
				//{
				//	PrintCenterText(client, "You have too much Health. You cant pick it up!")
				//}
			}	
		}	
	}
	return Plugin_Handled
}

stock KillHealthKitTimer(healthkit)
{
	if(HealthKitDropTimer[healthkit] != INVALID_HANDLE)
	{
		CloseHandle(HealthKitDropTimer[healthkit])
	}
	HealthKitDropTimer[healthkit] = INVALID_HANDLE
}

stock Action:PlayPickUpSound(client, Float:coords[3])
{
	//EmitSoundToClient(client, g_HealthKit_Sound, SOUND_FROM_PLAYER,SNDCHAN_AUTO,SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL)
	EmitSoundToAll(g_HealthKit_Sound, SOUND_FROM_WORLD, SNDCHAN_ITEM, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0, SNDPITCH_NORMAL, -1, coords);
	
	//ClientCommand(client, "playgamesound WallHealth.Start"); //this works if all else fails, only to player though
}

stock PlayDeniedSound(client, Float:coords[3])
{
	//EmitSoundToClient(client, g_HealthKitdenied_Sound, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.6, SNDPITCH_NORMAL)
	EmitSoundToAll(g_HealthKitdenied_Sound, SOUND_FROM_WORLD, SNDCHAN_ITEM, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.6, SNDPITCH_NORMAL, -1, coords);
	#if DEBUG > 0
	PrintToChat(client, "Emitted denied sound effect");
	#endif
}

public Action:RemoveDroppedHealthKit(Handle:timer, any:healthkit)
{
	HealthKitDropTimer[healthkit] = INVALID_HANDLE
	if(IsValidEdict(healthkit))
	{
		AcceptEntityInput(healthkit, "kill");
		//RemoveEdict(healthkit)  //crash! -glub
	}
	return Plugin_Handled
}
