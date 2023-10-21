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

#define WEBHOOK_URL_MAX_SIZE			1000
#define WEBHOOK_THREAD_NAME_MAX_SIZE	100

ConVar g_cvWebhook, g_cvWebhookRetry, g_cvAvatar, g_cvUsername;
ConVar g_cvChannelType, g_cvThreadName, g_cvThreadID;

ConVar g_cvCooldown, g_cvAdmins, g_cvNetPublicAddr, g_cvPort;
ConVar g_cCountBots = null;
ConVar g_cRedirectURL = null;

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
	version = "1.12",
	url = "https://github.com/srcdslab/sm-plugin-CallAdmin"
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

	/* General config */
	g_cvWebhook = CreateConVar("sm_calladmin_webhook", "", "The webhook URL of your Discord channel.", FCVAR_PROTECTED);
	g_cvAvatar = CreateConVar("sm_calladmin_avatar", "https://avatars.githubusercontent.com/u/110772618?s=200&v=4", "URL to Avatar image.");
	g_cvUsername = CreateConVar("sm_calladmin_username", "CallAdmin", "Discord username.");
	g_cvWebhookRetry = CreateConVar("sm_calladmin_webhook_retry", "3", "Number of retries if webhook fails.", FCVAR_PROTECTED);
	g_cRedirectURL = CreateConVar("sm_calladmin_redirect", "https://nide.gg/connect/", "URL to your redirect.php file.");
	g_cvChannelType = CreateConVar("sm_calladmin_channel_type", "0", "Type of your channel: (1 = Thread, 0 = Classic Text channel");

	/* Thread config */
	g_cvThreadName = CreateConVar("sm_calladmin_threadname", "CallAdmin", "The Thread Name of your Discord forums. (If not empty, will create a new thread)", FCVAR_PROTECTED);
	g_cvThreadID = CreateConVar("sm_calladmin_threadid", "0", "If thread_id is provided, the message will send in that thread.", FCVAR_PROTECTED);

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
	char sWebhookURL[WEBHOOK_URL_MAX_SIZE];
	g_cvWebhook.GetString(sWebhookURL, sizeof sWebhookURL);
	if(!sWebhookURL[0])
	{
		LogError("[CallAdmin] No webhook found or specified.");
		CPrintToChat(client, "%s A configuration issue has been detected, can't send the weebhook.", CHAT_PREFIX);
		return Plugin_Handled;
	}

	if (!client)
	{
		ReplyToCommand(client, "[SM] Cannot use this command from server console.");
		return Plugin_Handled;
	}
	else
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
			CPrintToChat(client, "%s You are not allowed to use {gold}Call Admin {orchid}since you are gagged.", CHAT_PREFIX);
			return Plugin_Handled;
		}
	}

	if(GetAdminFlag(GetUserAdmin(client), Admin_Ban))
	{
		CPrintToChat(client, "%s You are an admin nigger, why the f*ck do you use that command?", CHAT_PREFIX);
		return Plugin_Handled;
	}

	int currentTime = GetTime();
	int cooldownDiff = currentTime - g_iLastUse[client];
	if (cooldownDiff < g_cvCooldown.IntValue)
	{
		CPrintToChat(client, "%s You are on cooldown, wait {default}%d {orchid}seconds.", CHAT_PREFIX, g_cvCooldown.IntValue - cooldownDiff);
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
					int IdleTime = GetClientIdleTime(i);
					if(IdleTime > 30) AfkAdmins++;
				}
			#endif
				Admins++;
			}
		}

		if(Admins > AfkAdmins)
		{
			CPrintToChat(client, "%s You can't use {gold}CallAdmin {orchid}since there is admins online. Type {red}!admins {orchid}to check currently online admins.", CHAT_PREFIX);
			return Plugin_Handled;
		}
	}

	if(args < 1)
	{
		CPrintToChat(client, "%s sm_calladmin <reason>", CHAT_PREFIX);
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

	char sConnect[256], sURL[256], sNetIP[32], sNetPort[32];
	GetConVarString(g_cRedirectURL, sURL, sizeof(sURL));

	if (g_cvPort != null)
		GetConVarString(g_cvPort, sNetPort, sizeof (sNetPort));
	delete g_cvPort;

	if (g_cvNetPublicAddr != null)
		GetConVarString(g_cvNetPublicAddr, sNetIP, sizeof(sNetIP));
	delete g_cvNetPublicAddr;

	Format(sConnect, sizeof(sConnect), "[%s:%s](%s?ip=%s&port=%s)", sNetIP, sNetPort, sURL, sNetIP, sNetPort);

	char sReason[256];
	GetCmdArgString(sReason, sizeof(sReason));
	ReplaceString(sReason, sizeof(sReason), "\\n", "\n");

	char sAuth[32];
	GetClientAuthId(client, AuthId_Steam2, sAuth, sizeof(sAuth));

	
	char sClientID[256], sSteamClientID[64];	
	GetClientAuthId(client, AuthId_SteamID64, sSteamClientID, sizeof(sSteamClientID));
	Format(sClientID, sizeof(sClientID), "[Steam Profile](<https://steamcommunity.com/profiles/%s>)", sSteamClientID);

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

	// Generate discord message
	char sMessageDiscord[4096];

	if (g_Plugin_SourceBans)
	{
		int iClientBans = 0;
		int iClientComms = 0;

	#if defined _sourcebanschecker_included
		iClientBans = SBPP_CheckerGetClientsBans(client);
		iClientComms = SBPP_CheckerGetClientsComms(client);
	#endif

		Format(sMessageDiscord, sizeof(sMessageDiscord), 
			"@here ```%N (%d bans - %d comms) [%s] is calling an Admin. \nCurrent map : %s \n%s \n%s \n%s \nTimeLeft : %s \nReason: %s```**Quick join:** %s \n*%s*", 
			client, iClientBans, iClientComms, sAuth, currentMap, sTime, sAliveCount, sCount, sTimeLeft, sReason, sConnect, sClientID);
	}
	else
	{
		Format(sMessageDiscord, sizeof(sMessageDiscord), 
			"@here ```%N [%s] is calling an Admin. \nCurrent map : %s \n%s \n%s \n%s \nTimeLeft : %s \nReason: %s```**Quick join:** %s \n*%s*", 
			client, sAuth, currentMap, sTime, sAliveCount, sCount, sTimeLeft, sReason, sConnect, sClientID);
	}


	SendWebHook(GetClientUserId(client), sMessageDiscord, sWebhookURL);
	LogAction(client, -1, "%L has called an Admin. (Reason: %s)", client, sReason);

	return Plugin_Handled;
}

