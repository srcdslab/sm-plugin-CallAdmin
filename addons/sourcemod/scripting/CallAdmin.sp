#include <sourcemod>
#include <clientprefs>
#include <cstrike>
#include <basecomm>

#include <discordWebhookAPI>
#include <multicolors>

#undef REQUIRE_PLUGIN
#tryinclude <AFKManager>
#tryinclude <sourcecomms>
#tryinclude <sourcebanschecker>
#tryinclude <zombiereloaded>
#define REQUIRE_PLUGIN

#pragma newdecls required

#define CHAT_PREFIX "{gold}[Call Admin]{orchid}"

#define WEBHOOK_URL_MAX_SIZE	1000

ConVar g_cvWebhook, g_cvWebhookRetry;

ConVar g_cvCooldown, g_cvAdmins, g_cvNetPublicAddr, g_cvPort;
ConVar g_cCountBots = null;

Handle g_hLastUse = INVALID_HANDLE;

int g_iLastUse[MAXPLAYERS+1] = { -1, ... }

bool g_bLate = false;
bool g_Plugin_AFKManager = false;
bool g_Plugin_ZR = false;
bool g_Plugin_SourceBans = false;
bool g_Plugin_SourceComms = false;

public Plugin myinfo = 
{
	name = "CallAdmin",
	author = "inGame, maxime1907, .Rushaway",
	description = "Send a calladmin message to discord and forum",
	version = "1.10.5",
	url = "https://nide.gg"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLate = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	RegConsoleCmd("sm_calladmin", Command_CallAdmin, "Send a message to call admins.");

	g_hLastUse = RegClientCookie("calladmin_last_use", "Last call admin", CookieAccess_Protected);

	g_cvWebhook = CreateConVar("sm_calladmin_webhook", "", "The webhook URL of your Discord channel.", FCVAR_PROTECTED);
	g_cvWebhookRetry = CreateConVar("sm_calladmin_webhook_retry", "3", "Number of retries if webhook fails.", FCVAR_PROTECTED);

	g_cvCooldown = CreateConVar("sm_calladmin_cooldown", "600", "Cooldown in seconds before a player can use sm_calladmin again", FCVAR_NONE);
	g_cCountBots = CreateConVar("sm_calladmin_count_bots", "0", "Should we count bots as players ?(1 = Yes, 0 = No)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvAdmins = CreateConVar("sm_calladmin_block", "0", "Block calladmin usage if an admin is online?(1 = Yes, 0 = No)", FCVAR_PROTECTED, true, 0.0, true, 1.0);

	AutoExecConfig(true);

	// Late load
	if (g_bLate)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i))
			{
				OnClientPutInServer(i);
			}
		}
	}
}

public void OnAllPluginsLoaded()
{
	g_Plugin_AFKManager = LibraryExists("AFKManager");
	g_Plugin_SourceBans = LibraryExists("sourcebans++");
	g_Plugin_SourceComms = LibraryExists("sourcecomms++");
	g_Plugin_ZR = LibraryExists("zombiereloaded");

	LogMessage("[CallAdmin] Capabilities: AFKManager: %s - SourcebansPP: %s - SourcecommsPP: %s - ZombieReloaded: %s",
		(g_Plugin_AFKManager ? "Loaded" : "Not loaded"),
		(g_Plugin_SourceBans ? "Loaded" : "Not loaded"),
		(g_Plugin_SourceComms ? "Loaded" : "Not loaded"),
		(g_Plugin_ZR ? "Loaded" : "Not loaded"));
}

public void OnLibraryAdded(const char[] sName)
{
	if (strcmp(sName, "zombiereloaded", false) == 0)
		g_Plugin_ZR = true;
	if (strcmp(sName, "sourcebans++", false) == 0)
		g_Plugin_SourceBans = true;
	if (strcmp(sName, "sourcecomms++", false) == 0)
		g_Plugin_SourceComms = true;
}

public void OnLibraryRemoved(const char[] sName)
{
	if (strcmp(sName, "zombiereloaded", false) == 0)
		g_Plugin_ZR = false;
	if (strcmp(sName, "sourcebans++", false) == 0)
		g_Plugin_SourceBans = false;
	if (strcmp(sName, "sourcecomms++", false) == 0)
		g_Plugin_SourceComms = true;
}

public void OnClientPutInServer(int client)
{
	if (AreClientCookiesCached(client))
		ReadClientCookies(client);
}

public void OnClientDisconnect(int client)
{
	SetClientCookies(client);
}

public void OnClientCookiesCached(int client)
{
	ReadClientCookies(client);
}

public void ReadClientCookies(int client)
{
	char sValue[32];

	GetClientCookie(client, g_hLastUse, sValue, sizeof(sValue));
	g_iLastUse[client] = (sValue[0] == '\0' ? 0 : StringToInt(sValue));
}

public void SetClientCookies(int client)
{
	char sValue[32];

	Format(sValue, sizeof(sValue), "%i", g_iLastUse[client]);
	SetClientCookie(client, g_hLastUse, sValue);
}

