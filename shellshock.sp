#include <sourcemod>
#include <dhooks>
#include <sdktools>
#include <sdktools_gamerules>
#include <sdktools_trace>
#include <steamtools>
#include <smlib>

/*
* Shellshock Features:
* (X)-Server-controlled weapon loadout on spawn
* (X)-Constantly sprinting
* (X)-Quick respawn
* (X)-Faster shotgun fire
* (X)-Larger clips for shotgun
* ( )-Faster crossbow bolts
* ( )-Faster crossbow fire
* (X)-Impact grenade
* (X)-Spawn Protection
*/

//globals

//int CHL2_Player::GiveAmmo( int nCount, int nAmmoIndex, bool bSuppressSound)
new Handle:hGiveAmmo;
//void CBasePlayer::RemoveAllItems( bool removeSuit )
new Handle:hRemoveAllItems;
//void CHL2_Player::PreThink(void)
new Handle:hPreThink;
//virtual void CBasePlayer::Spawn()
new Handle:hSpawnCall;
new Handle:hSpawnHook;
//virtual void SetAnimation( PLAYER_ANIM playerAnim );
new Handle:hSetAnimation;
//virtual int GetMaxClip1( void ) const;
new Handle:hGetMaxClip1;
//virtual int GetDefaultClip1( void ) const;
new Handle:hGetDefaultClip1;
//virtual bool AllowsAutoSwitchFrom( void ) const;
new Handle:hAllowAutoSwitchFrom;
//virtual void Operator_HandleAnimEvent( animevent_t *pEvent, CBaseCombatCharacter *pOperator );
new Handle:hOperator_HandleAnimEvent;
//virtual bool Reload( void );
new Handle:hReloadShotgun;
new Handle:hReloadCrossbow;
//virtual bool HasWeaponIdleTimeElapsed( void );
new Handle:hHasWeaponIdleTimeElapsed;
//virtual void PrimaryAttack( void );
new Handle:hPrimaryAttackCrossbow;
new Handle:hPrimaryAttackShotgun;
//virtual void SecondaryAttack( void );
new Handle:hSecondaryAttackShotgun;
//virtual void Weapon_Equip( CBaseCombatWeapon *pWeapon );
new Handle:hWeapon_Equip;
//virtual void SetWeaponIdleTime( float time );
new Handle:hSetWeaponIdleTime;
//virtual int OnTakeDamage( const CTakeDamageInfo &info );
new Handle:hOnTakeDamage;
//Array of player respawn times keyed by player ID
new Float:nextEligibleDamageTime[64]

//Convars
new Handle:hss_respawn_time;
new Handle:hss_playerspeed;
new Handle:hss_physcannon;
new Handle:hss_shotgun;
new Handle:hss_crossbow;
new Handle:hss_pistol;
new Handle:hss_rpg;
new Handle:hss_frag;
new Handle:hss_ar2;
new Handle:hss_smg1;
new Handle:hss_slam;
new Handle:hss_melee;
new Handle:hss_357;
new Handle:hss_shotgun_defaultclip;
new Handle:hss_shotgun_maxclip;
new Handle:hss_shotgun_damage_multiplier;
new Handle:hss_shotgun_refire;
//Actual values
new Float:ss_respawn_time = 0.5;
new Float:ss_playerspeed = 320.0;
new bool:ss_physcannon = true;
new bool:ss_shotgun = true;
new bool:ss_crossbow = false;
new bool:ss_pistol = true;
new bool:ss_rpg = false;
new bool:ss_frag = false;
new bool:ss_ar2 = false;
new bool:ss_smg1 = false;
new bool:ss_slam = false;
new bool:ss_melee = true;
new bool:ss_357 = false;
new ss_shotgun_defaultclip = 8;
new ss_shotgun_maxclip = 8;
new Float:ss_shotgun_damage_multiplier = 3.0;
new Float:ss_shotgun_refire = 0.35;

//Plugin info
public Plugin:myinfo =
{
	name = "Shell Shock",
	author = "Nimgoble & pl4tinum",
	description = "HL2:DM Shotgun mod",
	version = "1.0.0.1",
	url = "www.nimgoble.com"
};

public OnPluginStart()
{
	CreateConVars();
	//PrintToServer("This is going to take forever...");
	new Handle:config = LoadGameConfigFile("shellshock.games");
	
	if(config == INVALID_HANDLE)
		SetFailState("Invalid config");
	
	/*
	* Calls
	*/
	//GiveAmmo
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(config, SDKConf_Virtual, "GiveAmmo");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	hGiveAmmo = EndPrepSDKCall();
	
	//RemoveAllItems
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(config, SDKConf_Virtual, "RemoveAllItems");
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	hRemoveAllItems = EndPrepSDKCall();
	
	//SetAnimation
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(config, SDKConf_Virtual, "SetAnimation");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	hSetAnimation = EndPrepSDKCall();
	
	//Spawn call
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(config, SDKConf_Virtual, "Spawn");
	hSpawnCall = EndPrepSDKCall();
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(config, SDKConf_Virtual, "SetWeaponIdleTime");
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	hSetWeaponIdleTime = EndPrepSDKCall();
	
	/*
	* Hooks
	*/
	InitClientHooks(config);
	InitShotgunHooks(config);
	InitFragHooks(config);
	InitCrossbowHooks(config);
	
	//Close config handle
	CloseHandle(config);
	
	//Hook existing clients
	new playersconnected = GetMaxClients();
	for (new i = 1; i <= playersconnected; i++)
    {
        if(IsClientInGame(i))
        {    
            HookExistingClient(i);
        }
    }
}

