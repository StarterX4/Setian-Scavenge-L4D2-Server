#include <sourcemod>
#include <sdktools>
#include <builtinvotes>
#include <l4d2_weapon_stocks>
#include <colors>
#include <left4dhooks>
#undef REQUIRE_PLUGIN
#include <readyup>
#include <pause>
#include <l4d2_hybrid_scoremod>
#include <l4d2_scoremod>
#include <l4d2_health_temp_bonus>
#include <l4d_tank_control_eq>
#include <l4d2_boss_percents>

#define REQUIRE_PLUGIN

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION	"3.5.4"

public Plugin myinfo = 
{
	name = "Hyper-V HUD Manager",
	author = "Visor, Forgetest",
	description = "Provides different HUDs for spectators",
	version = PLUGIN_VERSION,
	url = "https://github.com/Target5150/MoYu_Server_Stupid_Plugins"
};

// ======================================================================
//  Macros
// ======================================================================
#define SPECHUD_DRAW_INTERVAL   0.5

#define ZOMBIECLASS_NAME(%0) (L4D2SI_Names[(%0)])

#define CLAMP(%0,%1,%2) (((%0) > (%2)) ? (%2) : (((%0) < (%1)) ? (%1) : (%0)))
#define MAX(%0,%1) (((%0) > (%1)) ? (%0) : (%1))
#define MIN(%0,%1) (((%0) < (%1)) ? (%0) : (%1))

// ToPercent(int var, int varmax): float
#define ToPercent(%0,%1) ((%0) < 1 ? 0.0 : (100.0 * (%0) / (%1)))

#define TEAM_NONE       0
#define TEAM_SPECTATOR  1
#define TEAM_SURVIVOR   2
#define TEAM_INFECTED   3

// ======================================================================
//  Plugin Vars
// ======================================================================
enum L4D2Gamemode
{
	L4D2Gamemode_None,
	L4D2Gamemode_Versus,
	L4D2Gamemode_Scavenge
};
L4D2Gamemode g_Gamemode;

enum L4D2SI 
{
	ZC_None,
	ZC_Smoker,
	ZC_Boomer,
	ZC_Hunter,
	ZC_Spitter,
	ZC_Jockey,
	ZC_Charger,
	ZC_Witch,
	ZC_Tank
};
//L4D2SI storedClass[MAXPLAYERS+1];

static const char L4D2SI_Names[][] = 
{
	"None",
	"Smoker",
	"Boomer",
	"Hunter",
	"Spitter",
	"Jockey",
	"Charger",
	"Witch",
	"Tank"
};

enum SurvivorCharacter
{
	SC_NONE=-1,
	SC_NICK=0,
	SC_ROCHELLE,
	SC_COACH,
	SC_ELLIS,
	SC_BILL,
	SC_ZOEY,
	SC_LOUIS,
	SC_FRANCIS
};

// Game Var
ConVar survivor_limit, z_max_player_zombies, versus_boss_buffer, mp_gamemode, mp_roundlimit, sv_maxplayers, tank_burn_duration, pain_pills_decay_rate;
int iSurvivorLimit, iMaxPlayerZombies, iMaxPlayers, iRoundLimit;
float fVersusBossBuffer, fTankBurnDuration, fPainPillsDecayRate;

// Network Var
ConVar cVarMinUpdateRate, cVarMaxUpdateRate, cVarMinInterpRatio, cVarMaxInterpRatio;
float fMinUpdateRate, fMaxUpdateRate, fMinInterpRatio, fMaxInterpRatio;

// Plugin Cvar
ConVar l4d_tank_percent, l4d_witch_percent, hServerNamer, l4d_ready_cfg_name;

// Plugin Var
char sReadyCfgName[64], sHostname[64];
bool bRoundLive, bPendingArrayRefresh;
int iSurvivorArray[MAXPLAYERS/2+1], iInfectedArray[MAXPLAYERS/2+1];

// Plugin Handle
ArrayList hSpecHudViewers, hTankHudViewers;

// Boss Spawn Scheme
StringMap hFirstTankSpawningScheme, hSecondTankSpawningScheme;		// eq_finale_tanks (Zonemod, Acemod, etc.)
StringMap hFinaleExceptionMaps;										// finale_tank_blocker (Promod and older?)
StringMap hCustomTankScriptMaps;									// Handled by this plugin

// Flow Bosses
int iTankCount, iWitchCount;
bool bRoundHasFlowTank, bRoundHasFlowWitch, bFlowTankActive;

// Score & Scoremod
//int iFirstHalfScore;
bool bScoremod, bHybridScoremod, bNextScoremod;
int iMaxDistance;

// Tank Control EQ
bool bTankSelection;

// Hud Toggle & Hint Message
bool bSpecHudActive[MAXPLAYERS+1], bTankHudActive[MAXPLAYERS+1];
bool bSpecHudHintShown[MAXPLAYERS+1], bTankHudHintShown[MAXPLAYERS+1];

bool isPassing = false;

/**********************************************************************************************/

// ======================================================================
//  Plugin Start
// ======================================================================
public void OnPluginStart()
{
	(	survivor_limit			= FindConVar("survivor_limit")			).AddChangeHook(OnGameConVarChanged);
	(	z_max_player_zombies	= FindConVar("z_max_player_zombies")	).AddChangeHook(OnGameConVarChanged);
	(	versus_boss_buffer		= FindConVar("versus_boss_buffer")		).AddChangeHook(OnGameConVarChanged);
	(	mp_gamemode				= FindConVar("mp_gamemode")				).AddChangeHook(OnGameConVarChanged);
	(	mp_roundlimit			= FindConVar("mp_roundlimit")			).AddChangeHook(OnGameConVarChanged);
	(	sv_maxplayers			= FindConVar("sv_maxplayers")			).AddChangeHook(OnGameConVarChanged);
	(	tank_burn_duration		= FindConVar("tank_burn_duration")		).AddChangeHook(OnGameConVarChanged);
	(	pain_pills_decay_rate	= FindConVar("pain_pills_decay_rate")	).AddChangeHook(OnGameConVarChanged);

	(	cVarMinUpdateRate		= FindConVar("sv_minupdaterate")			).AddChangeHook(OnNetworkConVarChanged);
	(	cVarMaxUpdateRate		= FindConVar("sv_maxupdaterate")			).AddChangeHook(OnNetworkConVarChanged);
	(	cVarMinInterpRatio		= FindConVar("sv_client_min_interp_ratio")	).AddChangeHook(OnNetworkConVarChanged);
	(	cVarMaxInterpRatio		= FindConVar("sv_client_max_interp_ratio")	).AddChangeHook(OnNetworkConVarChanged);
	
	FillBossPercents();
	FillServerNamer();
	FillReadyConfig();
	
	InitTankSpawnSchemeTrie();
	
	RegConsoleCmd("sm_spechud", ToggleSpecHudCmd);
	RegConsoleCmd("sm_tankhud", ToggleTankHudCmd);
	
	HookEvent("round_start",			view_as<EventHook>(Event_RoundStart), EventHookMode_PostNoCopy);
	HookEvent("player_death",			Event_PlayerDeath);
	HookEvent("witch_killed",			Event_WitchDeath);
	HookEvent("player_team",			Event_PlayerTeam);
	
	GetGameCvars();
	GetNetworkCvars();
	
	for (int i = 1; i <= MaxClients; ++i)
	{
		bSpecHudActive[i] = false;
		bSpecHudHintShown[i] = false;
		bTankHudActive[i] = true;
		bTankHudHintShown[i] = false;
	}
	
	hSpecHudViewers = new ArrayList();
	hTankHudViewers = new ArrayList();
	
	bPendingArrayRefresh = true;
	
	CreateTimer(SPECHUD_DRAW_INTERVAL, HudDrawTimer, _, TIMER_REPEAT);
}

