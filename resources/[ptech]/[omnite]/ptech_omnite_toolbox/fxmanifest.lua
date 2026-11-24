fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ptech_omnite_toolbox'
author 'P-Tech'
description 'Omnite toolbox: seating, beds, garages and two-point teleporters'
version '0.6.0-dev'

shared_scripts { '@ox_lib/init.lua', 'config.lua' }
client_scripts { 'main/client/client.lua', 'main/client/placement.lua', 'main/client/teleporters.lua', 'main/client/circles.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', 'main/server/server.lua', 'main/server/placement.lua', 'main/server/teleporters.lua', 'main/server/circles.lua' }

ui_page 'main/nui/index.html'

files {
    'main/nui/index.html',
    'main/nui/style.css',
    'main/nui/app.js',
}

dependencies {
    'ox_target',
    'ox_lib',
    'ox_inventory',
    'oxmysql',
    'qbx_core',
    '/onesync',
}
