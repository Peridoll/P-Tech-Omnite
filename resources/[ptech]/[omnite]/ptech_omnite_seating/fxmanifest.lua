fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ptech_omnite_seating'
author 'P-Tech'
description 'Target-based seating for configured chair props and MLO seats'
version '0.2.0-dev'

shared_scripts { '@ox_lib/init.lua', 'config.lua' }
client_scripts { 'main/client/client.lua', 'main/client/placement.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', 'main/server/server.lua', 'main/server/placement.lua' }

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