CreateConVars()
{
	new String:convarValue[32];
	
	hss_respawn_time = FindConVar("ss_respawn_time");
	if(hss_respawn_time == INVALID_HANDLE)
		hss_respawn_time = CreateConVar("ss_respawn_time", "0.5", "Sets how long a player has to wait until they can respawn", FCVAR_PROTECTED);
	else
	{
		GetConVarString(hss_respawn_time, convarValue, 32)
		ChangeCVAR(hss_respawn_time, convarValue);
	}
	
	hss_playerspeed = FindConVar("ss_playerspeed");
	if(hss_playerspeed == INVALID_HANDLE)
		hss_playerspeed = CreateConVar("ss_playerspeed", "320", "Sets the speed of the players", FCVAR_PROTECTED, true, 1.0);
	else
	{
		GetConVarString(hss_playerspeed, convarValue, 32)
		ChangeCVAR(hss_playerspeed, convarValue);
	}
	
	hss_physcannon = FindConVar("ss_physcannon");
	if(hss_physcannon == INVALID_HANDLE)
		hss_physcannon = CreateConVar("ss_physcannon", "1", "Sets whether players spawn with the gravity gun", FCVAR_PROTECTED, true, 0.0, true, 1.0);
	else
	{
		GetConVarString(hss_physcannon, convarValue, 32)
		ChangeCVAR(hss_physcannon, convarValue);
	}
	
	hss_shotgun = FindConVar("ss_shotgun");
	if(hss_shotgun == INVALID_HANDLE)
		hss_shotgun = CreateConVar("ss_shotgun", "1", "Sets whether players spawn with the shotgun", FCVAR_PROTECTED, true, 0.0, true, 1.0);
	else
	{
		GetConVarString(hss_shotgun, convarValue, 32)
		ChangeCVAR(hss_shotgun, convarValue);
	}
	
	hss_crossbow = FindConVar("ss_crossbow");
	if(hss_crossbow == INVALID_HANDLE)
		hss_crossbow = CreateConVar("ss_crossbow", "0", "Sets whether players spawn with the crossbow", FCVAR_PROTECTED, true, 0.0, true, 1.0);
	else
	{
		GetConVarString(hss_crossbow, convarValue, 32)
		ChangeCVAR(hss_crossbow, convarValue);
	}
	
	hss_pistol = FindConVar("ss_pistol");
	if(hss_pistol == INVALID_HANDLE)
		hss_pistol = CreateConVar("ss_pistol", "1", "Sets whether players spawn with the pistol", FCVAR_PROTECTED, true, 0.0, true, 1.0);
	else
	{
		GetConVarString(hss_pistol, convarValue, 32)
		ChangeCVAR(hss_pistol, convarValue);
	}
	
	hss_rpg = FindConVar("ss_rpg");
	if(hss_rpg == INVALID_HANDLE)
		hss_rpg = CreateConVar("ss_rpg", "0", "Sets whether players spawn with the rpg", FCVAR_PROTECTED, true, 0.0, true, 1.0);
	else
	{
		GetConVarString(hss_rpg, convarValue, 32)
		ChangeCVAR(hss_rpg, convarValue);
	}
		
	hss_frag = FindConVar("ss_frag");
	if(hss_frag == INVALID_HANDLE)
		hss_frag = CreateConVar("ss_frag", "0", "Sets whether players spawn with the frag", FCVAR_PROTECTED, true, 0.0, true, 1.0);
	else
	{
		GetConVarString(hss_frag, convarValue, 32)
		ChangeCVAR(hss_frag, convarValue);
	}
	
	hss_ar2 = FindConVar("ss_ar2");
	if(hss_ar2 == INVALID_HANDLE)
		hss_ar2 = CreateConVar("ss_ar2", "0", "Sets whether players spawn with the ar2", FCVAR_PROTECTED, true, 0.0, true, 1.0);
	else
	{
		GetConVarString(hss_ar2, convarValue, 32)
		ChangeCVAR(hss_ar2, convarValue);
	}
	
	hss_smg1 = FindConVar("ss_smg1");
	if(hss_smg1 == INVALID_HANDLE)
		hss_smg1 = CreateConVar("ss_smg1", "0", "Sets whether players spawn with the smg1", FCVAR_PROTECTED, true, 0.0, true, 1.0);
	else
	{
		GetConVarString(hss_smg1, convarValue, 32)
		ChangeCVAR(hss_smg1, convarValue);
	}
	
	hss_slam = FindConVar("ss_slam");
	if(hss_slam == INVALID_HANDLE)
		hss_slam = CreateConVar("ss_slam", "0", "Sets whether players spawn with the slam", FCVAR_PROTECTED, true, 0.0, true, 1.0);
	else
	{
		GetConVarString(hss_slam, convarValue, 32)
		ChangeCVAR(hss_slam, convarValue);
	}
	
	hss_melee = FindConVar("ss_melee");
	if(hss_melee == INVALID_HANDLE)
		hss_melee = CreateConVar("ss_melee", "1", "Sets whether players spawn with the melee", FCVAR_PROTECTED, true, 0.0, true, 1.0);
	else
	{
		GetConVarString(hss_melee, convarValue, 32)
		ChangeCVAR(hss_melee, convarValue);
	}
		
	hss_357 = FindConVar("ss_357");
	if(hss_357 == INVALID_HANDLE)
		hss_357 = CreateConVar("ss_357", "0", "Sets whether players spawn with the 357", FCVAR_PROTECTED, true, 0.0, true, 1.0);
	else
	{
		GetConVarString(hss_357, convarValue, 32)
		ChangeCVAR(hss_357, convarValue);
	}
	
	hss_shotgun_defaultclip = FindConVar("ss_shotgun_defaultclip");
	if(hss_shotgun_defaultclip == INVALID_HANDLE)
		hss_shotgun_defaultclip = CreateConVar("ss_shotgun_defaultclip", "8", "Sets the default clip size of the shotgun", FCVAR_PROTECTED, true, 1.0);
	else
	{
		GetConVarString(hss_shotgun_defaultclip, convarValue, 32)
		ChangeCVAR(hss_shotgun_defaultclip, convarValue);
	}
		
	hss_shotgun_maxclip = FindConVar("ss_shotgun_maxclip");
	if(hss_shotgun_maxclip == INVALID_HANDLE)
		hss_shotgun_maxclip = CreateConVar("ss_shotgun_maxclip", "8", "Sets the max clip size of the shogtun", FCVAR_PROTECTED, true, 1.0);
	else
	{
		GetConVarString(hss_shotgun_maxclip, convarValue, 32)
		ChangeCVAR(hss_shotgun_maxclip, convarValue);
	}
		
	hss_shotgun_damage_multiplier = FindConVar("ss_shotgun_damage_multiplier");
	if(hss_shotgun_damage_multiplier == INVALID_HANDLE)
		hss_shotgun_damage_multiplier = CreateConVar("ss_shotgun_damage_multiplier", "3.0", "Sets the damage multiplier for the shotgun.", FCVAR_PROTECTED, true, 1.0);
	else
	{
		GetConVarString(hss_shotgun_damage_multiplier, convarValue, 32)
		ChangeCVAR(hss_shotgun_damage_multiplier, convarValue);
	}
	
	hss_shotgun_refire = FindConVar("hss_shotgun_refire");
	if(hss_shotgun_refire == INVALID_HANDLE)
		hss_shotgun_refire = CreateConVar("ss_shotgun_refire", "0.35", "Sets the refire time for the shotgun.", FCVAR_PROTECTED, true, 0.0);
	else
	{
		GetConVarString(hss_shotgun_refire, convarValue, 32)
		ChangeCVAR(hss_shotgun_refire, convarValue);
	}

	HookConVarChange(hss_respawn_time, SSConVarChanged);
	HookConVarChange(hss_playerspeed, SSConVarChanged);
	HookConVarChange(hss_physcannon, SSConVarChanged);
	HookConVarChange(hss_shotgun, SSConVarChanged);
	HookConVarChange(hss_crossbow, SSConVarChanged);
	HookConVarChange(hss_pistol, SSConVarChanged);
	HookConVarChange(hss_rpg, SSConVarChanged);
	HookConVarChange(hss_frag, SSConVarChanged);
	HookConVarChange(hss_ar2, SSConVarChanged);
	HookConVarChange(hss_smg1, SSConVarChanged);
	HookConVarChange(hss_slam, SSConVarChanged);
	HookConVarChange(hss_melee, SSConVarChanged);
	HookConVarChange(hss_357, SSConVarChanged);
	HookConVarChange(hss_shotgun_defaultclip, SSConVarChanged);
	HookConVarChange(hss_shotgun_maxclip, SSConVarChanged);
	HookConVarChange(hss_shotgun_damage_multiplier, SSConVarChanged);
	HookConVarChange(hss_shotgun_refire, SSConVarChanged);
}

