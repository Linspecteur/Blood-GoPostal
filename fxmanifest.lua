fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'BloodLeak'
description 'BloodLeak - Livreur GoPostal (pôle intérimaire : tournées en équipe, colis, progression, succès, classement, événements) - ESX / QBCore / Qbox / ox_core'
version '1.2.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/admin.css',
    'html/admin.js'
}

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/bridge.lua',
    'client/main.lua'
}

server_scripts {
    'server/bridge.lua',
    'server/storage.lua',
    'server/main.lua',
    'server/progress.lua',
    'server/admin.lua'
}
