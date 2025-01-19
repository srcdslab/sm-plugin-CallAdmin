#include <sourcemod>
#include <clientprefs>
#include <cstrike>
#include <sdktools>
#include <basecomm>

#include <discordWebhookAPI>
#include <multicolors>

#undef REQUIRE_PLUGIN
#tryinclude <AFKManager>
#tryinclude <AutoRecorder>
#tryinclude <sourcecomms>
#tryinclude <sourcebanschecker>
#tryinclude <ExtendedDiscord>
#tryinclude <zombiereloaded>
#define REQUIRE_PLUGIN

#pragma newdecls required

#define PLUGIN_NAME "CallAdmin"
#define CHAT_PREFIX "{gold}[Call Admin]{orchid}"

ConVar g_cvWebhook, g_cvWebhookRetry, g_cvAvatar, g_cvUsername, g_cvMapThumbnailURL, g_cvColor;
ConVar g_cvChannelType, g_cvThreadName, g_cvThreadID;

ConVar g_cvCooldown, g_cvAdmins, g_cvDetectionSound, g_cvNetPublicAddr, g_cvPort;
ConVar g_cCountBots = null;
ConVar g_cvRedirectURL = null;
ConVar g_cvFooterIcon = null;

Handle g_hLastUse = INVALID_HANDLE;

EngineVersion gEV_Type = Engine_Unknown;

int g_iLastUse[MAXPLAYERS+1] = { -1, ... }

bool g_bLate = false;

bool g_Plugin_AFKManager = false;
bool g_Plugin_ZR = false;
bool g_Plugin_SourceBans = false;
bool g_Plugin_SourceComms = false;
bool g_Plugin_ExtDiscord = false;
bool g_Plugin_AutoRecorder = false;

bool g_bNative_AFKManager = false;
bool g_bNative_SbComms_GagType = false;
bool g_bNative_SbChecker_Bans = false;
bool g_bNative_SbChecker_Mutes = false;
bool g_bNative_SbChecker_Gags = false;
bool g_bNative_ExtDiscord = false;
bool g_bNative_AutoRecorder_DemoRecording = false;
bool g_bNative_AutoRecorder_DemoRecordCount = false;
bool g_bNative_AutoRecorder_DemoRecordingTick = false;
bool g_bNative_AutoRecorder_DemoRecordingTime = false;

char g_sBeepSound[PLATFORM_MAX_PATH];