public SSConVarChanged(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	new String:convarName[32];
	GetConVarName(cvar, convarName, 32);
	PrintToServer("SSConVarChanged for %s: %s - %s", convarName, oldVal, newVal);
	ChangeCVAR(cvar, newVal);
}

ChangeCVAR(Handle:cvar, const String:newVal[])
{
	new String:convarName[32];
	GetConVarName(cvar, convarName, 32);
	PrintToServer("Setting %s to %s", convarName, newVal);
	if(cvar == hss_respawn_time)
	{
		ss_respawn_time = StringToFloat(newVal);
	}
	else if(cvar == hss_playerspeed)
	{
		ss_playerspeed = StringToFloat(newVal);
	}
	else if(cvar == hss_physcannon)
	{
		ss_physcannon = (StringToInt(newVal) == 0 ? false : true);
	}
	else if(cvar == hss_shotgun)
	{
		ss_shotgun = (StringToInt(newVal) == 0 ? false : true);
	}
	else if(cvar == hss_crossbow)
	{
		ss_crossbow = (StringToInt(newVal) == 0 ? false : true);
	}
	else if(cvar == hss_pistol)
	{
		ss_pistol = (StringToInt(newVal) == 0 ? false : true);
	}
	else if(cvar == hss_rpg)
	{
		ss_rpg = (StringToInt(newVal) == 0 ? false : true);
	}
	else if(cvar == hss_frag)
	{
		ss_frag = (StringToInt(newVal) == 0 ? false : true);
	}
	else if(cvar == hss_ar2)
	{
		ss_ar2 = (StringToInt(newVal) == 0 ? false : true);
	}
	else if(cvar == hss_smg1)
	{
		ss_smg1 = (StringToInt(newVal) == 0 ? false : true);
	}
	else if(cvar == hss_slam)
	{
		ss_slam = (StringToInt(newVal) == 0 ? false : true);
	}
	else if(cvar == hss_melee)
	{
		ss_melee = (StringToInt(newVal) == 0 ? false : true);
	}
	else if(cvar == hss_357)
	{
		ss_357 = (StringToInt(newVal) == 0 ? false : true);
	}
	else if(cvar == hss_shotgun_defaultclip)
	{
		ss_shotgun_defaultclip = StringToInt(newVal);
	}
	else if(cvar == hss_shotgun_maxclip)
	{
		ss_shotgun_maxclip = StringToInt(newVal);
	}
	else if(cvar == hss_shotgun_damage_multiplier)
	{
		ss_shotgun_damage_multiplier = StringToFloat(newVal);
	}
	else if(cvar == hss_shotgun_refire)
	{
		ss_shotgun_refire = (StringToFloat(newVal) - 0.7);
	}
}

public InitClientHooks(Handle:config)
{
	//PreThink post hook
	new offset = GameConfGetOffset(config, "PreThink");
	hPreThink = DHookCreate(offset, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity, PreThinkPost);
	
	//Weapon_Equip post hook
	offset = GameConfGetOffset(config, "Weapon_Equip");
	hWeapon_Equip = DHookCreate(offset, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity, Weapon_EquipPost);
	DHookAddParam(hWeapon_Equip, HookParamType_CBaseEntity);
	
	//Spawn post
	offset = GameConfGetOffset(config, "Spawn");
	hSpawnHook = DHookCreate(offset, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity, SpawnPost);
	
	//OnTakeDamage pre
	offset = GameConfGetOffset(config, "OnTakeDamage");
	hOnTakeDamage = DHookCreate(offset, HookType_Entity, ReturnType_Int, ThisPointer_CBaseEntity, OnTakeDamagePre);
	DHookAddParam(hOnTakeDamage, HookParamType_ObjectPtr);
}

