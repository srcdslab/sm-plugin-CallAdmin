# SourcePawn Plugin Development Guidelines for CallAdmin

## Repository Overview
This repository contains a SourcePawn plugin for SourceMod called "CallAdmin" that allows game server players to send Discord webhook messages to notify administrators. The plugin integrates with multiple other SourceMod plugins and provides comprehensive server information in Discord embeds.

## Technical Environment
- **Language**: SourcePawn (version 1.11+, minimum 1.12+ for new development)
- **Platform**: SourceMod 1.12+ (latest stable release)
- **Compiler**: SourcePawn compiler (spcomp) via SourceKnight build system
- **Build Tool**: SourceKnight v0.2 (dependency management and compilation)
- **CI/CD**: GitHub Actions with automated building and releases

## Project Structure
```
/
├── addons/sourcemod/scripting/
│   └── CallAdmin.sp                 # Main plugin source code
├── .github/
│   └── workflows/ci.yml            # CI/CD pipeline
├── sourceknight.yaml              # Build configuration and dependencies
├── README.md                       # Project documentation
└── .gitignore                      # Git ignore rules
```

## Code Style & Standards (Current Implementation)
- **Indentation**: Tabs (4 spaces equivalent)
- **Variables**: camelCase for local variables and parameters (e.g., `sWebhookURL`, `iClientBans`)
- **Functions**: PascalCase for function names (e.g., `SendWebHook`, `ReadClientCookies`)
- **Global Variables**: Prefix with "g_" and use PascalCase (e.g., `g_cvWebhook`, `g_bLate`)
- **Constants**: ALL_CAPS with underscores (e.g., `PLUGIN_NAME`, `CHAT_PREFIX`)
- **Required Pragmas**: `#pragma newdecls required` and `#pragma semicolon 1` (modern SourcePawn)
- **Whitespace**: Delete trailing spaces from all lines
- **Translations**: Use translation files for all user-facing messages (not currently implemented but recommended)

## Dependencies & Integration Points
The plugin integrates with multiple SourceMod plugins through conditional compilation and native function checking:

### Core Dependencies (Required)
- **discordWebhookAPI**: Discord webhook functionality
- **multicolors**: Chat color formatting
- **utilshelper**: Utility functions
- **clientprefs**: Player preference storage (cooldowns)
- **cstrike**: Counter-Strike game integration
- **sdktools**: SourceMod SDK tools
- **basecomm**: Basic communication (gag checking)

### Optional Dependencies (Conditional Features)
- **AFKManager**: AFK time detection for admins
- **AutoRecorder**: Demo recording information
- **sourcecomms**: Advanced communication management
- **sourcebanschecker**: Ban/mute/gag history
- **ExtendedDiscord**: Enhanced error logging
- **zombiereloaded**: Zombie mod team name adaptation

### Dependency Management Pattern
```sourcepawn
// Use #undef/#tryinclude/#define pattern for optional dependencies
#undef REQUIRE_PLUGIN
#tryinclude <AFKManager>
#tryinclude <AutoRecorder>
#define REQUIRE_PLUGIN

// Check plugin availability at runtime
bool g_Plugin_AFKManager = false;
bool g_bNative_AFKManager = false;

public void OnAllPluginsLoaded() {
    g_Plugin_AFKManager = LibraryExists("AFKManager");
    VerifyNatives();
}

// Verify native function availability
stock void VerifyNative_AFKManager() {
    g_bNative_AFKManager = g_Plugin_AFKManager && CanTestFeatures() && 
        GetFeatureStatus(FeatureType_Native, "GetClientIdleTime") == FeatureStatus_Available;
}
```

## Build Process
### Using SourceKnight
```bash
# Install SourceKnight (Python package)
pip install sourceknight

# Build the plugin
sourceknight build

# Output location: /addons/sourcemod/plugins/CallAdmin.smx
```

### Build Configuration (sourceknight.yaml)
- Automatically downloads SourceMod 1.11.0-git6934
- Fetches all dependencies from GitHub repositories
- Compiles to `.smx` files in the plugins directory
- **Note**: There's a typo in line 67 (`includea` should be `include`) that should be fixed

### CI/CD Pipeline
- Builds on Ubuntu 24.04
- Creates release packages automatically
- Tags latest builds from main/master branch
- Uploads artifacts and creates GitHub releases