public Action Command_CallAdmin(int client, int args)
{
	if (!client)
	{
		ReplyToCommand(client, "[SM] Cannot use this command from server console.");
		return Plugin_Handled;
	}

	if (client)
	{
		int iGagType = 0;
		bool bIsGagged = false;

		if (g_Plugin_SourceComms)
		{
		#if defined _sourcecomms_included
			iGagType = SourceComms_GetClientGagType(client);
		#endif
			bIsGagged = iGagType > 0
		}
		else
		{
			bIsGagged = BaseComm_IsClientGagged(client)
		}

		if (bIsGagged)
		{
			CReplyToCommand(client, "%s You are not allowed to use {gold}Call Admin {orchid}since you are gagged.", CHAT_PREFIX);
			return Plugin_Handled;
		}
	}

	if(GetAdminFlag(GetUserAdmin(client), Admin_Ban))
	{
		CReplyToCommand(client, "%s You are an admin nigger, why the f*ck do you use that command?", CHAT_PREFIX);
		return Plugin_Handled;
	}

	int currentTime = GetTime();
	int cooldownDiff = currentTime - g_iLastUse[client];
	if (cooldownDiff < g_cvCooldown.IntValue)
	{
		CReplyToCommand(client, "%s You are on cooldown, wait {default}%d {orchid}seconds.", CHAT_PREFIX, g_cvCooldown.IntValue - cooldownDiff);
		return Plugin_Handled;
	}

	if(g_cvAdmins.IntValue >= 1)
	{
		int Admins = 0;
		int AfkAdmins = 0;

		for(int i = 1; i <= MaxClients; i++)
		{
			if(!IsClientInGame(i) || IsFakeClient(i))
				continue;

			if(GetAdminFlag(GetUserAdmin(i), Admin_Ban))
			{
			#if defined _AFKManager_Included
				if(g_Plugin_AFKManager)
				{
					int IdleTime;
					IdleTime = GetClientIdleTime(i);
					if(IdleTime > 30) AfkAdmins++;
				}
			#endif
				Admins++;
			}
		}

		if(Admins > AfkAdmins)
		{
			CReplyToCommand(client, "%s You can't use {gold}CallAdmin {orchid}since there is admins online. Type {red}!admins {orchid}to check currently online admins.", CHAT_PREFIX);
			return Plugin_Handled;
		}
	}

	if(args < 1)
	{
		CReplyToCommand(client, "%s sm_calladmin <reason>", CHAT_PREFIX);
		return Plugin_Handled;
	}

	g_iLastUse[client] = currentTime;

	char sTime[64];
	int iTime = GetTime();
	FormatTime(sTime, sizeof(sTime), "Date : %d/%m/%Y @ %H:%M:%S", iTime);

	char sCount[64];
	int iMaxPlayers = MaxClients;
	int iConnected = GetClientCountEx(g_cCountBots.BoolValue);
	Format(sCount, sizeof(sCount), "Players : %d/%d", iConnected, iMaxPlayers);

	char sAliveCount[64];
	if (g_Plugin_ZR)
		Format(sAliveCount, sizeof(sAliveCount), "Alive : %d Humans - %d Zombies", GetTeamAliveCount(CS_TEAM_CT), GetTeamAliveCount(CS_TEAM_T));
	else
		Format(sAliveCount, sizeof(sAliveCount), "Alive : %d CTs - %d Ts", GetTeamAliveCount(CS_TEAM_CT), GetTeamAliveCount(CS_TEAM_T));

	g_cvNetPublicAddr = FindConVar("net_public_adr");
	g_cvPort = FindConVar("hostport");

	char sConnect[256];
	char sNetIP[32], sNetPort[32];
	if (g_cvPort != null)
		GetConVarString(g_cvPort, sNetPort, sizeof (sNetPort));
	if (g_cvNetPublicAddr != null)
		GetConVarString(g_cvNetPublicAddr, sNetIP, sizeof(sNetIP));
	Format(sConnect, sizeof(sConnect), "**steam://connect/%s:%s**", sNetIP, sNetPort);

	char sMessageDiscord[4096];
	GetCmdArgString(sMessageDiscord, sizeof(sMessageDiscord));
	ReplaceString(sMessageDiscord, sizeof(sMessageDiscord), "\\n", "\n");

	char sAuth[32];
	GetClientAuthId(client, AuthId_Steam2, sAuth, sizeof(sAuth), true);

	/*		>> Will implant this when Discord will have custom link... <<
	char sInfos[2048], sClientID[256], sSteamClientID[64];	
	GetClientAuthId(client, AuthId_SteamID64, sSteamClientID, sizeof(sSteamClientID));
	Format(sClientID, sizeof(sClientID), "More infos about the caller:  %s (https://steamcommunity.com/profiles/%s)", client, sSteamClientID);*/

	char currentMap[PLATFORM_MAX_PATH];
	GetCurrentMap(currentMap, sizeof(currentMap));

	char sTimeLeft[32];
	int timeleft;
	if(GetMapTimeLeft(timeleft))
	{
		if(timeleft > 0)
			Format(sTimeLeft, sizeof(sTimeLeft), "%i:%02i", timeleft / 60, timeleft % 60);
		else if(timeleft <= 0)
			Format(sTimeLeft, sizeof(sTimeLeft), "Last Round");
	}

	char sPluginVersion[256];
	GetPluginInfo(INVALID_HANDLE, PlInfo_Version, sPluginVersion, sizeof(sPluginVersion));

	// Generate discord message
	if (g_Plugin_SourceBans)
	{
		int iClientBans = 0;
		int iClientComms = 0;

	#if defined _sourcebanschecker_included
		iClientBans = SBPP_CheckerGetClientsBans(client);
		iClientComms = SBPP_CheckerGetClientsComms(client);
	#endif

		Format(sMessageDiscord, sizeof(sMessageDiscord), "@here ```%N (%d bans - %d comms) [%s] is calling an Admin. \nCurrent map : %s \n%s \n%s \n%s \nTimeLeft : %s \nReason: %s```(*v%s*) **Quick join:** %s", client, iClientBans, iClientComms, sAuth, currentMap, sTime, sAliveCount, sCount, sTimeLeft, sMessageDiscord, sPluginVersion, sConnect);
	}
	else
	{
		Format(sMessageDiscord, sizeof(sMessageDiscord), "@here ```%N [%s] is calling an Admin. \nCurrent map : %s \n%s \n%s \n%s \nTimeLeft : %s \nReason: %s```(*v%s*) **Quick join:** %s", client, sAuth, currentMap, sTime, sAliveCount, sCount, sTimeLeft, sMessageDiscord, sPluginVersion, sConnect);
	}

	char sWebhookURL[WEBHOOK_URL_MAX_SIZE];
	g_cvWebhook.GetString(sWebhookURL, sizeof sWebhookURL);
	if(!sWebhookURL[0])
	{
		LogError("[CallAdmin] No webhook found or specified.");
		return Plugin_Handled;
	}

	SendWebHook(GetClientUserId(client), sMessageDiscord, sWebhookURL);

	return Plugin_Handled;
}