public InitShotgunHooks(Handle:config)
{
	//GetMaxClip1 pre
	new offset = GameConfGetOffset(config, "GetMaxClip1");
	hGetMaxClip1 = DHookCreate(offset, HookType_Entity, ReturnType_Int, ThisPointer_CBaseEntity, GetMaxClip1Pre);
	
	//GetDefaultClip1 pre
	offset = GameConfGetOffset(config, "GetDefaultClip1");
	hGetDefaultClip1 = DHookCreate(offset, HookType_Entity, ReturnType_Int, ThisPointer_CBaseEntity, GetDefaultClip1Pre);
	
	//AllowAutoSwitchFrom pre
	offset = GameConfGetOffset(config, "AllowAutoSwitchFrom");
	hAllowAutoSwitchFrom = DHookCreate(offset, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity, AllowAutoSwitchFromPre);
	
	//Reload post
	offset = GameConfGetOffset(config, "Reload");
	hReloadShotgun = DHookCreate(offset, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity, ReloadShotgunPost);
	
	//PrimaryAttack post
	offset = GameConfGetOffset(config, "PrimaryAttack");
	hPrimaryAttackShotgun = DHookCreate(offset, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity, PrimaryAttackShotgunPost);
	
	//SecondaryAttack post
	offset = GameConfGetOffset(config, "SecondaryAttack");
	hSecondaryAttackShotgun = DHookCreate(offset, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity, SecondaryAttackShotgunPost);
}

public InitFragHooks(Handle:config)
{
	//Operator_HandleAnimEvent pre hook
	new offset = GameConfGetOffset(config, "Operator_HandleAnimEvent");
	hOperator_HandleAnimEvent = DHookCreate(offset, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity, Operator_HandleAnimEventPre);
	DHookAddParam(hOperator_HandleAnimEvent, HookParamType_ObjectPtr);
	DHookAddParam(hOperator_HandleAnimEvent, HookParamType_CBaseEntity);
}

public InitCrossbowHooks(Handle:config)
{
	//HasWeaponIdleTimeElapsed pre
	new offset = GameConfGetOffset(config, "HasWeaponIdleTimeElapsed");
	hHasWeaponIdleTimeElapsed = DHookCreate(offset, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity, HasWeaponIdleTimeElapsedPre);
	
	//PrimaryAttack post
	offset = GameConfGetOffset(config, "PrimaryAttack");
	hPrimaryAttackCrossbow = DHookCreate(offset, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity, PrimaryAttackCrossbowPost);
	
	//Reload post
	offset = GameConfGetOffset(config, "Reload");
	hReloadCrossbow = DHookCreate(offset, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity, ReloadCrossbowPre);
}

public /*Captain*/HookClient(client)
{
	PrintToServer("Hooking client: %i", client);
	DHookEntity(hPreThink, true, client);
	DHookEntity(hWeapon_Equip, true, client);
	DHookEntity(hSpawnHook, true, client);
	DHookEntity(hOnTakeDamage, false, client);
}

public HookExistingClient(client)
{
	HookClient(client);
	
	new weaponIndex = Client_GetWeapon(client, "weapon_shotgun");
	if(weaponIndex != -1)
		HookShotgun(weaponIndex);
	
	weaponIndex = Client_GetWeapon(client, "weapon_frag");
	if(weaponIndex != -1)
		HookFrag(weaponIndex);
	
	weaponIndex = Client_GetWeapon(client, "weapon_crossbow");
	if(weaponIndex != -1)
		HookCrossbow(weaponIndex);
}

public UnhookClient(client)
{
}

public HookShotgun(shotgunIndex)
{
	DHookEntity(hGetMaxClip1, false, shotgunIndex);
	DHookEntity(hGetDefaultClip1, false, shotgunIndex);
	DHookEntity(hAllowAutoSwitchFrom, false, shotgunIndex);
	DHookEntity(hReloadShotgun, true, shotgunIndex);
	DHookEntity(hPrimaryAttackShotgun, true, shotgunIndex);
	DHookEntity(hSecondaryAttackShotgun, true, shotgunIndex);
}

public HookFrag(fragIndex)
{
	DHookEntity(hOperator_HandleAnimEvent, false, fragIndex);
}

public HookCrossbow(crossbowIndex)
{
	DHookEntity(hHasWeaponIdleTimeElapsed, false, crossbowIndex);
	DHookEntity(hPrimaryAttackCrossbow, true, crossbowIndex);
	DHookEntity(hReloadCrossbow, false, crossbowIndex);
	//SetEntProp(crossbowIndex, Prop_Data, "m_bReloadsSingly", false);
}

public Steam_FullyLoaded()
{
	new Handle:teamplay = FindConVar("mp_teamplay");
	if(teamplay != INVALID_HANDLE)
	{
		if(GetConVarBool(teamplay))
			Steam_SetGameDescription("Team Shell Shock");
		else
			Steam_SetGameDescription("Shell Shock");
	}
	else
		Steam_SetGameDescription("Shell Shock");
}
public OnClientPutInServer(client)
{
	PrintToServer("Client %i connected", client);
	HookClient(client);
}

public OnClientDisconnect(client)
{
	PrintToServer("Client %i disconnected", client);
	UnhookClient(client);
}

public Action:OnPlayerRunCmd(client, &buttons, &impules, Float:vec[3], Float:angles[3], &weapon)
{
	if(IsFakeClient(client))
		return Plugin_Continue;
	
	//Respawn if we're dead, pushing buttons, and it's been half a second since we died.
	if(!IsPlayerAlive(client))
	{
		new fAnyButtonDown = (buttons & ~IN_SCORE)
		new Float:deathTime = GetEntPropFloat(client, Prop_Send, "m_flDeathTime");
		if(fAnyButtonDown && (GetGameTime() >= (deathTime + ss_respawn_time)))
		{
			SDKCall(hSpawnCall, client);
			return Plugin_Continue;
		}
		//PrintToServer("Player %i is trying to move while not alive", client);
	}
	
	//Stop players from sprinting.
	if(buttons & IN_SPEED)
	{
		buttons &= ~IN_SPEED;
	}
	
	return Plugin_Continue;
}