public Plugin myinfo = 
{
	name = PLUGIN_NAME,
	author = "inGame, maxime1907, .Rushaway",
	description = "Send a calladmin message to discord",
	version = "2.1.0",
	url = "https://github.com/srcdslab/sm-plugin-CallAdmin"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("CallAdmin");
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
	g_cvRedirectURL = CreateConVar("sm_calladmin_redirect", "https://nide.gg/connect/", "URL to your redirect.php file.");
	g_cvChannelType = CreateConVar("sm_calladmin_channel_type", "0", "Type of your channel: (1 = Thread, 0 = Classic Text channel");
	g_cvMapThumbnailURL = CreateConVar("sm_calladmin_mapthumbnailurl", "https://bans.nide.gg/images/maps/", "URL where you store map thumbail files. (.JPG ONLY)");
	g_cvColor = CreateConVar("sm_calladmin_color", "4244579", "Decimal color code for the embed. \nHex to Decimal - https://www.binaryhexconverter.com/hex-to-decimal-converter");
	g_cvFooterIcon = CreateConVar("sm_calladmin_footer_icon", "https://github.githubassets.com/images/icons/emoji/unicode/1f55c.png?v8", "Url to the footer icon.");

	/* Thread config */
	g_cvThreadName = CreateConVar("sm_calladmin_threadname", "CallAdmin", "The Thread Name of your Discord forums. (If not empty, will create a new thread)", FCVAR_PROTECTED);
	g_cvThreadID = CreateConVar("sm_calladmin_threadid", "0", "If thread_id is provided, the message will send in that thread.", FCVAR_PROTECTED);

	g_cvCooldown = CreateConVar("sm_calladmin_cooldown", "600", "Cooldown in seconds before a player can use sm_calladmin again", FCVAR_NONE);
	g_cCountBots = CreateConVar("sm_calladmin_count_bots", "0", "Should we count bots as players ?(1 = Yes, 0 = No)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvAdmins = CreateConVar("sm_calladmin_block", "0", "Block calladmin usage if an admin is online?(1 = Yes, 0 = No)", FCVAR_PROTECTED, true, 0.0, true, 1.0);
	g_cvDetectionSound = CreateConVar("sm_calladmin_detection_sound", "1", "Emit a beep sound when someone gets flagged [0 = disabled, 1 = enabled]", 0, true, 0.0, true, 1.0);

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
	g_Plugin_ExtDiscord = LibraryExists("ExtendedDiscord");
	g_Plugin_AutoRecorder = LibraryExists("AutoRecorder");
	g_Plugin_ZR = LibraryExists("zombiereloaded");

	VerifyNatives();
}

public void OnLibraryAdded(const char[] sName)
{
	if (strcmp(sName, "zombiereloaded", false) == 0)
		g_Plugin_ZR = true;
	if (strcmp(sName, "AFKManager", false) == 0)
	{
		g_Plugin_AFKManager = true;
		VerifyNative_AFKManager();
	}
	if (strcmp(sName, "sourcebans++", false) == 0)
	{
		g_Plugin_SourceBans = true;
		VerifyNative_SbChecker();
	}
	if (strcmp(sName, "sourcecomms++", false) == 0)
	{
		g_Plugin_SourceComms = true;
		VerifyNative_SbComms();
	}
	if (strcmp(sName, "ExtendedDiscord", false) == 0)
	{
		g_Plugin_ExtDiscord = true;
		VerifyNative_ExtDiscord();
	}
	if (strcmp(sName, "AutoRecorder", false) == 0)
	{
		g_Plugin_AutoRecorder = true;
		VerifyNative_AutoRecorder();
	}
}

public void OnLibraryRemoved(const char[] sName)
{
	if (strcmp(sName, "zombiereloaded", false) == 0)
		g_Plugin_ZR = false;
	if (strcmp(sName, "AFKManager", false) == 0)
	{
		g_Plugin_AFKManager = false;
		VerifyNative_AFKManager();
	}
	if (strcmp(sName, "sourcebans++", false) == 0)
	{
		g_Plugin_SourceBans = false;
		VerifyNative_SbChecker();
	}
	if (strcmp(sName, "sourcecomms++", false) == 0)
	{
		g_Plugin_SourceComms = false;
		VerifyNative_SbComms();
	}
	if (strcmp(sName, "ExtendedDiscord", false) == 0)
	{
		g_Plugin_ExtDiscord = false;
		VerifyNative_ExtDiscord();
	}
	if (strcmp(sName, "AutoRecorder", false) == 0)
	{
		g_Plugin_AutoRecorder = false;
		VerifyNative_AutoRecorder();
	}
}

stock void VerifyNatives()
{
	VerifyNative_AFKManager();
	VerifyNative_SbComms();
	VerifyNative_SbChecker();
	VerifyNative_ExtDiscord();
	VerifyNative_AutoRecorder();
}

stock void VerifyNative_AFKManager()
{
	g_bNative_AFKManager = g_Plugin_AFKManager && CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "GetClientIdleTime") == FeatureStatus_Available;
}

stock void VerifyNative_SbComms()
{
	g_bNative_SbComms_GagType = g_Plugin_SourceComms && CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "SourceComms_GetClientGagType") == FeatureStatus_Available;
}

stock void VerifyNative_SbChecker()
{
	g_bNative_SbChecker_Bans = g_Plugin_SourceBans && CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "SBPP_CheckerGetClientsBans") == FeatureStatus_Available;
	g_bNative_SbChecker_Mutes = g_Plugin_SourceBans && CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "SBPP_CheckerGetClientsMutes") == FeatureStatus_Available;
	g_bNative_SbChecker_Gags = g_Plugin_SourceBans && CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "SBPP_CheckerGetClientsGags") == FeatureStatus_Available;
}

stock void VerifyNative_ExtDiscord()
{
	g_bNative_ExtDiscord = g_Plugin_ExtDiscord && CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "ExtendedDiscord_LogError") == FeatureStatus_Available;
}

stock void VerifyNative_AutoRecorder()
{
	g_bNative_AutoRecorder_DemoRecording = g_Plugin_AutoRecorder && CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "AutoRecorder_IsDemoRecording") == FeatureStatus_Available;
	g_bNative_AutoRecorder_DemoRecordCount = g_Plugin_AutoRecorder && CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "AutoRecorder_GetDemoRecordCount") == FeatureStatus_Available;
	g_bNative_AutoRecorder_DemoRecordingTick = g_Plugin_AutoRecorder && CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "AutoRecorder_GetDemoRecordingTick") == FeatureStatus_Available;
	g_bNative_AutoRecorder_DemoRecordingTime = g_Plugin_AutoRecorder && CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "AutoRecorder_GetDemoRecordingTime") == FeatureStatus_Available;
}

