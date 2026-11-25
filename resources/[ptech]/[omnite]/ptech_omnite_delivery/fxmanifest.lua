fx_version 'cerulean'
game 'gta5'
lua54 'yes'
name 'ptech_omnite_delivery'
author 'P-Tech'
description 'Employee delivery jobs and shop ingredient supplies'
version '0.1.0'
shared_scripts { '@ox_lib/init.lua', 'config.lua' }
client_scripts { 'main/gameplay.lua', 'main/client.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', 'main/finance.lua', 'main/server.lua' }
dependencies { 'ox_lib', 'ox_target', 'ox_inventory', 'oxmysql', 'qbx_core', '/onesync' }