public MRESReturn:SpawnPost(this)
{
	//PrintToServer("Client %i spawn", entity);
	//Spawn protection
	nextEligibleDamageTime[this] = GetGameTime() + 0.5;
	//Strip all that stuff they got in their initial spawn.
	SDKCall(hRemoveAllItems, this, 0);
	
	GivePlayerSpawnWeapons(this);
	return MRES_Ignored;
}

/* AMMODEFS: Name, Index, Maximum Carry
* AR2, 				1,	60
* AR2AltFire, 		2,	3
* Pistol, 			3,	150
* SMG1, 			4,	225
* 357, 				5,	12
* XBowBolt, 		6,	10
* Buckshot, 		7,	30
* RPG_Round, 		8,	3
* SMG1_Grenade, 	9,	3
* Grenade, 			10, 5
* slam, 			11, 5
*/
GivePlayerSpawnWeapons(client)
{
	if(ss_physcannon)
	{
		Client_GiveWeapon(client, "weapon_physcannon", false);
	}
	if(ss_crossbow)
	{
		Client_GiveWeapon(client, "weapon_crossbow", false);
		SDKCall(hGiveAmmo, client, 10, 6, 1);
	}
	if(ss_pistol)
	{
		Client_GiveWeapon(client, "weapon_pistol", false);
		SDKCall(hGiveAmmo, client, 150, 3, 1);
	}
	if(ss_rpg)
	{
		Client_GiveWeapon(client, "weapon_rpg", false);
		SDKCall(hGiveAmmo, client, 3, 8, 1);
	}
	if(ss_frag)
	{
		//Frag
		Client_GiveWeapon(client, "weapon_frag", false);
		SDKCall(hGiveAmmo, client, 5, 10, 1);
	}
	if(ss_ar2)
	{
		Client_GiveWeapon(client, "weapon_ar2", false);
		SDKCall(hGiveAmmo, client, 60, 1, 1);
		SDKCall(hGiveAmmo, client, 3, 2, 1);
	}
	if(ss_smg1)
	{
		Client_GiveWeapon(client, "weapon_smg1", false);
		SDKCall(hGiveAmmo, client, 225, 4, 1);
		SDKCall(hGiveAmmo, client, 3, 9, 1);
	}
	if(ss_slam)
	{
		Client_GiveWeapon(client, "weapon_slam", false);
		SDKCall(hGiveAmmo, client, 5, 11, 1);
	}
	if(ss_melee)
	{
		//Check model to check which melee weapon to give them.
		new String:model[128];
		GetClientModel(client, model, 128);
		if(StrContains(model, "combine", false) != -1)
		{
			Client_GiveWeapon(client, "weapon_stunstick", false);
		}
		else
		{
			Client_GiveWeapon(client, "weapon_crowbar", false);
		}
	}
	if(ss_357)
	{
		Client_GiveWeapon(client, "weapon_357", false);
		SDKCall(hGiveAmmo, client, 12, 5, 1);
	}
	if(ss_shotgun)
	{
		//Grant them the Shotgun.
		new shotgunIndex = Client_GiveWeapon(client, "weapon_shotgun");
		SDKCall(hGiveAmmo, client, 30, 7, 1);
		if(shotgunIndex != -1)
		{
			//Ugly: Work-around, so shotgun isn't hooked twice.
			SetEntProp(shotgunIndex, Prop_Send, "m_iClip1", 8);
		}
		else
		{
			PrintToServer("Unable to give client %i the shotgun", client);
		}
	}
}

/*
* Vector	m_vecDamageForce; //0
* Vector	m_vecDamagePosition; //16
* Vector	m_vecReportedPosition; //32
* EHANDLE	m_hInflictor; //36
* EHANDLE	m_hAttacker; //40
* EHANDLE	m_hWeapon; //44
* float		m_flDamage; //48
* float	 	m_flMaxDamage; //52
* float	 	m_flBaseDamage;	 //56
* int	 	m_bitsDamageType; //60
* int	 	m_iDamageCustom; //64
* int	 	m_iDamageStats; //68
* int	 	m_iAmmoType; //72
*/
public MRESReturn:OnTakeDamagePre(this, Handle:hReturn, Handle:hParams)
{
	if(IsFakeClient(this))
		return MRES_Ignored;
	new attacker = DHookGetParamObjectPtrVar(hParams, 1, 40, ObjectValueType_Ehandle);
	new inflictor = DHookGetParamObjectPtrVar(hParams, 1, 36, ObjectValueType_Ehandle);
	
	if(attacker == -1 || this == -1 || (this == attacker) || inflictor == -1)
		return MRES_Ignored;
	//Spawn protection
	if(nextEligibleDamageTime[this] > GetGameTime())
	{
		DHookSetParamObjectPtrVar(hParams, 1, 48, ObjectValueType_Float, 0.0);
		return MRES_Handled ;
	}
	
	new ammoType = DHookGetParamObjectPtrVar(hParams, 1, 72, ObjectValueType_Int);
	//Modify the damage taken from buckshot
	if(ammoType == 7)
	{
		new Float:damage = DHookGetParamObjectPtrVar(hParams, 1, 48, ObjectValueType_Float);
		damage *= ss_shotgun_damage_multiplier;
		DHookSetParamObjectPtrVar(hParams, 1, 48, ObjectValueType_Float, damage);
		
		new Float:damageForce[3];
		DHookGetParamObjectPtrVarVector(hParams, 1, 0, ObjectValueType_Vector, damageForce);
		ScaleVector(damageForce, 10000.0);//Because lol
		DHookSetParamObjectPtrVarVector(hParams, 1, 0, ObjectValueType_Vector, damageForce);
		
		return MRES_Handled ;
	}
	return MRES_Ignored;
}
public MRESReturn:PreThinkPost(this)
{
	if(IsFakeClient(this) || !IsPlayerAlive(this))
		return MRES_Ignored;
		
	//Set the player's speed.
	SetEntPropFloat(this, Prop_Send, "m_flMaxspeed", ss_playerspeed);
		
	return MRES_Ignored;
}