/**********************************************************************************************/

// ======================================================================
//  ConVar Maintenance
// ======================================================================
void GetGameCvars()
{
	iSurvivorLimit		= survivor_limit.IntValue;
	iMaxPlayerZombies	= z_max_player_zombies.IntValue;
	fVersusBossBuffer	= versus_boss_buffer.FloatValue;
	GetCurrentGameMode();
	iRoundLimit			= CLAMP(mp_roundlimit.IntValue, 1, 5);
	iMaxPlayers			= sv_maxplayers.IntValue;
	fTankBurnDuration	= tank_burn_duration.FloatValue;
	fPainPillsDecayRate	= pain_pills_decay_rate.FloatValue;
}

void GetNetworkCvars()
{
	fMinUpdateRate	= cVarMinUpdateRate.FloatValue;
	fMaxUpdateRate	= cVarMaxUpdateRate.FloatValue;
	fMinInterpRatio	= cVarMinInterpRatio.FloatValue;
	fMaxInterpRatio	= cVarMaxInterpRatio.FloatValue;
}

void GetCurrentGameMode()
{
	char sGameMode[32];
	GetConVarString(mp_gamemode, sGameMode, sizeof(sGameMode));
	
	if (strcmp(sGameMode, "scavenge") == 0)
	{
		g_Gamemode = L4D2Gamemode_Scavenge;
	}
	else if (strcmp(sGameMode, "versus") == 0
		|| strcmp(sGameMode, "mutation12") == 0) // realism versus
	{
		g_Gamemode = L4D2Gamemode_Versus;
	}
	else
	{
		g_Gamemode = L4D2Gamemode_None; // Unsupported
	}
}

public void OnTankPassStart()
{
    isPassing = true;
}

public void OnTankPassEnd()
{
    isPassing = false;
}

// ======================================================================
//  Dependency Maintenance
// ======================================================================
void FillBossPercents()
{
	l4d_tank_percent	= FindConVar("l4d_tank_percent");
	l4d_witch_percent	= FindConVar("l4d_witch_percent");
}

void FillServerNamer()
{
	ConVar convar = null;
	if ((convar = FindConVar("l4d_ready_server_cvar")) != null)
	{
		char buffer[64];
		convar.GetString(buffer, sizeof buffer);
		convar = FindConVar(buffer);
	}
	
	if (convar == null)
	{
		convar = FindConVar("hostname");
	}
	
	if (hServerNamer == null)
	{
		hServerNamer = convar;
	}
	else if (hServerNamer != convar)
	{
		hServerNamer.RemoveChangeHook(OnHostnameChanged);
		hServerNamer = convar;
	}
	
	hServerNamer.AddChangeHook(OnHostnameChanged);
	hServerNamer.GetString(sHostname, sizeof(sHostname));
	
	delete convar;
}

void FillReadyConfig()
{
	if (l4d_ready_cfg_name != null || (l4d_ready_cfg_name = FindConVar("l4d_ready_cfg_name")) != null)
		l4d_ready_cfg_name.GetString(sReadyCfgName, sizeof(sReadyCfgName));
}

void FindScoreMod()
{
	bScoremod = LibraryExists("l4d2_scoremod");
	bHybridScoremod = LibraryExists("l4d2_hybrid_scoremod") || LibraryExists("l4d2_hybrid_scoremod_zone");
	bNextScoremod = LibraryExists("l4d2_health_temp_bonus");
}

void FindTankSelection()
{
	bTankSelection = (GetFeatureStatus(FeatureType_Native, "GetTankSelection") != FeatureStatus_Unknown);
}

// ======================================================================
//  Dependency Monitor
// ======================================================================
public void OnGameConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	GetGameCvars();
}

public void OnNetworkConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	GetNetworkCvars();
}

public void OnHostnameChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	FillServerNamer();
}

public void OnAllPluginsLoaded()
{
	FindScoreMod();
	
	FillBossPercents();
	FillServerNamer();
	FillReadyConfig();
	
	FindTankSelection();
}

public void OnLibraryAdded(const char[] name)
{
	FindScoreMod();
	FillBossPercents();
}

public void OnLibraryRemoved(const char[] name)
{
	FindScoreMod();
	FillBossPercents();
}

// ======================================================================
//  Bosses Caching
// ======================================================================
void BuildCustomTrieEntries()
{
	// Haunted Forest 3
	hCustomTankScriptMaps.SetValue("hf03_themansion", true);
}

void InitTankSpawnSchemeTrie()
{
	hFirstTankSpawningScheme	= new StringMap();
	hSecondTankSpawningScheme	= new StringMap();
	hFinaleExceptionMaps		= new StringMap();
	hCustomTankScriptMaps		= new StringMap();
	
	RegServerCmd("tank_map_flow_and_second_event",	SetMapFirstTankSpawningScheme);
	RegServerCmd("tank_map_only_first_event",		SetMapSecondTankSpawningScheme);
	RegServerCmd("finale_tank_default",				SetFinaleExceptionMap);
	
	BuildCustomTrieEntries();
}

public Action SetMapFirstTankSpawningScheme(int args)
{
	char mapname[64];
	GetCmdArg(1, mapname, sizeof(mapname));
	hFirstTankSpawningScheme.SetValue(mapname, true);
}

public Action SetMapSecondTankSpawningScheme(int args)
{
	char mapname[64];
	GetCmdArg(1, mapname, sizeof(mapname));
	hSecondTankSpawningScheme.SetValue(mapname, true);
}

public Action SetFinaleExceptionMap(int args)
{
	char mapname[64];
	GetCmdArg(1, mapname, sizeof(mapname));
	hFinaleExceptionMaps.SetValue(mapname, true);
}

/**********************************************************************************************/

// ======================================================================
//  Forwards
// ======================================================================
public void OnClientDisconnect(int client)
{
	bSpecHudHintShown[client] = false;
	bTankHudHintShown[client] = false;
}

public void OnMapStart() { bRoundLive = false; }
public void OnRoundIsLive()
{
	FillReadyConfig();
	
	bRoundLive = true;
	bPendingArrayRefresh = true;
	
	GetCurrentGameMode();
	
	//for (int i = 1; i <= MaxClients; ++i) storedClass[i] = ZC_None;
	
	if (g_Gamemode == L4D2Gamemode_Versus)
	{
		bRoundHasFlowTank = RoundHasFlowTank();
		bRoundHasFlowWitch = RoundHasFlowWitch();
		bFlowTankActive = bRoundHasFlowTank;
		
		iMaxDistance = L4D_GetVersusMaxCompletionScore() / 4 * iSurvivorLimit;
		
		iTankCount = 0;
		iWitchCount = 0;
		
		if (l4d_tank_percent != null && l4d_tank_percent.BoolValue)
		{
			iTankCount = 1;
			
			char mapname[64];
			bool dummy;
			GetCurrentMap(mapname, sizeof(mapname));
			
			// TODO: individual plugin served as an interface to tank counts?
			if (hCustomTankScriptMaps.GetValue(mapname, dummy)) iTankCount += 1;
			
			else if (!IsDarkCarniRemix() && L4D_IsMissionFinalMap())
			{
				iTankCount = 3
							- view_as<int>(hFirstTankSpawningScheme.GetValue(mapname, dummy))
							- view_as<int>(hSecondTankSpawningScheme.GetValue(mapname, dummy))
							- view_as<int>(hFinaleExceptionMaps.Size > 0 && !hFinaleExceptionMaps.GetValue(mapname, dummy))
							- view_as<int>(IsStaticTankMap());
			}
		}
		
		if (l4d_witch_percent != null && l4d_witch_percent.BoolValue)
		{
			iWitchCount = 1;
		}
	}
}

