# CallAdmin

Player can send a message from the game server to call admins on discord.

![Preview](https://i.imgur.com/ax4FG2i.png)

## Requirement

For **1.3 and above** you need: https://github.com/sbpp/sourcebans-pp/pull/763/files

## Usage
```
sm_calladmin <client text>
```

## Config
```
sm_calladmin_servername <name> (ServerName)
sm_calladmin_cooldown <value> (Cooldown in seconds before a player can use sm_calladmin again)
sm_calladmin_count_bots <value> [1 = Yes | 0 = No ]
sm_calladmin_server_steam_ip <ip> (Set your server IP here when auto detection is not working for you.
(Use 0.0.0.0 to disable manually override) - The port is automaticly detected.
```