public MRESReturn:Weapon_EquipPost(this, Handle:hParams)
{
	if(IsFakeClient(this) || !IsPlayerAlive(this))
		return MRES_Ignored;
		
	new weapon = DHookGetParam(hParams, 1);
	
	if(weapon == -1)
	{
		PrintToServer("Invalid weapon in Weapon_EquipPost for Client: %i", this);
		return MRES_Ignored;
	}
	
	new String:weaponname[64];
	GetEntityClassname(weapon, weaponname, 64);
	
	//PrintToServer("Client %i picked up weapon %s", this, weaponname);
	
	if(strcmp("weapon_shotgun", weaponname) == 0)
	{
		HookShotgun(weapon);
	}
	else if(strcmp("weapon_frag", weaponname) == 0)
	{
		HookFrag(weapon);
	}
	else if(strcmp("weapon_crossbow", weaponname) == 0)
	{
		HookCrossbow(weapon);
		Weapon_SetOwner(weapon, this);
	}
		
	return MRES_Ignored;
}

public MRESReturn:Operator_HandleAnimEventPre(this, Handle:hParams)
{
	if(ThrowContactGrenade(this, hParams) == true)
		return MRES_Supercede;
	return MRES_Ignored;
}

public MRESReturn:GetMaxClip1Pre(this, Handle:hReturn)
{
	DHookSetReturn(hReturn, ss_shotgun_maxclip); 
	return MRES_Supercede;
}
public MRESReturn:GetDefaultClip1Pre(this, Handle:hReturn)
{
	DHookSetReturn(hReturn, ss_shotgun_defaultclip);
	return MRES_Supercede;
}
public MRESReturn:AllowAutoSwitchFromPre(this, Handle:hReturn)
{
	DHookSetReturn(hReturn, false); 
	return MRES_Supercede;
}
public MRESReturn:ReloadShotgunPost(this, Handle:hReturn)
{
	SetShotgunRefire(this);
	return MRES_Ignored;
}
public MRESReturn:PrimaryAttackShotgunPost(this)
{
	SetShotgunRefire(this);
}
public MRESReturn:SecondaryAttackShotgunPost(this)
{
	SetShotgunRefire(this);
}
public MRESReturn:ReloadCrossbowPre(this, Handle:hReturn)
{
	//SetEntProp(this, Prop_Send, "m_bMustReload", false);
	//DHookSetReturn(hReturn, true);
	return MRES_Ignored;
}
SetShotgunRefire(shotgun)
{
	new Float:refire = GetEntPropFloat(shotgun, Prop_Send, "m_flNextPrimaryAttack");
	PrintToServer("Shotgun refire was: %f", refire);
	//.7 - (desired refire rate) = ss_shotgun_refire
	refire += ss_shotgun_refire;
	PrintToServer("Shotgun refire is now: %f", refire);
	SetEntPropFloat(shotgun, Prop_Send, "m_flNextPrimaryAttack", refire);
}
bool:ThrowContactGrenade(weaponFrag, Handle:hParams)
{
	if(hParams == INVALID_HANDLE)
	{
		PrintToServer("ThrowContactGrenade hParams are invalid!");
		return false;
	}
	new eventAnim = DHookGetParamObjectPtrVar(hParams, 1, 0, ObjectValueType_Int);
	new client = DHookGetParam(hParams, 2);
	
	if(client == -1)
		return false;
	
	//Lobbed the grenade?
	if(eventAnim != 3016)
		return false;
	
	// case EVENT_WEAPON_THROW3:
	
	//LobGrenade( pOwner );
	new Float:vecEye[3];
	GetClientEyePosition(client, vecEye);
	new Float:eyeAngles[3];
	GetClientEyeAngles(client, eyeAngles);
	new Float:vForward[3];
	new Float:vRight[3];
	new Float:vUp[3];
	GetAngleVectors(eyeAngles, vForward, vRight, vUp);
	
	new Float:tempFwd[3];
	tempFwd[0] = vForward[0];
	tempFwd[1] = vForward[1];
	tempFwd[2] = vForward[2];
	
	ScaleVector(tempFwd, 18.0);
	ScaleVector(vRight, 8.0);
	
	new Float:vecSrc[3];
	AddVectors(vecEye, tempFwd, vecSrc);
	AddVectors(vecSrc, vRight, vecSrc);
	vecSrc[2] -= 8;
	
	//CheckThrowPosition
	new Float:mins[3] = {-6.0, -6.0, -6.0};
	new Float:max[3] = {6.0, 6.0, 6.0};
	TR_TraceHull(vecEye, vecSrc, mins, max, MASK_PLAYERSOLID);
	if(TR_DidHit())
	{
		TR_GetEndPosition(vecSrc);
	}
	
	new Float:vecThrow[3];
	Entity_GetAbsVelocity(client, vecThrow);
	ScaleVector(vForward, 1200.0);
	AddVectors(vecThrow, vForward, vecThrow);
	vecThrow[2] += 50;
	
	new contactGrenade = CreateEntityByName("npc_contactgrenade");
	if(contactGrenade == -1)
	{
		PrintToServer("Unable to make contact grenade");
		return false;
	}
	
	Entity_SetAbsOrigin(contactGrenade, vecSrc);
	Entity_SetAbsVelocity(contactGrenade, vecThrow);
	SetEntPropEnt(contactGrenade, Prop_Send, "m_hThrower", client);
	Entity_SetOwner(contactGrenade, client);
	DispatchSpawn(contactGrenade);
	//Aaaand it's a nuke.  Just because.
	SetEntPropFloat(contactGrenade, Prop_Send, "m_flDamage", 240.0);
	SetEntPropFloat(contactGrenade, Prop_Send, "m_DmgRadius", 400.0);
	//m_hThrower
	SDKCall(hSetAnimation, client, 5/*PLAYER_ATTACK1*/);
	
	//DecrementAmmo( pOwner );
	new primaryAmmoCount = 0;
	new secondaryAmmoCount = -1;
	Client_GetWeaponPlayerAmmo(client, "weapon_frag", primaryAmmoCount, secondaryAmmoCount);
	Client_SetWeaponPlayerAmmoEx(client, weaponFrag, primaryAmmoCount - 1, secondaryAmmoCount);
	
	//fThrewGrenade = true;
	SetEntProp(weaponFrag, Prop_Send, "m_bRedraw", 1);
	SetEntPropFloat(weaponFrag, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() + 0.5);
	SetEntPropFloat(weaponFrag, Prop_Send, "m_flNextSecondaryAttack", GetGameTime() + 0.5);
	SetEntPropFloat(weaponFrag, Prop_Send, "m_flTimeWeaponIdle", 340282326356119256160033759537265639424.0);
	
	return true;
}