stock void SendWebHook(int userid, char sMessage[4096], char sWebhookURL[WEBHOOK_URL_MAX_SIZE])
{
	Webhook webhook = new Webhook(sMessage);

	char sThreadID[32], sThreadName[WEBHOOK_THREAD_NAME_MAX_SIZE];
	g_cvThreadID.GetString(sThreadID, sizeof sThreadID);
	g_cvThreadName.GetString(sThreadName, sizeof sThreadName);

	bool IsThread = g_cvChannelType.BoolValue;

	if (IsThread)
	{
		if (!sThreadName[0] && !sThreadID[0])
		{
			int client = GetClientOfUserId(userid);
			LogError("[CallAdmin] Thread Name or ThreadID not found or specified.");
			CPrintToChat(client, "%s Oops something is wrong on server side, can't send the weebhook.", CHAT_PREFIX);
			delete webhook;
			return;
		}
		else
		{
			if (strlen(sThreadName) > 0)
			{
				webhook.SetThreadName(sThreadName);
				// discord API doc: If thread_name is provided, a thread with that name will be created in the forum channel
				// error: #220002	Webhooks posted to forum channels cannot have both a thread_name and thread_id
				// So no need to continue for thread_id method
				sThreadID[0] = '\0';
			}
		}
	}

	char sName[128];
	g_cvUsername.GetString(sName, sizeof(sName));
	if (strlen(sName) < 1)
		FormatEx(sName, sizeof(sName), "CallAdmin");

	char sAvatar[256];
	g_cvAvatar.GetString(sAvatar, sizeof(sAvatar));

	webhook.SetUsername(sName);
	webhook.SetAvatarURL(sAvatar);

	DataPack pack = new DataPack();

	if (IsThread && strlen(sThreadName) <= 0 && strlen(sThreadID) > 0)
		pack.WriteCell(1);
	else
		pack.WriteCell(0);

	pack.WriteCell(userid);
	pack.WriteString(sMessage);
	pack.WriteString(sWebhookURL);

	webhook.Execute(sWebhookURL, OnWebHookExecuted, pack, sThreadID);
	delete webhook;
}

public void OnWebHookExecuted(HTTPResponse response, DataPack pack)
{
	static int retries = 0;
	pack.Reset();

	bool IsThreadReply = pack.ReadCell();
	int userid = pack.ReadCell();
	int client = GetClientOfUserId(userid);

	char sMessage[4096], sWebhookURL[WEBHOOK_URL_MAX_SIZE];
	pack.ReadString(sMessage, sizeof(sMessage));
	pack.ReadString(sWebhookURL, sizeof(sWebhookURL));

	delete pack;
	
	if (!IsThreadReply && response.Status != HTTPStatus_OK)
	{
		if (retries < g_cvWebhookRetry.IntValue)
		{
			CPrintToChat(client, "%s {red}Failed to send your message. Resending it .. (%d/3)", CHAT_PREFIX, retries + 1);
			PrintToServer("[CallAdmin] Failed to send the webhook. Resending it .. (%d/%d)", retries + 1, g_cvWebhookRetry.IntValue);
			SendWebHook(userid, sMessage, sWebhookURL);
			retries++;
			return;
		}
		else
		{
			CPrintToChat(client, "%s {red}An error has occurred. Your message can't be sent.", CHAT_PREFIX);
			LogError("[CallAdmin] Failed to send the webhook after %d retries, aborting.", retries);
			return;
		}
	}

	if (IsThreadReply && response.Status != HTTPStatus_NoContent)
	{
		if (retries < g_cvWebhookRetry.IntValue)
		{
			CPrintToChat(client, "%s {red}Failed to send your message. Resending it .. (%d/3)", CHAT_PREFIX, retries + 1);
			PrintToServer("[CallAdmin] Failed to send the webhook. Resending it .. (%d/%d)", retries + 1, g_cvWebhookRetry.IntValue);
			SendWebHook(userid, sMessage, sWebhookURL);
			retries++;
			return;
		}
		else
		{
			CPrintToChat(client, "%s {red}An error has occurred. Your message can't be sent.", CHAT_PREFIX);
			LogError("[CallAdmin] Failed to send the webhook after %d retries, aborting.", retries);
			return;
		}
	}

	CPrintToChat(client, "%s Message sent.\nRemember that abuse/spam of {gold}CallAdmin {orchid}will result in a chat block", CHAT_PREFIX);

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