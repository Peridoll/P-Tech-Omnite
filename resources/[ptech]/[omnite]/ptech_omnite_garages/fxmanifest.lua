fx_version 'cerulean'
game 'gta5'
lua54 'yes'
name 'ptech_omnite_garages'
author 'P-Tech'
version '0.1.0-dev'
description 'Omnite garage location authoring for JG v3'
shared_scripts { '@ox_lib/init.lua', 'config.lua' }
client_script 'main/client.lua'
server_script 'main/server.lua'
dependencies { 'ox_lib', 'ox_inventory', 'jg-advancedgarages' }
