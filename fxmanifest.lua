fx_version 'cerulean'
game 'gta5'
author 'MRI'
description 'Sistema de Logs de Ponto com UI Moderna'
version '2.0.0'

shared_scripts {
    'shared/config.lua',
    '@ox_lib/init.lua',
}

client_scripts {
    'client/main.lua',
    'client/config_ui.lua',
}

server_scripts {
    'server/main.lua',
    'server/config_store.lua',
    'server/backup_logs.lua',
}

ui_page 'web/dist/index.html'

files {
    'web/dist/index.html',
    'web/dist/assets/*.js', 
    'web/dist/assets/*.css',
    'web/src/**/*', -- Just in case dev mode
    'web/*.tsx',
    'web/*.tsx',
    'web/*.ts',
    'locales/*.json',
}