//public void L4D2_OnEndVersusModeRound_Post() { if (!InSecondHalfOfRound()) iFirstHalfScore = L4D_GetTeamScore(GetRealTeam(0) + 1); }

// ======================================================================
//  Events
// ======================================================================
public void Event_RoundStart() { bRoundLive = false; bPendingArrayRefresh = true; }

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client || !IsInfected(client)) return;
	
	if (GetInfectedClass(client) == ZC_Tank)
	{
		if (iTankCount > 0) iTankCount--;
		if (!RoundHasFlowTank()) bFlowTankActive = false;
	}
}

public void Event_WitchDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (iWitchCount > 0) iWitchCount--;
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client) return;
	
	int team = event.GetInt("team");
	
	if (team == TEAM_NONE) // Player disconnecting
	{
		bSpecHudActive[client] = false;
		bTankHudActive[client] = true;
	}
	
	bPendingArrayRefresh = true;
	
	//if (team == 3) storedClass[client] = ZC_None;
}

/**********************************************************************************************/

// ======================================================================
//  Player Arrays & Custom Sorting
// ======================================================================
stock void BuildPlayerArrays()
{
	hSpecHudViewers.Clear();
	hTankHudViewers.Clear();
	
	int survivorCount = 0, infectedCount = 0;
	for (int client = 1; client <= MaxClients; ++client) 
	{
		if (!IsClientInGame(client)) continue;
		
		switch (GetClientTeam(client))
		{
			case TEAM_SPECTATOR:
			{
				if (!IsFakeClient(client))
				{
					if (bSpecHudActive[client])
						hSpecHudViewers.Push(client);
						
					else if (bTankHudActive[client])
						hTankHudViewers.Push(client);
				}
			}
			case TEAM_SURVIVOR:
			{
				if (survivorCount < iSurvivorLimit)
					iSurvivorArray[survivorCount++] = client;
			}
			case TEAM_INFECTED:
			{
				if (infectedCount < iMaxPlayerZombies)
					iInfectedArray[infectedCount++] = client;
					
				if (!IsFakeClient(client) && bTankHudActive[client])
					hTankHudViewers.Push(client);
			}
		}
	}
	
	iSurvivorArray[survivorCount] = 0;
	iInfectedArray[infectedCount] = 0;
	
	SortCustom1D(iSurvivorArray, survivorCount, SortSurvArray);
}

public int SortSurvArray(int elem1, int elem2, const int[] array, Handle hndl)
{
	SurvivorCharacter sc1 = GetFixedSurvivorCharacter(elem1);
	SurvivorCharacter sc2 = GetFixedSurvivorCharacter(elem2);
	
	if (sc1 > sc2) { return 1; }
	else if (sc1 < sc2) { return -1; }
	else { return 0; }
}

// ======================================================================
//  HUD Command Callbacks
// ======================================================================
public Action ToggleSpecHudCmd(int client, int args) 
{
	if (GetClientTeam(client) != TEAM_SPECTATOR)
		return;
	
	if (bSpecHudActive[client])
	{
		bSpecHudActive[client] = false;
		
		int index = hSpecHudViewers.FindValue(client);
		if (index != -1)
			hSpecHudViewers.Erase(index);
		
		if (bTankHudActive[client])
		{
			index = hTankHudViewers.FindValue(client);
			if (index == -1)
				hTankHudViewers.Push(client);
		}
	}
	else
	{
		bSpecHudActive[client] = true;
		
		int index = hSpecHudViewers.FindValue(client);
		if (index == -1)
			hSpecHudViewers.Push(client);
			
		if (bTankHudActive[client])
		{
			index = hTankHudViewers.FindValue(client);
			if (index != -1)
				hTankHudViewers.Erase(index);
		}
	}
	
	CPrintToChat(client, "<{olive}HUD{default}> Spectator HUD is now %s.", (bSpecHudActive[client] ? "{blue}on{default}" : "{red}off{default}"));
}

public Action ToggleTankHudCmd(int client, int args) 
{
	int team = GetClientTeam(client);
	if (team == TEAM_SURVIVOR)
		return;
	
	if (bTankHudActive[client])
	{
		bTankHudActive[client] = false;
		
		int index = hTankHudViewers.FindValue(client);
		if (index != -1)
			hTankHudViewers.Erase(index);
	}
	else
	{
		bTankHudActive[client] = true;
		
		if (!bSpecHudActive[client] || team == TEAM_INFECTED)
		{
			int index = hTankHudViewers.FindValue(client);
			if (index == -1)
				hTankHudViewers.Push(client);
		}
	}
	
	CPrintToChat(client, "<{olive}HUD{default}> Tank HUD is now %s.", (bTankHudActive[client] ? "{blue}on{default}" : "{red}off{default}"));
}

/**********************************************************************************************/

// ======================================================================
//  HUD Handle
// ======================================================================
public Action HudDrawTimer(Handle hTimer)
{
	if (IsInReady() || IsInPause())
		return Plugin_Continue;

	if (bPendingArrayRefresh)
	{
		bPendingArrayRefresh = false;
		BuildPlayerArrays();
	}

	int arraysize = hSpecHudViewers.Length;
	if (arraysize) // Only bother if someone's watching us
	{
		Panel specHud = new Panel();
		
		FillHeaderInfo(specHud);
		FillSurvivorInfo(specHud);
		FillScoreInfo(specHud);
		FillInfectedInfo(specHud);
		if (!FillTankInfo(specHud))
			FillGameInfo(specHud);

		for (int i = 0; i < arraysize; ++i)
		{
			int client = hSpecHudViewers.Get(i);
			if(!IsTank(client)){
				SendPanelToClient(specHud, client, DummySpecHudHandler, 3);
			}
			if (!bSpecHudHintShown[client])
			{
				bSpecHudHintShown[client] = true;
				CPrintToChat(client, "<{olive}HUD{default}> Type {green}!spechud{default} into chat to toggle the {blue}Spectator HUD{default}.");
			}
		}
		delete specHud;
	}
	
	arraysize = hTankHudViewers.Length;
	if (!arraysize) return Plugin_Continue;
	
	Panel tankHud = new Panel();
	if (FillTankInfo(tankHud, true)) // No tank -- no HUD
	{
		for (int i = 0; i < arraysize; ++i)
		{
			int client = hTankHudViewers.Get(i);
			if(!IsTank(client)){
				SendPanelToClient(tankHud, client, DummyTankHudHandler, 3);
			}else{
				if(!IsFakeClient(client)){
						PrintHintText(client, "Control : %d / 2 | Frustration: %d", L4D2Direct_GetTankPassedCount(), GetTankFrustration(client));
					}
			}
			if (!bTankHudHintShown[client])
			{
				bTankHudHintShown[client] = true;
				CPrintToChat(client, "<{olive}HUD{default}> Type {green}!tankhud{default} into chat to toggle the {red}Tank HUD{default}.");
			}
		}
	}
	
	delete tankHud;
	return Plugin_Continue;
}