public MRESReturn:HasWeaponIdleTimeElapsedPre(this, Handle:hReturn)
{
	new Float:m_flNextPrimaryAttack = GetEntPropFloat(this, Prop_Send, "m_flNextPrimaryAttack");
	if(GetGameTime() >= m_flNextPrimaryAttack)
	{
		PrintToServer("HasWeaponIdleTimeElapsed return true");
		DHookSetReturn(hReturn, true);
	}
	else
	{
		//PrintToServer("HasWeaponIdleTimeElapsed return false");
		//DHookSetReturn(hReturn, false);
		DHookSetReturn(hReturn, true);
	}
	return MRES_Supercede;
}

public MRESReturn:PrimaryAttackCrossbowPost(this)
{
	PrintToServer("PrimaryAttackCrossbowPost");
	new Float:m_flNextAttack = GetEntPropFloat(this, Prop_Send, "m_flNextPrimaryAttack");
	PrintToServer("m_flNextAttack was: %f", m_flNextAttack);
	m_flNextAttack -= 500.0;
	PrintToServer("m_flNextAttack is now: %f", m_flNextAttack);
	SetEntPropFloat(this, Prop_Send, "m_flNextPrimaryAttack", m_flNextAttack);
	SetEntPropFloat(this, Prop_Send, "m_flNextSecondaryAttack", m_flNextAttack);
	SetEntPropFloat(this, Prop_Send, "m_flTimeWeaponIdle", m_flNextAttack);
	
	return MRES_Ignored;
}

/*
 * if ( m_iClip1 <= 0 )
	{
	if ( !m_bFireOnEmpty )
	{
	Reload();
	}
	else
	{
	WeaponSound( EMPTY );
	m_flNextPrimaryAttack = 0.15;
	}
	
	return;
	}
	
	CBasePlayer *pOwner = ToBasePlayer( GetOwner() );
	
	if ( pOwner == NULL )
	return;
	
	#ifndef CLIENT_DLL
	Vector vecAiming	= pOwner->GetAutoaimVector( 0 );	
	Vector vecSrc		= pOwner->Weapon_ShootPosition();
	
	QAngle angAiming;
	VectorAngles( vecAiming, angAiming );
	
	CCrossbowBolt *pBolt = CCrossbowBolt::BoltCreate( vecSrc, angAiming, GetHL2MPWpnData().m_iPlayerDamage, pOwner );
	
	CCrossbowBolt *CCrossbowBolt::BoltCreate( const Vector &vecOrigin, const QAngle &angAngles, int iDamage, CBasePlayer *pentOwner )
	{
	// Create a new entity with CCrossbowBolt private data
	CCrossbowBolt *pBolt = (CCrossbowBolt *)CreateEntityByName( "crossbow_bolt" );
	UTIL_SetOrigin( pBolt, vecOrigin );
	pBolt->SetAbsAngles( angAngles );
	pBolt->Spawn();
	pBolt->SetOwnerEntity( pentOwner );
	
	pBolt->m_iDamage = iDamage;
	
	return pBolt;
	}
	
	if ( pOwner->GetWaterLevel() == 3 )
	{
	pBolt->SetAbsVelocity( vecAiming * BOLT_WATER_VELOCITY );
	}
	else
	{
	pBolt->SetAbsVelocity( vecAiming * BOLT_AIR_VELOCITY );
	}
	
	#endif
	
	m_iClip1--;
	
	pOwner->ViewPunch( QAngle( -2, 0, 0 ) );
	
	WeaponSound( SINGLE );
	WeaponSound( SPECIAL2 );
	
	SendWeaponAnim( ACT_VM_PRIMARYATTACK );
	
	if ( !m_iClip1 && pOwner->GetAmmoCount( m_iPrimaryAmmoType ) <= 0 )
	{
	// HEV suit - indicate out of ammo condition
	pOwner->SetSuitUpdate("!HEV_AMO0", FALSE, 0);
	}
	
	m_flNextPrimaryAttack = m_flNextSecondaryAttack	= gpGlobals->curtime + 0.75;
	
	DoLoadEffect();
	SetChargerState( CHARGER_STATE_DISCHARGE );
	
	// Signal a reload
	m_bMustReload = true;
	
	SetWeaponIdleTime( gpGlobals->curtime + SequenceDuration( ACT_VM_PRIMARYATTACK ) );
 * */
