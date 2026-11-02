fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ptech_omnite_requests'
author 'P-Tech'
description 'Omnite configurable request and delivery boards'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'main/shared/shared.lua',
}

client_scripts {
    'main/client/client.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'main/server/server.lua',
}

dependencies {
    'ox_lib',
    'ox_target',
    'qbx_core',
    'oxmysql',
    'ox_inventory',
    '/onesync',
}