bool IsTank(int tank)
{
	return GetEntProp(tank, Prop_Send, "m_zombieClass") == 8;
}

public int DummySpecHudHandler(Menu hMenu, MenuAction action, int param1, int param2) {}
public int DummyTankHudHandler(Menu hMenu, MenuAction action, int param1, int param2) {}

/**********************************************************************************************/

// ======================================================================
//  HUD Content
// ======================================================================
void FillHeaderInfo(Panel &hSpecHud)
{
	static int iTickrate = 0;
	if (iTickrate == 0 && IsServerProcessing())
		iTickrate = RoundToNearest(1.0 / GetTickInterval());
	
	static char buf[64];
	Format(buf, sizeof(buf), "Server: %s [Slots %i/%i | %iT]", sHostname, GetRealClientCount(), iMaxPlayers, iTickrate);
	DrawPanelText(hSpecHud, buf);
}

void GetMeleePrefix(int client, char[] prefix, int length)
{
	int secondary = GetPlayerWeaponSlot(client, view_as<int>(L4D2WeaponSlot_Secondary));
	WeaponId secondaryWep = IdentifyWeapon(secondary);

	static char buf[4];
	switch (secondaryWep)
	{
		case WEPID_NONE: buf = "N";
		case WEPID_PISTOL: buf = (GetEntProp(secondary, Prop_Send, "m_isDualWielding") ? "DP" : "P");
		case WEPID_PISTOL_MAGNUM: buf = "DE";
		case WEPID_MELEE: buf = "M";
		default: buf = "?";
	}

	strcopy(prefix, length, buf);
}

void GetWeaponInfo(int client, char[] info, int length)
{
	static char buffer[32];
	
	int activeWep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	int primaryWep = GetPlayerWeaponSlot(client, view_as<int>(L4D2WeaponSlot_Primary));
	WeaponId activeWepId = IdentifyWeapon(activeWep);
	WeaponId primaryWepId = IdentifyWeapon(primaryWep);
	
	// Let's begin with what player is holding,
	// but cares only pistols if holding secondary.
	switch (activeWepId)
	{
		case WEPID_PISTOL, WEPID_PISTOL_MAGNUM:
		{
			if (activeWepId == WEPID_PISTOL && !!GetEntProp(activeWep, Prop_Send, "m_isDualWielding"))
			{
				// Dual Pistols Scenario
				// Straight use the prefix since full name is a bit long.
				Format(buffer, sizeof(buffer), "DP");
			}
			else GetLongWeaponName(activeWepId, buffer, sizeof(buffer));
			
			FormatEx(info, length, "%s %i", buffer, GetWeaponClipAmmo(activeWep));
		}
		default:
		{
			GetLongWeaponName(primaryWepId, buffer, sizeof(buffer));
			FormatEx(info, length, "%s %i/%i", buffer, GetWeaponClipAmmo(primaryWep), GetWeaponExtraAmmo(client, primaryWepId));
		}
	}
	
	// Format our result info
	if (primaryWep == -1)
	{
		// In case with no primary,
		// show the melee full name.
		if (activeWepId == WEPID_MELEE || activeWepId == WEPID_CHAINSAW)
		{
			MeleeWeaponId meleeWepId = IdentifyMeleeWeapon(activeWep);
			GetLongMeleeWeaponName(meleeWepId, info, length);
		}
	}
	else
	{
		// Default display -> [Primary <In Detail> | Secondary <Prefix>]
		// Holding melee included in this way
		// i.e. [Chrome 8/56 | M]
		if (GetSlotFromWeaponId(activeWepId) != 1 || activeWepId == WEPID_MELEE || activeWepId == WEPID_CHAINSAW)
		{
			GetMeleePrefix(client, buffer, sizeof(buffer));
			Format(info, length, "%s | %s", info, buffer);
		}

		// Secondary active -> [Secondary <In Detail> | Primary <Ammo Sum>]
		// i.e. [Deagle 8 | Mac 700]
		else
		{
			GetLongWeaponName(primaryWepId, buffer, sizeof(buffer));
			Format(info, length, "%s | %s %i", info, buffer, GetWeaponClipAmmo(primaryWep) + GetWeaponExtraAmmo(client, primaryWepId));
		}
	}
}

void FillSurvivorInfo(Panel &hSpecHud)
{
	static char info[100];
	static char name[MAX_NAME_LENGTH];

	int SurvivorTeamIndex = L4D2_AreTeamsFlipped();

	switch (g_Gamemode)
	{
		case L4D2Gamemode_Scavenge:
		{
			int score = GetScavengeMatchScore(SurvivorTeamIndex);
			FormatEx(info, sizeof info, "->1. Survivors [%d of %d]", score, iRoundLimit);
		}
		case L4D2Gamemode_Versus:
		{
			if (bRoundLive)
			{
				FormatEx(info, sizeof(info), "->1. Survivors [%d]",
							L4D2Direct_GetVSCampaignScore(SurvivorTeamIndex) + GetVersusProgressDistance(SurvivorTeamIndex));
			}
			else
			{
				FormatEx(info, sizeof(info), "->1. Survivors [%d]",
							L4D2Direct_GetVSCampaignScore(SurvivorTeamIndex));
			}
		}
	}
	
	DrawPanelText(hSpecHud, " ");
	DrawPanelText(hSpecHud, info);
	
	for (int i = 0; i < iSurvivorLimit; ++i)
	{
		int client = iSurvivorArray[i];
		if (!client) continue;
		
		GetClientFixedName(client, name, sizeof(name));
		if (!IsPlayerAlive(client))
		{
			FormatEx(info, sizeof(info), "%s: Dead", name);
		}
		else
		{
			if (IsSurvivorHanging(client))
			{
				// Nick: <300HP@Hanging>
				FormatEx(info, sizeof(info), "%s: <%iHP@Hanging>", name, GetClientHealth(client));
			}
			else if (IsIncapacitated(client))
			{
				int activeWep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
				GetLongWeaponName(IdentifyWeapon(activeWep), info, sizeof(info));
				// Nick: <300HP@1st> [Deagle 8]
				Format(info, sizeof(info), "%s: <%iHP@%s> [%s %i]", name, GetClientHealth(client), (GetSurvivorIncapCount(client) == 1 ? "2nd" : "1st"), info, GetWeaponClipAmmo(activeWep));
			}
			else
			{
				GetWeaponInfo(client, info, sizeof(info));
				
				int tempHealth = GetSurvivorTemporaryHealth(client);
				int health = GetClientHealth(client) + tempHealth;
				int incapCount = GetSurvivorIncapCount(client);
				if (incapCount == 0)
				{
					// "#" indicates that player is bleeding.
					// Nick: 99HP# [Chrome 8/72]
					Format(info, sizeof(info), "%s: %iHP%s [%s]", name, health, (tempHealth > 0 ? "#" : ""), info);
				}
				else
				{
					// Player ever incapped should always be bleeding.
					// Nick: 99HP (#1st) [Chrome 8/72]
					Format(info, sizeof(info), "%s: %iHP (#%s) [%s]", name, health, (incapCount == 2 ? "2nd" : "1st"), info);
				}
			}
		}
		
		DrawPanelText(hSpecHud, info);
	}
}