public void OnMapStart()
{
	Handle hConfig = LoadGameConfigFile("funcommands.games");

	if (hConfig == null)
	{
		SetFailState("Unable to load game config funcommands.games");
		return;
	}

	if (GameConfGetKeyValue(hConfig, "SoundBeep", g_sBeepSound, PLATFORM_MAX_PATH))
		PrecacheSound(g_sBeepSound, true);

	delete hConfig;
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

	FormatEx(sValue, sizeof(sValue), "%i", g_iLastUse[client]);
	SetClientCookie(client, g_hLastUse, sValue);
}

public Action Command_CallAdmin(int client, int args)
{
	if (!client)
	{
		ReplyToCommand(client, "[SM] Cannot use this command from server console.");
		return Plugin_Handled;
	}

	if (args < 1)
	{
		CPrintToChat(client, "%s sm_calladmin <reason>", CHAT_PREFIX);
		return Plugin_Handled;
	}

	char sWebhookURL[WEBHOOK_URL_MAX_SIZE];
	g_cvWebhook.GetString(sWebhookURL, sizeof sWebhookURL);
	if (!sWebhookURL[0])
	{
		LogError("[CallAdmin] No webhook found or specified.");
		CPrintToChat(client, "%s A configuration issue has been detected, can't send the webhook.", CHAT_PREFIX);
		return Plugin_Handled;
	}
	
	int iGagType = 0;
	bool bIsGagged = false;

	if (g_bNative_SbComms_GagType)
	{
	#if defined _sourcecomms_included
		iGagType = SourceComms_GetClientGagType(client);
	#endif
		bIsGagged = iGagType > 0;
	}
	else
	{
		bIsGagged = BaseComm_IsClientGagged(client);
	}

	if (bIsGagged)
	{
		CPrintToChat(client, "%s You are not allowed to use {gold}Call Admin {orchid}since you are gagged.", CHAT_PREFIX);
		return Plugin_Handled;
	}

	if (GetAdminFlag(GetUserAdmin(client), Admin_Ban) && !GetAdminFlag(GetUserAdmin(client), Admin_Root))
	{
		CPrintToChat(client, "%s You are an admin with the ban flag, why the f*ck do you use that command?", CHAT_PREFIX);
		return Plugin_Handled;
	}

	int cooldownDiff = GetTime() - g_iLastUse[client];
	if (cooldownDiff < g_cvCooldown.IntValue)
	{
		CPrintToChat(client, "%s You are on cooldown, wait {default}%d {orchid}seconds.", CHAT_PREFIX, g_cvCooldown.IntValue - cooldownDiff);
		return Plugin_Handled;
	}

	if (g_cvAdmins.IntValue >= 1)
	{
		int Admins = 0;
		int AfkAdmins = 0;

		for(int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || IsFakeClient(i))
				continue;

			if (GetAdminFlag(GetUserAdmin(i), Admin_Ban))
			{
			#if defined _AFKManager_Included
				if (g_bNative_AFKManager)
				{
					int IdleTime = GetClientIdleTime(i);
					if (IdleTime > 30)
						AfkAdmins++;
				}
			#endif
				Admins++;
			}
		}

		if (Admins > AfkAdmins)
		{
			CPrintToChat(client, "%s You can't use {gold}CallAdmin {orchid}since there is admins online. Type {red}!admins {orchid}to check currently online admins.", CHAT_PREFIX);
			return Plugin_Handled;
		}
	}

	char sReason[256];
	GetCmdArgString(sReason, sizeof(sReason));
	ReplaceString(sReason, sizeof(sReason), "\\n", "\n");
	SendWebHook(GetClientUserId(client), sReason, sWebhookURL);

	if (g_cvAdmins.IntValue < 1)
	{
		// Print a messages to online admins
		for(int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || IsFakeClient(i))
				continue;

			if (GetAdminFlag(GetUserAdmin(i), Admin_Ban))
			{
				CPrintToChat(i, "%s {olive}%N {orchid}has called an admin ({default}Reason: %s{orchid})", CHAT_PREFIX, client, sReason);
				if (g_cvDetectionSound.BoolValue)
				{
					if (gEV_Type == Engine_CSS || gEV_Type == Engine_TF2)
						EmitSoundToClient(i, g_sBeepSound);
					else
						ClientCommand(i, "play */%s", g_sBeepSound);
				}
				continue;
			}
		}
	}

	return Plugin_Handled;
}