## Memory Management Patterns
```sourcepawn
// Proper handle cleanup - no null checking needed
delete webhook;
delete hConfig;
delete g_cvPort;

// Use StringMap/ArrayList instead of arrays where appropriate
// Always delete and recreate instead of using .Clear()
delete someStringMap;
someStringMap = new StringMap();
```

## Common Patterns in This Codebase

### ConVar Management
```sourcepawn
ConVar g_cvWebhook, g_cvCooldown, g_cvAdmins;

public void OnPluginStart() {
    g_cvWebhook = CreateConVar("sm_calladmin_webhook", "", "Description", FCVAR_PROTECTED);
    AutoExecConfig(true);
}
```

### Client Cookie Handling
```sourcepawn
Handle g_hLastUse = INVALID_HANDLE;
int g_iLastUse[MAXPLAYERS+1] = { -1, ... };

public void OnPluginStart() {
    g_hLastUse = RegClientCookie("calladmin_last_use", "Description", CookieAccess_Protected);
}

public void OnClientCookiesCached(int client) {
    ReadClientCookies(client);
}
```

### Discord Webhook Integration
```sourcepawn
// Create webhook with proper embed structure
Webhook webhook = new Webhook("||@here||");
Embed embed = new Embed(title);
embed.SetTimeStampNow();
embed.SetColor(colorValue);

// Add fields and execute
EmbedField field = new EmbedField();
field.SetName("Field Name");
field.SetValue("Field Value");
embed.AddField(field);
webhook.AddEmbed(embed);
webhook.Execute(url, OnWebHookExecuted, datapack);
```

### Error Handling & Retries
```sourcepawn
// Implement retry logic with proper error handling
public void OnWebHookExecuted(HTTPResponse response, DataPack pack) {
    static int retries = 0;
    
    if (response.Status != HTTPStatus_OK) {
        if (retries < g_cvWebhookRetry.IntValue) {
            retries++;
            // Retry logic
        } else {
            // Error logging with optional ExtendedDiscord integration
            if (g_bNative_ExtDiscord) {
                ExtendedDiscord_LogError("Error message");
            } else {
                LogError("Error message");
            }
        }
    }
}
```

## Performance Considerations
- **Cooldown System**: Uses client preferences to persist across map changes
- **Admin Detection**: Efficient loop through connected clients with early termination
- **Native Checking**: Runtime verification prevents crashes from missing plugins
- **Memory Efficiency**: Proper cleanup of handles and objects, no memory leaks
- **Async Operations**: All webhook calls are asynchronous to prevent server blocking
- **O(1) Optimizations**: Cache frequently accessed values, avoid O(n) operations in timers
- **String Operations**: Minimize string manipulations in frequently called functions
- **Timer Usage**: Avoided where possible, prefer event-driven programming

## Testing & Validation
- Plugin compiles without warnings using SourceMod 1.12+
- Test with various plugin combinations (with/without optional dependencies)
- Verify Discord webhook functionality with actual Discord server
- Test cooldown persistence across map changes and server restarts
- Validate admin detection and permission checking
- Check for memory leaks using SourceMod's built-in profiler
- Ensure compatibility across different Source engine games
- Test performance impact on server tick rate under load

## Configuration Files
The plugin auto-generates configuration file with these key ConVars:
- `sm_calladmin_webhook`: Discord webhook URL
- `sm_calladmin_cooldown`: Cooldown between uses (default: 600 seconds)
- `sm_calladmin_block`: Block usage when admins online (0/1)
- `sm_calladmin_channel_type`: Regular channel (0) or thread (1)

## Common Modification Patterns
1. **Adding New Discord Fields**: Create EmbedField, set properties, add to embed
2. **New Plugin Integration**: Add to sourceknight.yaml dependencies, add conditional includes, implement native checking
3. **ConVar Addition**: Add to OnPluginStart(), document in configuration section
4. **Command Extensions**: Use RegConsoleCmd() with proper permission checking

## Security Considerations
- Webhook URLs marked as FCVAR_PROTECTED
- Input validation for all user-provided strings
- Admin permission checking before allowing usage
- Rate limiting through cooldown system
- Gag status checking to prevent spam

## Debugging Tips
- Use LogAction() for user actions
- Implement ExtendedDiscord logging when available
- Check GetFeatureStatus() before calling optional natives
- Validate ConVar values before usage
- Test with various client states (connected, in-game, different teams)