void FillScoreInfo(Panel &hSpecHud)
{
	static char info[64];
	
	switch (g_Gamemode)
	{
		case L4D2Gamemode_Scavenge:
		{
			bool bSecondHalf = !!InSecondHalfOfRound();
			bool bTeamFlipped = L4D2_AreTeamsFlipped();
			
			float fDuration = GetScavengeRoundDuration(bTeamFlipped);
			int iMinutes = RoundToFloor(fDuration / 60);
			
			DrawPanelText(hSpecHud, " ");
				
			FormatEx(info, sizeof info, "> Elapsed Time [%02d:%02.0f]", iMinutes, fDuration - 60 * iMinutes);
			DrawPanelText(hSpecHud, info);
			
			if (bSecondHalf)
			{
				fDuration = GetScavengeRoundDuration(!bTeamFlipped);
				iMinutes = RoundToFloor(fDuration / 60);
				
				FormatEx(info, sizeof info, "> Opponent Duration [%02d:%05.2f]", iMinutes, fDuration - 60 * iMinutes);
				DrawPanelText(hSpecHud, info);
			}
		}
		
		case L4D2Gamemode_Versus:
		{
			if (bHybridScoremod)
			{
				int healthBonus	= SMPlus_GetHealthBonus(),	maxHealthBonus	= SMPlus_GetMaxHealthBonus();
				int damageBonus	= SMPlus_GetDamageBonus(),	maxDamageBonus	= SMPlus_GetMaxDamageBonus();
				int pillsBonus	= SMPlus_GetPillsBonus(),	maxPillsBonus	= SMPlus_GetMaxPillsBonus();
				
				int totalBonus		= healthBonus		+ damageBonus		+ pillsBonus;
				int maxTotalBonus	= maxHealthBonus	+ maxDamageBonus	+ maxPillsBonus;
				
				DrawPanelText(hSpecHud, " ");
				
				// > HB: 100% | DB: 100% | Pills: 60 / 100%
				// > Bonus: 860 <100.0%>
				// > Distance: 400
				
				FormatEx(	info,
							sizeof(info),
							"> HB: %.0f%% | DB: %.0f%% | Pills: %i / %.0f%%",
							ToPercent(healthBonus, maxHealthBonus),
							ToPercent(damageBonus, maxDamageBonus),
							pillsBonus, ToPercent(pillsBonus, maxPillsBonus));
				DrawPanelText(hSpecHud, info);
				
				FormatEx(info, sizeof(info), "> Bonus: %i <%.1f%%>", totalBonus, ToPercent(totalBonus, maxTotalBonus));
				DrawPanelText(hSpecHud, info);
				
				FormatEx(info, sizeof(info), "> Distance: %i", iMaxDistance);
				//if (InSecondHalfOfRound())
				//{
				//	Format(info, sizeof(info), "%s | R#1: %i <%.1f%%>", info, iFirstHalfScore, ToPercent(iFirstHalfScore, L4D_GetVersusMaxCompletionScore() + maxTotalBonus));
				//}
				DrawPanelText(hSpecHud, info);
			}
			
			else if (bScoremod)
			{
				int healthBonus = HealthBonus();
				
				DrawPanelText(hSpecHud, " ");
				
				// > Health Bonus: 860
				// > Distance: 400
				
				FormatEx(info, sizeof(info), "> Health Bonus: %i", healthBonus);
				DrawPanelText(hSpecHud, info);
				
				FormatEx(info, sizeof(info), "> Distance: %i", iMaxDistance);
				//if (InSecondHalfOfRound())
				//{
				//	Format(info, sizeof(info), "%s | R#1: %i", info, iFirstHalfScore);
				//}
				DrawPanelText(hSpecHud, info);
			}
			
			else if (bNextScoremod)
			{
				int permBonus	= SMNext_GetPermBonus(),	maxPermBonus	= SMNext_GetMaxPermBonus();
				int tempBonus	= SMNext_GetTempBonus(),	maxTempBonus	= SMNext_GetMaxTempBonus();
				int pillsBonus	= SMNext_GetPillsBonus(),	maxPillsBonus	= SMNext_GetMaxPillsBonus();
				
				int totalBonus		= permBonus		+ tempBonus		+ pillsBonus;
				int maxTotalBonus	= maxPermBonus	+ maxTempBonus	+ maxPillsBonus;
				
				DrawPanelText(hSpecHud, " ");
				
				// > Perm: 114 | Temp: 514 | Pills: 810
				// > Bonus: 114514 <100.0%>
				// > Distance: 191
				// never ever played on Next so take it easy.
				
				FormatEx(	info,
							sizeof(info),
							"> Perm: %i | Temp: %i | Pills: %i",
							permBonus, tempBonus, pillsBonus);
				DrawPanelText(hSpecHud, info);
				
				FormatEx(info, sizeof(info), "> Bonus: %i <%.1f%%>", totalBonus, ToPercent(totalBonus, maxTotalBonus));
				DrawPanelText(hSpecHud, info);
				
				FormatEx(info, sizeof(info), "> Distance: %i", iMaxDistance);
				//if (InSecondHalfOfRound())
				//{
				//	Format(info, sizeof(info), "%s | R#1: %i <%.1f%%>", info, iFirstHalfScore, ToPercent(iFirstHalfScore, L4D_GetVersusMaxCompletionScore() + maxTotalBonus));
				//}
				DrawPanelText(hSpecHud, info);
			}
		}
	}
}