stock void SendWebHook(int userid, char sReason[256], char sWebhookURL[WEBHOOK_URL_MAX_SIZE])
{
	Webhook webhook = new Webhook("||@here||");

	int client = GetClientOfUserId(userid);
	bool IsThread = g_cvChannelType.BoolValue;
	char sThreadID[32], sThreadName[WEBHOOK_THREAD_NAME_MAX_SIZE];

	g_cvThreadID.GetString(sThreadID, sizeof sThreadID);
	g_cvThreadName.GetString(sThreadName, sizeof sThreadName);

	if (IsThread) {
		if (!sThreadName[0] && !sThreadID[0]) {
			LogError("Thread Name or ThreadID not found or specified.");
			CPrintToChat(client, "%s Oops something is wrong on server side, can't send the weebhook.", CHAT_PREFIX);
			delete webhook;
			return;
		} else {
			if (strlen(sThreadName) > 0) {
				webhook.SetThreadName(sThreadName);
				sThreadID[0] = '\0';
			}
		}
	}

	/* Webhook UserName */
	char sName[128];
	g_cvUsername.GetString(sName, sizeof(sName));

	/* Webhook Avatar */
	char sAvatar[256];
	g_cvAvatar.GetString(sAvatar, sizeof(sAvatar));

	/* Map Name */
	char sMapName[PLATFORM_MAX_PATH], sMapNameLower[PLATFORM_MAX_PATH];
	GetCurrentMap(sMapName, sizeof(sMapName));
	GetCurrentMap(sMapNameLower, sizeof(sMapNameLower));

	/* Map Time Left */
	int timeleft;
	char sTimeLeft[32];
	if (GetMapTimeLeft(timeleft))
	{
		if (timeleft > 0)
			FormatEx(sTimeLeft, sizeof(sTimeLeft), "%i:%02i", timeleft / 60, timeleft % 60);
		else if (timeleft <= 0)
			FormatEx(sTimeLeft, sizeof(sTimeLeft), "Last Round");
	}
	else
		FormatEx(sTimeLeft, sizeof(sTimeLeft), "N/A");

	/* Team names */
	char sTeamCTName[32], sTeamTName[32];
	sTeamCTName = g_Plugin_ZR ? "Humans" : "CTs"
	sTeamTName = g_Plugin_ZR ? "Zombies" : "Ts"

	/* Team score */
	char sTeamScore[64];
	FormatEx(sTeamScore, sizeof(sTeamScore), "%s %d - %d %s", sTeamCTName, GetTeamScore(CS_TEAM_CT), GetTeamScore(CS_TEAM_T), sTeamTName);

	/* Team details */
	char sTeamDetails[128];
	FormatEx(sTeamDetails, sizeof(sTeamDetails), "%d/%d \n%d %s | %d %s | %d Spectators \n%d %s alive | %d %s alive", 
		GetClientCountEx(g_cCountBots.BoolValue), MaxClients,
		GetPlayerCountByTeam(CS_TEAM_CT), sTeamCTName,
		GetPlayerCountByTeam(CS_TEAM_T), sTeamTName,
		GetPlayerCountByTeam(CS_TEAM_NONE) + GetPlayerCountByTeam(CS_TEAM_SPECTATOR), 
		GetPlayerCountByTeam(CS_TEAM_CT, true), sTeamCTName,
		GetPlayerCountByTeam(CS_TEAM_T, true), sTeamTName);

	/* Profile link */
	char sCallerInfos[512], sProfile[256], sSteamID64[64];
	GetClientAuthId(client, AuthId_SteamID64, sSteamID64, sizeof(sSteamID64));
	FormatEx(sProfile, sizeof(sProfile), "[`%N`](<https://steamcommunity.com/profiles/%s>)", client, sSteamID64);

	int iClientBans = 0;
	int iClientGags = 0;
	int iClientMutes = 0;

#if defined _sourcebanschecker_included
	/* Caller bans informations added to caller informations */
	if (g_bNative_SbChecker_Bans)
		iClientBans = SBPP_CheckerGetClientsBans(client);

	if (g_bNative_SbChecker_Mutes)
		iClientMutes = SBPP_CheckerGetClientsMutes(client);

	if (g_bNative_SbChecker_Gags)
		iClientGags = SBPP_CheckerGetClientsGags(client);
#endif

	FormatEx(sCallerInfos, sizeof(sCallerInfos), "%s (%d bans - %d mutes - %d gags)", sProfile, iClientBans, iClientMutes, iClientGags);

	/* Caller authid informations */
	char sAuth[32];
	GetClientAuthId(client, AuthId_Steam3, sAuth, sizeof(sAuth), false);
	FormatEx(sCallerInfos, sizeof(sCallerInfos), "%s %s", sCallerInfos, sAuth);

	/* Quick Connect */
	char sConnect[256], sURL[256], sNetIP[32], sNetPort[32];

	g_cvPort = FindConVar("hostport");
	if (g_cvPort != null)
	{
		GetConVarString(g_cvPort, sNetPort, sizeof (sNetPort));
		delete g_cvPort;
	}

	g_cvNetPublicAddr = FindConVar("net_public_adr");
	if (g_cvNetPublicAddr == null)
		g_cvNetPublicAddr = FindConVar("hostip");

	GetConVarString(g_cvNetPublicAddr, sNetIP, sizeof(sNetIP));
	delete g_cvNetPublicAddr;

	GetConVarString(g_cvRedirectURL, sURL, sizeof(sURL));
	FormatEx(sConnect, sizeof(sConnect), "[%s:%s](%s?ip=%s&port=%s)", sNetIP, sNetPort, sURL, sNetIP, sNetPort);

	/* Footer Icon */
	char sFooterIcon[256];
	GetConVarString(g_cvFooterIcon, sFooterIcon, sizeof(sFooterIcon));

	/* Generate map image */
	char sThumb[256], sThumbailURL[256];
	StringToLowerCase(sMapNameLower);
	GetConVarString(g_cvMapThumbnailURL, sThumbailURL, sizeof(sThumbailURL));
	Format(sThumb, sizeof(sThumb), "%s/%s.jpg", sThumbailURL, sMapNameLower);

	/* Clean reason */
	char sFormatedReason[256];
	FormatEx(sFormatedReason, sizeof(sFormatedReason), "`%s`", sReason);

	char sHeader[126];
	FormatEx(sHeader, sizeof(sHeader), "`%N` has called an Admin.", client);

	/* Let's build the Embed */
	if (strlen(sName) > 0)
		webhook.SetUsername(sName);
	if (strlen(sAvatar) > 0)
		webhook.SetAvatarURL(sAvatar);

	/* Header */
	Embed Embed_1 = new Embed(sHeader);
	Embed_1.SetTimeStampNow();
	Embed_1.SetColor(g_cvColor.IntValue);

	/* Map Image */
	EmbedThumbnail thumbnail1 = new EmbedThumbnail();
	thumbnail1.SetURL(sThumb);
	Embed_1.SetThumbnail(thumbnail1);
	delete thumbnail1;
	
	/* Fields */
	EmbedField Field_Map = new EmbedField();
	Field_Map.SetName("Current Map:");
	Field_Map.SetValue(sMapName);
	Field_Map.SetInline(true);
	Embed_1.AddField(Field_Map);

	EmbedField Field_Timeleft = new EmbedField();
	Field_Timeleft.SetName("Timeleft:");
	Field_Timeleft.SetValue(sTimeLeft);
	Field_Timeleft.SetInline(true);
	Embed_1.AddField(Field_Timeleft);

	EmbedField Field_TeamScore = new EmbedField();
	Field_TeamScore.SetName("Current Score:");
	Field_TeamScore.SetValue(sTeamScore);
	Field_TeamScore.SetInline(false);
	Embed_1.AddField(Field_TeamScore);

	EmbedField Field_Players = new EmbedField();
	Field_Players.SetName("Players Details:");
	Field_Players.SetValue(sTeamDetails);
	Field_Players.SetInline(false);
	Embed_1.AddField(Field_Players);

	EmbedField Field_Caller = new EmbedField();
	Field_Caller.SetName("Caller:");
	Field_Caller.SetValue(sCallerInfos);
	Field_Caller.SetInline(false);
	Embed_1.AddField(Field_Caller);

	EmbedField Field_Reason = new EmbedField();
	Field_Reason.SetName("Call Reason:");
	Field_Reason.SetValue(sFormatedReason);
	Field_Reason.SetInline(false);
	Embed_1.AddField(Field_Reason);

	EmbedField Field_Connect = new EmbedField();
	Field_Connect.SetName("Quick Connect:");
	Field_Connect.SetValue(sConnect);
	Field_Connect.SetInline(false);
	Embed_1.AddField(Field_Connect);

	#if defined _autorecorder_included
	/* Get all demos informations */
	if (g_bNative_AutoRecorder_DemoRecording && AutoRecorder_IsDemoRecording())
	{
		char sDate[32], sRecord[256];

		int iCount = -1;
		if (g_bNative_AutoRecorder_DemoRecordCount)
			iCount = AutoRecorder_GetDemoRecordCount();

		int iTick = -1;
		if (g_bNative_AutoRecorder_DemoRecordingTick)
			iTick = AutoRecorder_GetDemoRecordingTick();
		
		int retValTime = -1;
		if (g_bNative_AutoRecorder_DemoRecordingTime)
			retValTime = AutoRecorder_GetDemoRecordingTime();

		if (retValTime == -1)
			FormatEx(sDate, sizeof(sDate), "N/A");
		else
			FormatTime(sDate, sizeof(sDate), "%d.%m.%Y @ %H:%M", retValTime);

		FormatEx(sRecord, sizeof(sRecord), "#%d @ Tick: ≈ %d (Started %s)", iCount, iTick, sDate);

		EmbedField Field_Record = new EmbedField();
		Field_Record.SetName("Demo:");
		Field_Record.SetValue(sRecord);
		Field_Record.SetInline(true);
		Embed_1.AddField(Field_Record);
	}
#endif
	
	EmbedFooter Footer = new EmbedFooter("");
	Footer.SetIconURL(sFooterIcon);
	Embed_1.SetFooter(Footer);
	delete Footer;

	/* Generate the Embed */
	webhook.AddEmbed(Embed_1);

	DataPack pack = new DataPack();
	if (IsThread && strlen(sThreadName) <= 0 && strlen(sThreadID) > 0)
		pack.WriteCell(1);
	else
		pack.WriteCell(0);
	pack.WriteCell(userid);
	pack.WriteString(sReason);
	pack.WriteString(sWebhookURL);

	/* Push the message */
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

	char sReason[256], sWebhookURL[WEBHOOK_URL_MAX_SIZE];
	pack.ReadString(sReason, sizeof(sReason));
	pack.ReadString(sWebhookURL, sizeof(sWebhookURL));

	delete pack;
	
	if ((!IsThreadReply && response.Status != HTTPStatus_OK) || (IsThreadReply && response.Status != HTTPStatus_NoContent))
	{
		if (retries < g_cvWebhookRetry.IntValue) {
			CPrintToChat(client, "%s {red}Failed to send your message. Resending it .. (%d/3)", CHAT_PREFIX, retries + 1);
			PrintToServer("[CallAdmin] Failed to send the webhook. Resending it .. (%d/%d)", retries + 1, g_cvWebhookRetry.IntValue);
			SendWebHook(userid, sReason, sWebhookURL);
			retries++;
			return;
		} else {
			CPrintToChat(client, "%s {red}An error has occurred. Your message can't be sent.", CHAT_PREFIX);
			if (!g_bNative_ExtDiscord)
			{
				LogError("[%s] Failed to send the webhook after %d retries, aborting.", PLUGIN_NAME, retries);
				LogError("[%s] %L tried to Call an Admin with the following reason: %s", PLUGIN_NAME, client, sReason);
			}
		#if defined _extendeddiscord_included
			else
			{
				ExtendedDiscord_LogError("[%s] Failed to send the webhook after %d retries, aborting.", PLUGIN_NAME, retries);
				ExtendedDiscord_LogError("[%s] %L tried to Call an Admin with the following reason: %s", PLUGIN_NAME, client, sReason);
			}
		#endif
		}
	}
	else
	{
		if (!GetAdminFlag(GetUserAdmin(client), Admin_Root))
			g_iLastUse[client] = GetTime();

		LogAction(client, -1, "%L has called an Admin. (Reason: %s)", client, sReason);
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
		if (IsClientConnected(player))
		{
			if (IsFakeClient(player))
				iFakeClients++;
			else
				iRealClients++;
		}
	}
	return countBots ? iFakeClients + iRealClients : iRealClients;
}

stock int GetPlayerCountByTeam(int team, bool alive = false)
{
	int count = 0;

	for(int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
		if (alive && IsPlayerAlive(i) && GetClientTeam(i) == team)
			count++;
		else if (!alive && GetClientTeam(i) == team)
			count++;
	}
	return count;
}

stock void StringToLowerCase(char[] input)
{
	for (int i = 0; i < strlen(input); i++)
	{
		input[i] = CharToLower(input[i]);
	}
}