stock void SendWebHook(int userid, char sMessage[4096], char sWebhookURL[WEBHOOK_URL_MAX_SIZE])
{
	Webhook webhook = new Webhook(sMessage);

	DataPack pack = new DataPack();
	pack.WriteCell(userid);
	pack.WriteString(sMessage);
	pack.WriteString(sWebhookURL);

	webhook.Execute(sWebhookURL, OnWebHookExecuted, pack);

	delete webhook;
}

public void OnWebHookExecuted(HTTPResponse response, DataPack pack)
{
	static int retries = 0;

	pack.Reset();

	int userid = pack.ReadCell();
	int client = GetClientOfUserId(userid);

	char sMessage[4096];
	pack.ReadString(sMessage, sizeof(sMessage));

	char sWebhookURL[WEBHOOK_URL_MAX_SIZE];
	pack.ReadString(sWebhookURL, sizeof(sWebhookURL));

	delete pack;

	if (response.Status != HTTPStatus_OK)
	{
		if (retries < g_cvWebhookRetry.IntValue)
		{
			if (client && IsClientInGame(client))
				CPrintToChat(client, "%s {red}Failed to send your message. Resending it .. (%d/3)", CHAT_PREFIX, retries);

			PrintToServer("[CallAdmin] Failed to send the webhook. Resending it .. (%d/%d)", retries, g_cvWebhookRetry.IntValue);

			SendWebHook(userid, sMessage, sWebhookURL);
			retries++;
			return;
		}
		else
		{
			if (client && IsClientInGame(client))
				CPrintToChat(client, "%s {red}An error has occurred. Your message can't be sent.", CHAT_PREFIX);

			LogError("[CallAdmin] Failed to send the webhook after %d retries, aborting.", retries);
		}
	}
	else
	{
		if (client && IsClientInGame(client))
			CPrintToChat(client, "%s Message sent.\nRemember that abuse/spam of {gold}CallAdmin {orchid}will result in a chat block", CHAT_PREFIX);
	}

	retries = 0;
}

stock int GetClientCountEx(bool countBots)
{
	int iRealClients = 0;
	int iFakeClients = 0;

	for(int player = 1; player <= MaxClients; player++)
	{
		if(IsClientConnected(player))
		{
			if(IsFakeClient(player))
				iFakeClients++;
			else
				iRealClients++;
		}
	}
	return countBots ? iFakeClients + iRealClients : iRealClients;
}

stock int GetTeamAliveCount(int team)
{
	int count = 0;
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i))
			continue;
		if(IsPlayerAlive(i) && GetClientTeam(i) == team)
			count++;
	}
	return count;
}