void FillInfectedInfo(Panel &hSpecHud)
{
	static char info[80];
	static char buffer[16];
	static char name[MAX_NAME_LENGTH];

	int InfectedTeamIndex = !L4D2_AreTeamsFlipped();
	
	switch (g_Gamemode)
	{
		case L4D2Gamemode_Scavenge:
		{
			int score = GetScavengeMatchScore(InfectedTeamIndex);
			FormatEx(info, sizeof info, "->2. Infected [%d of %d]", score, iRoundLimit);
		}
		case L4D2Gamemode_Versus:
		{
			FormatEx(info, sizeof info, "->2. Infected [%d]",
						L4D2Direct_GetVSCampaignScore(InfectedTeamIndex));
		}
	}
	
	DrawPanelText(hSpecHud, " ");
	DrawPanelText(hSpecHud, info);

	int infectedCount = 0;
	for (int i = 0; i < iMaxPlayerZombies; ++i)
	{
		int client = iInfectedArray[i];
		if (!client) continue;
		
		GetClientFixedName(client, name, sizeof(name));
		if (!IsPlayerAlive(client)) 
		{
			int timeLeft = RoundToFloor(L4D_GetPlayerSpawnTime(client));
			if (timeLeft < 0) // Deathcam
			{
				// verygood: Dead
				FormatEx(info, sizeof(info), "%s: Dead", name);
			}
			else // Ghost Countdown
			{
				FormatEx(buffer, sizeof(buffer), "%is", timeLeft);
				// verygood: Dead (15s)
				FormatEx(info, sizeof(info), "%s: Dead (%s)", name, (timeLeft ? buffer : "Spawning..."));
				
				//if (storedClass[client] > ZC_None) {
				//	FormatEx(info, sizeof(info), "%s: Dead (%s) [%s]", name, ZOMBIECLASS_NAME(storedClass[client]), (RoundToNearest(timeLeft) ? buffer : "Spawning..."));
				//} else {
				//	FormatEx(info, sizeof(info), "%s: Dead (%s)", name, (RoundToNearest(timeLeft) ? buffer : "Spawning..."));
				//}
			}
		}
		else
		{
			L4D2SI zClass = GetInfectedClass(client);
			if (zClass == ZC_Tank)
				continue;
			
			int iHP = GetClientHealth(client), iMaxHP = GetEntProp(client, Prop_Send, "m_iMaxHealth");
			if (IsInfectedGhost(client))
			{
				// DONE: Handle a case of respawning chipped SI, show the ghost's health
				if (iHP < iMaxHP)
				{
					// verygood: Charger (Ghost@1HP)
					FormatEx(info, sizeof(info), "%s: %s (Ghost@%iHP)", name, ZOMBIECLASS_NAME(zClass), iHP);
				}
				else
				{
					// verygood: Charger (Ghost)
					FormatEx(info, sizeof(info), "%s: %s (Ghost)", name, ZOMBIECLASS_NAME(zClass));
				}
			}
			else
			{
				int iCooldown = RoundToCeil(GetAbilityCooldown(client));
				float fDuration = GetAbilityCooldownDuration(client);
				if (iCooldown > 0 && fDuration > 1.0 && !HasAbilityVictim(client, zClass))
				{
					FormatEx(buffer, sizeof(buffer), " [%is]", iCooldown);
				}
				else { buffer[0] = '\0'; }
				
				if (GetEntityFlags(client) & FL_ONFIRE)
				{
					// verygood: Charger (1HP) [On Fire] [6s]
					FormatEx(info, sizeof(info), "%s: %s (%iHP) [On Fire]%s", name, ZOMBIECLASS_NAME(zClass), iHP, buffer);
				}
				else
				{
					// verygood: Charger (1HP) [6s]
					FormatEx(info, sizeof(info), "%s: %s (%iHP)%s", name, ZOMBIECLASS_NAME(zClass), iHP, buffer);
				}
			}
		}

		infectedCount++;
		DrawPanelText(hSpecHud, info);
	}
	
	if (!infectedCount)
	{
		DrawPanelText(hSpecHud, "There is no SI at this moment.");
	}
}

bool FillTankInfo(Panel &hSpecHud, bool bTankHUD = false)
{
	int tank = FindTank();
	if (tank == -1)
		return false;

	static char info[64];
	static char name[MAX_NAME_LENGTH];

	if (bTankHUD)
	{
		FormatEx(info, sizeof(info), "%s :: Tank HUD", sReadyCfgName);
		DrawPanelText(hSpecHud, info);
		
		int len = strlen(info);
		for (int i = 0; i < len; ++i) info[i] = '_';
		DrawPanelText(hSpecHud, info);
	}
	else
	{
		DrawPanelText(hSpecHud, " ");
		DrawPanelText(hSpecHud, "->3. Tank");
	}

	// Draw owner & pass counter
	int passCount = L4D2Direct_GetTankPassedCount();
	switch (passCount)
	{
		case 0: FormatEx(info, sizeof(info), "native");
		case 1: FormatEx(info, sizeof(info), "%i", passCount);
		case 2: FormatEx(info, sizeof(info), "%i", passCount);
		case 3: FormatEx(info, sizeof(info), "%ird", passCount);
		default: FormatEx(info, sizeof(info), "%ith", passCount);
	}

	if (!IsFakeClient(tank))
	{
		GetClientFixedName(tank, name, sizeof(name));
		Format(info, sizeof(info), "Control : %s (%s / 2)", name, info);
	}
	else
	{
		Format(info, sizeof(info), "Control : AI (%s / 2)", info);
	}
	DrawPanelText(hSpecHud, info);

	// Draw health
	int health = GetClientHealth(tank),
		maxhealth = GetEntProp(tank, Prop_Send, "m_iMaxHealth");
	float healthPercent = ToPercent(health, maxhealth);
	if (health <= 0 || IsIncapacitated(tank) || !IsPlayerAlive(tank))
	{
		info = "Health  : Dead";
	}
	else
	{
		FormatEx(info, sizeof(info), "Health  : %i / %i%%", health, MAX(1, RoundFloat(healthPercent)));
	}
	DrawPanelText(hSpecHud, info);

	// Draw frustration
	if (!IsFakeClient(tank))
	{
		FormatEx(info, sizeof(info), "Frustr.  : %d%%", GetTankFrustration(tank));
	}
	else
	{
		info = "Frustr.  : AI";
	}
	DrawPanelText(hSpecHud, info);

	// Draw network
	if (!IsFakeClient(tank))
	{
		FormatEx(info, sizeof(info), "Network: %ims / %.1f", RoundToNearest(GetClientAvgLatency(tank, NetFlow_Both) * 1000.0), GetLerpTime(tank) * 1000.0);
	}
	else
	{
		info = "Network: AI";
	}
	DrawPanelText(hSpecHud, info);

	// Draw fire status
	if (GetEntityFlags(tank) & FL_ONFIRE)
	{
		int timeleft = RoundToCeil(healthPercent / 100.0 * fTankBurnDuration);
		FormatEx(info, sizeof(info), "On Fire: %is", timeleft);
		DrawPanelText(hSpecHud, info);
	}
	
	return true;
}

void FillGameInfo(Panel &hSpecHud)
{
	// Turns out too much info actually CAN be bad, funny ikr
	static char info[64];
	static char buffer[10];

	switch (g_Gamemode)
	{
		case L4D2Gamemode_Scavenge:
		{
			FormatEx(info, sizeof(info), "->3. %s (R#%i)", sReadyCfgName, GetScavengeRoundNumber());
			
			DrawPanelText(hSpecHud, " ");
			DrawPanelText(hSpecHud, info);
			
			FormatEx(info, sizeof info, "Best of %i", iRoundLimit);
			DrawPanelText(hSpecHud, info);
		}
		
		case L4D2Gamemode_Versus:
		{
			FormatEx(info, sizeof(info), "->3. %s (R#%d)", sReadyCfgName, InSecondHalfOfRound() + 1);
			DrawPanelText(hSpecHud, " ");
			DrawPanelText(hSpecHud, info);
			
			if (l4d_tank_percent != null && l4d_witch_percent != null)
			{
				int tankPercent = GetStoredTankPercent();
				int witchPercent = GetStoredWitchPercent();
				int survivorFlow = GetHighestSurvivorFlow();
				if (survivorFlow == -1)
					survivorFlow = GetFurthestSurvivorFlow();
				
				bool bDivide = false;
						
				// tank percent
				if (iTankCount > 0)
				{
					bDivide = true;
					FormatEx(buffer, sizeof(buffer), "%i%%", tankPercent);
					
					if ((bFlowTankActive && bRoundHasFlowTank) || IsDarkCarniRemix())
					{
						FormatEx(info, sizeof(info), "Tank: %s", buffer);
					}
					else
					{
						FormatEx(info, sizeof(info), "Tank: %s", (IsStaticTankMap() ? "Static" : "Event"));
					}
				}
				
				// witch percent
				if (iWitchCount > 0)
				{
					FormatEx(buffer, sizeof(buffer), "%i%%", witchPercent);
					
					if (bDivide) {
						Format(info, sizeof(info), "%s | Witch: %s", info, ((bRoundHasFlowWitch || IsDarkCarniRemix()) ? buffer : (IsStaticWitchMap() ? "Static" : "Event")));
					} else {
						bDivide = true;
						FormatEx(info, sizeof(info), "Witch: %s", ((bRoundHasFlowWitch || IsDarkCarniRemix()) ? buffer : (IsStaticWitchMap() ? "Static" : "Event")));
					}
				}
				
				// current
				if (bDivide) {
					Format(info, sizeof(info), "%s | Cur: %i%%", info, survivorFlow);
				} else {
					FormatEx(info, sizeof(info), "Cur: %i%%", survivorFlow);
				}
				
				DrawPanelText(hSpecHud, info);
			}
			
			// tank selection
			if (bTankSelection && iTankCount > 0)
			{
				int tankClient = GetTankSelection();
				if (tankClient > 0 && IsClientInGame(tankClient))
				{
					FormatEx(info, sizeof(info), "Tank -> %N", tankClient);
					DrawPanelText(hSpecHud, info);
				}
			}
		}
	}
}