//TODO: Make this a pre hook and tweak the entire function to taste.
//This isn't going to work.  There's no way to set the damage with this
public MRESReturn:PrimaryAttackCrossbowPre(this)
{
	PrintToServer("Crossbow Primary Attack");
	new Handle:client = Weapon_GetOwner(this);
	if(client == -1)
	{
		PrintToServer("Client is null in Crossbow PrimaryAttack");
		return MRES_Ignored;
	}
	
	new m_iClip1 = Weapon_GetPrimaryClip(this);
	if(m_iClip1 <= 0)
	{
		//SDKCall(hReloadCrossbow);
		return MRES_Supercede;
	}
	
	//Vector vecAiming	= pOwner->GetAutoaimVector( 0 );
	/* 	Vector	forward;
		AngleVectors( EyeAngles() + m_Local.m_vecPunchAngle, &forward );
	 * */
	//EyeAngles() 
	new Float:vecEyeAngles[3];
	GetClientEyeAngles(client, vecEyeAngles);
	PrintToServer("Player Eye Angles: (%f, %f, %f)", vecEyeAngles[0], vecEyeAngles[1], vecEyeAngles[2]);
	//m_Local.m_vecPunchAngle
	new Float:vecPunchAngle[3];
	GetEntPropVector(client, Prop_Send, "m_vecPunchAngle", vecPunchAngle);
	PrintToServer("Player punch angle: (%f, %f, %f)", vecPunchAngle[0], vecPunchAngle[1], vecPunchAngle[2]);
	//EyeAngles() + m_Local.m_vecPunchAngle
	new Float:vecEyeResult[3];
	AddVectors(vecEyeAngles, vecPunchAngle, vecEyeResult);
	PrintToServer("Player EyeAngles + Punch angle: (%f, %f, %f)", vecEyeResult[0], vecEyeResult[1], vecEyeResult[2]);
	//AngleVectors( EyeAngles() + m_Local.m_vecPunchAngle, &forward );
	new Float:vecAiming[3];
	GetAngleVectors(vecEyeResult, vecAiming, NULL_VECTOR, NULL_VECTOR);
	PrintToServer("GetAutoaimVector: (%f, %f, %f)", vecAiming[0], vecAiming[1], vecAiming[2]);
	
	//Vector vecSrc		= pOwner->Weapon_ShootPosition();
	/*
	 * AngleVectors( GetAbsAngles(), &forward, &right, &up );
		
		Vector vecSrc = GetAbsOrigin() 
		+ forward * m_HackedGunPos.y 
		+ right * m_HackedGunPos.x 
		+ up * m_HackedGunPos.z;
	 * */
	
	new Float:clientAngles[3];
	GetClientAbsAngles(client, clientAngles);
	new Float:vecForward[3];
	new Float:vecRight[3];
	new Float:vecUp[3];
	GetAngleVectors(clientAngles, vecForward, vecRight, vecUp);
	//m_HackedGunPos = (0, 32, 0)
	ScaleVector(vecForward, 32.0);
	
	new Float:vecSrc[3];
	GetClientAbsOrigin(client, vecSrc);
	AddVectors(vecSrc, vecForward, vecSrc);
	
	//GetClientEyePosition(client, vecSrc);
	PrintToServer("Weapon_ShootPosition: (%f, %f, %f)", vecSrc[0], vecSrc[1], vecSrc[2]);
	
	//QAngle angAiming;
	//VectorAngles( vecAiming, angAiming );
	new Float:angAiming[3];
	GetVectorAngles(vecAiming, angAiming);
	PrintToServer("angAiming: (%f, %f, %f)", angAiming[0], angAiming[1], angAiming[2]);
	
	new crossbowBolt = CreateEntityByName("crossbow_bolt");
	if(crossbowBolt == -1)
	{
		PrintToServer("Unable to make crossbow bolt");
		return MRES_Ignored;
	}
	
	Entity_SetAbsOrigin(crossbowBolt, vecSrc);
	Entity_SetAbsAngles(crossbowBolt, angAiming);
	Entity_SetOwner(crossbowBolt, client);
	DispatchSpawn(crossbowBolt);
	
	PrintToServer("vecAiming before: (%f, %f, %f)", vecAiming[0], vecAiming[1], vecAiming[2]);
	ScaleVector(vecAiming, 7000.0);
	PrintToServer("vecAiming after: (%f, %f, %f)", vecAiming[0], vecAiming[1], vecAiming[2]);
	
	Entity_SetAbsVelocity(crossbowBolt, vecAiming);
	new Float:vecCrossbowBoltVel[3];
	Entity_GetAbsVelocity(crossbowBolt, vecCrossbowBoltVel);
	PrintToServer("Crossbow bolt velocity: (%f, %f, %f)", vecCrossbowBoltVel[0], vecCrossbowBoltVel[1], vecCrossbowBoltVel[2]);
	//SetEntProp(crossbowBolt, Prop_Send, "m_iDamage", 240.0);
	
	//m_iClip1--;
	//DecrementAmmo( pOwner );
	new primaryAmmoCount = 0;
	new secondaryAmmoCount = -1;
	Client_GetWeaponPlayerAmmo(client, "weapon_crossbow", primaryAmmoCount, secondaryAmmoCount);
	Client_SetWeaponPlayerAmmoEx(client, this, primaryAmmoCount - 1, secondaryAmmoCount);
	
	//pOwner->ViewPunch( QAngle( -2, 0, 0 ) );
	new Float:vecPunchAngleVel[3];
	GetEntPropVector(client, Prop_Send, "m_vecPunchAngleVel", vecPunchAngleVel);
	new Float:vecPunchAngleAdd[3];
	vecPunchAngleAdd[0] = -40;
	AddVectors(vecPunchAngleVel, vecPunchAngleAdd, vecPunchAngleVel);
	PrintToServer("m_vecPunchAngleVel: (%f, %f, %f)", vecPunchAngleVel[0], vecPunchAngleVel[1], vecPunchAngleVel[2]);
	SetEntPropVector(client, Prop_Send, "m_vecPunchAngleVel", vecPunchAngleVel);
	
	//WeaponSound( SINGLE );
	//WeaponSound( SPECIAL2 );
	
	//SendWeaponAnim( ACT_VM_PRIMARYATTACK );
	
	/*if ( !m_iClip1 && pOwner->GetAmmoCount( m_iPrimaryAmmoType ) <= 0 )
	{
		// HEV suit - indicate out of ammo condition
		pOwner->SetSuitUpdate("!HEV_AMO0", FALSE, 0);
	}*/
	
	//m_flNextPrimaryAttack = m_flNextSecondaryAttack	= gpGlobals->curtime + 0.75;
	//Primary Attack set to .5
	new Float:m_flNextAttack = GetGameTime() + 0.25;//GetEntPropFloat(this, Prop_Send, "m_flNextPrimaryAttack");
	SetEntPropFloat(this, Prop_Send, "m_flNextPrimaryAttack", m_flNextAttack);
	SetEntPropFloat(this, Prop_Send, "m_flNextSecondaryAttack", m_flNextAttack);
	
	//No idle
	SDKCall(hSetWeaponIdleTime, this, GetGameTime() - 1.5);
	
	return MRES_Supercede;
}