/**
 *	Stocks
**/
stock float GetAbilityCooldownDuration(int client)
{
	int ability = GetInfectedCustomAbility(client);
	if (ability != -1 && GetEntProp(ability, Prop_Send, "m_hasBeenUsed"))
	{
		return GetCountdownDuration(ability);
	}
	return 0.0;
}

stock float GetAbilityCooldown(int client)
{
	int ability = GetInfectedCustomAbility(client);
	if (ability != -1 && GetEntProp(ability, Prop_Send, "m_hasBeenUsed"))
	{
		if (GetCountdownDuration(ability) != 3600.0)
			return GetCountdownTimestamp(ability) - GetGameTime();
	}
	return 0.0;
}

stock float GetCountdownDuration(int entity)
{
	return GetEntPropFloat(entity, Prop_Send, "m_duration");
}

stock float GetCountdownTimestamp(int entity)
{
	return GetEntPropFloat(entity, Prop_Send, "m_timestamp");
}

stock int GetInfectedCustomAbility(int client)
{
	if (HasEntProp(client, Prop_Send, "m_customAbility")) {
		return GetEntPropEnt(client, Prop_Send, "m_customAbility");
	}
	
	return -1;
}

stock bool HasAbilityVictim(int client, L4D2SI zClass)
{
	switch (zClass)
	{
		case ZC_Smoker: return GetEntPropEnt(client, Prop_Send, "m_tongueVictim") > 0;
		case ZC_Hunter: return GetEntPropEnt(client, Prop_Send, "m_pounceVictim") > 0;
		case ZC_Jockey: return GetEntPropEnt(client, Prop_Send, "m_jockeyVictim") > 0;
		case ZC_Charger: return GetEntPropEnt(client, Prop_Send, "m_pummelVictim") > 0 || GetEntPropEnt(client, Prop_Send, "m_carryVictim") > 0;
	}
	return false;
}

/**
 *	Datamap m_iAmmo
 *	offset to add - gun(s) - control cvar
 *	
 *	+12: M4A1, AK74, Desert Rifle, also SG552 - ammo_assaultrifle_max
 *	+20: both SMGs, also the MP5 - ammo_smg_max
 *	+28: both Pump Shotguns - ammo_shotgun_max
 *	+32: both autoshotguns - ammo_autoshotgun_max
 *	+36: Hunting Rifle - ammo_huntingrifle_max
 *	+40: Military Sniper, AWP, Scout - ammo_sniperrifle_max
 *	+68: Grenade Launcher - ammo_grenadelauncher_max
 */

#define	ASSAULT_RIFLE_OFFSET_IAMMO		12;
#define	SMG_OFFSET_IAMMO				20;
#define	PUMPSHOTGUN_OFFSET_IAMMO		28;
#define	AUTO_SHOTGUN_OFFSET_IAMMO		32;
#define	HUNTING_RIFLE_OFFSET_IAMMO		36;
#define	MILITARY_SNIPER_OFFSET_IAMMO	40;
#define	GRENADE_LAUNCHER_OFFSET_IAMMO	68;

stock int GetWeaponExtraAmmo(int client, WeaponId wepid)
{
	static int ammoOffset;
	if (!ammoOffset) ammoOffset = FindSendPropInfo("CCSPlayer", "m_iAmmo");
	
	int offset;
	switch (wepid)
	{
		case WEPID_RIFLE, WEPID_RIFLE_AK47, WEPID_RIFLE_DESERT, WEPID_RIFLE_SG552:
			offset = ASSAULT_RIFLE_OFFSET_IAMMO
		case WEPID_SMG, WEPID_SMG_SILENCED:
			offset = SMG_OFFSET_IAMMO
		case WEPID_PUMPSHOTGUN, WEPID_SHOTGUN_CHROME:
			offset = PUMPSHOTGUN_OFFSET_IAMMO
		case WEPID_AUTOSHOTGUN, WEPID_SHOTGUN_SPAS:
			offset = AUTO_SHOTGUN_OFFSET_IAMMO
		case WEPID_HUNTING_RIFLE:
			offset = HUNTING_RIFLE_OFFSET_IAMMO
		case WEPID_SNIPER_MILITARY, WEPID_SNIPER_AWP, WEPID_SNIPER_SCOUT:
			offset = MILITARY_SNIPER_OFFSET_IAMMO
		case WEPID_GRENADE_LAUNCHER:
			offset = GRENADE_LAUNCHER_OFFSET_IAMMO
		default:
			return -1;
	}
	return GetEntData(client, ammoOffset + offset);
} 

stock int GetWeaponClipAmmo(int weapon)
{
	return (weapon > 0 ? GetEntProp(weapon, Prop_Send, "m_iClip1") : -1);
}

stock SurvivorCharacter GetFixedSurvivorCharacter(int client)
{
	int sc = GetEntProp(client, Prop_Send, "m_survivorCharacter");
	
	switch (sc)
	{
		case 6:						// Francis' netprop is 6
			return SC_FRANCIS;		// but here to match the official serial
			
		case 7:						// Louis' netprop is 7
			return SC_LOUIS;		// but here to match the official serial
			
		case 9, 11:					// Bill's alternative netprop
			return SC_BILL;			// match it correctly
	}
	return view_as<SurvivorCharacter>(sc);
}

stock float GetLerpTime(int client)
{
	static char value[16];
	
	if (!GetClientInfo(client, "cl_updaterate", value, sizeof(value))) value = "";
	int updateRate = StringToInt(value);
	updateRate = RoundFloat(CLAMP(float(updateRate), fMinUpdateRate, fMaxUpdateRate));
	
	if (!GetClientInfo(client, "cl_interp_ratio", value, sizeof(value))) value = "";
	float flLerpRatio = StringToFloat(value);
	
	if (!GetClientInfo(client, "cl_interp", value, sizeof(value))) value = "";
	float flLerpAmount = StringToFloat(value);
	
	if (cVarMinInterpRatio != null && cVarMaxInterpRatio != null && fMinInterpRatio != -1.0 ) {
		flLerpRatio = CLAMP(flLerpRatio, fMinInterpRatio, fMaxInterpRatio );
	}
	
	return MAX(flLerpAmount, flLerpRatio / updateRate);
}

stock void GetClientFixedName(int client, char[] name, int length)
{
	GetClientName(client, name, length);

	if (name[0] == '[')
	{
		char temp[MAX_NAME_LENGTH];
		strcopy(temp, sizeof(temp), name);
		temp[sizeof(temp)-2] = 0;
		strcopy(name[1], length-1, temp);
		name[0] = ' ';
	}

	if (strlen(name) > 18)
	{
		name[15] = name[16] = name[17] = '.';
		name[18] = 0;
	}
}

//stock int GetRealTeam(int team)
//{
//	return team ^ view_as<int>(!!InSecondHalfOfRound() != L4D2_AreTeamsFlipped());
//}

stock int GetRealClientCount() 
{
	int clients = 0;
	for (int i = 1; i <= MaxClients; ++i) 
	{
		if (IsClientConnected(i) && !IsFakeClient(i)) clients++;
	}
	return clients;
}

stock int InSecondHalfOfRound()
{
	return GameRules_GetProp("m_bInSecondHalfOfRound");
}

stock int GetVersusProgressDistance(int teamIndex)
{
	int distance = 0;
	for (int i = 0; i < 4; ++i)
	{
		distance += GameRules_GetProp("m_iVersusDistancePerSurvivor", _, i + 4 * teamIndex);
	}
	return distance;
}

/*
 * Future use
 */
stock void FillScavengeScores(int arr[2][5])
{
	for (int i = 1; i <= iRoundLimit; ++i)
	{
		arr[0][i-1] = GetScavengeTeamScore(0, i);
		arr[1][i-1] = GetScavengeTeamScore(1, i);
	}
}

stock int FormatScavengeRoundTime(char[] buffer, int maxlen, int teamIndex, bool nodecimalpoint = false)
{
	float seconds = GetScavengeRoundDuration(teamIndex);
	int minutes = RoundToFloor(seconds) / 60;
	seconds -= 60 * minutes;
	
	return nodecimalpoint ?
				Format(buffer, maxlen, "%d:%02.0f", minutes, seconds) :
				Format(buffer, maxlen, "%d:%05.2f", minutes, seconds);
}

/* 
 * GetScavengeRoundDuration & GetScavengeTeamScore
 * credit to ProdigySim
 */
stock float GetScavengeRoundDuration(int teamIndex)
{
	float flRoundStartTime = GameRules_GetPropFloat("m_flRoundStartTime");
	if (teamIndex == view_as<int>(L4D2_AreTeamsFlipped()) && flRoundStartTime != 0.0 && GameRules_GetPropFloat("m_flRoundEndTime") == 0.0)
	{
		// Survivor team still playing round.
		return GetGameTime() - flRoundStartTime;
	}
	return GameRules_GetPropFloat("m_flRoundDuration", teamIndex);
}

stock int GetScavengeTeamScore(int teamIndex, int round=-1)
{
	if (!(1 <= round <= 5))
	{
		round = GameRules_GetProp("m_nRoundNumber");
	}
	return GameRules_GetProp("m_iScavengeTeamScore", _, (2*(round-1)) + teamIndex);
}

stock int GetScavengeMatchScore(int teamIndex)
{
	return GameRules_GetProp("m_iScavengeMatchScore", _, teamIndex);
}

stock int GetScavengeRoundNumber()
{
	return GameRules_GetProp("m_nRoundNumber");
}

stock int GetFurthestSurvivorFlow()
{
	int flow = RoundToNearest(100.0 * (L4D2_GetFurthestSurvivorFlow() + fVersusBossBuffer) / L4D2Direct_GetMapMaxFlowDistance());
	return MIN(flow, 100);
}

//stock float GetClientFlow(int client)
//{
//	return (L4D2Direct_GetFlowDistance(client) / L4D2Direct_GetMapMaxFlowDistance());
//}

stock int GetHighestSurvivorFlow()
{
	int flow = -1;
	
	int client = L4D_GetHighestFlowSurvivor();
	if (client > 0) {
		flow = RoundToNearest(100.0 * (L4D2Direct_GetFlowDistance(client) + fVersusBossBuffer) / L4D2Direct_GetMapMaxFlowDistance());
	}
	
	return MIN(flow, 100);
}

stock bool RoundHasFlowTank()
{
	return L4D2Direct_GetVSTankToSpawnThisRound(InSecondHalfOfRound());
}

stock bool RoundHasFlowWitch()
{
	return L4D2Direct_GetVSWitchToSpawnThisRound(InSecondHalfOfRound());
}

//bool IsSpectator(int client)
//{
//	return IsClientInGame(client) && GetClientTeam(client) == TEAM_SPECTATOR;
//}

stock bool IsSurvivor(int client)
{
	return IsClientInGame(client) && GetClientTeam(client) == TEAM_SURVIVOR;
}

stock bool IsInfected(int client)
{
	return IsClientInGame(client) && GetClientTeam(client) == TEAM_INFECTED;
}

stock bool IsInfectedGhost(int client) 
{
	return !!GetEntProp(client, Prop_Send, "m_isGhost");
}

stock L4D2SI GetInfectedClass(int client)
{
	return view_as<L4D2SI>(GetEntProp(client, Prop_Send, "m_zombieClass"));
}

stock int FindTank() 
{
	for (int i = 1; i <= MaxClients; ++i)
	{
		if (IsInfected(i) && GetInfectedClass(i) == ZC_Tank && IsPlayerAlive(i))
			return i;
	}

	return -1;
}

stock int GetTankFrustration(int tank)
{
	return (100 - GetEntProp(tank, Prop_Send, "m_frustration"));
}

stock bool IsIncapacitated(int client)
{
	return !!GetEntProp(client, Prop_Send, "m_isIncapacitated");
}

stock bool IsSurvivorHanging(int client)
{
	return !!(GetEntProp(client, Prop_Send, "m_isHangingFromLedge") | GetEntProp(client, Prop_Send, "m_isFallingFromLedge"));
}

stock int GetSurvivorIncapCount(int client)
{
	return GetEntProp(client, Prop_Send, "m_currentReviveCount");
}

stock int GetSurvivorTemporaryHealth(int client)
{
	int temphp = RoundToCeil(GetEntPropFloat(client, Prop_Send, "m_healthBuffer") - ((GetGameTime() - GetEntPropFloat(client, Prop_Send, "m_healthBufferTime")) * fPainPillsDecayRate)) - 1;
	return (temphp > 0 ? temphp : 0);
}

stock float GetTankFlow(int round)
{
	return L4D2Direct_GetVSTankFlowPercent(round)/* -
		( GetConVarFloat(g_hVsBossBuffer) / L4D2Direct_GetMapMaxFlowDistance() )*/;
}

stock float GetWitchFlow(int round)
{
	return L4D2Direct_GetVSWitchFlowPercent(round)/* -
		( GetConVarFloat(g_hVsBossBuffer) / L4D2Direct_GetMapMaxFlowDistance() )*/;
}

stock bool IsStaticWitchMap()
{
	return RoundToNearest(GetWitchFlow(0) * 100.0) < 1;
}

stock bool IsStaticTankMap()
{
	return RoundToNearest(GetTankFlow(0) * 100.0) < 1;
}
