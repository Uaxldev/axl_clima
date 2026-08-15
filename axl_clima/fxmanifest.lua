fx_version 'cerulean'
game 'gta5'

name        'axl_clima'
author      'UnityDev - Axldev'
description 'Horario, clima e apagao da cidade — painel de admin com padrao gravavel'
version     '1.0.0'

-- vrp DEVE subir antes: sem ele o Proxy.getInterface falha em silencio e
-- nenhuma permissao resolve — o painel abriria pra qualquer um.
dependency 'vrp'

ui_page 'nui/index.html'

shared_scripts {
    'config.lua',
}

client_scripts {
    '@vrp/lib/utils.lua',
    'client.lua',
}

server_scripts {
    '@vrp/lib/utils.lua',
    'server.lua',
}

files {
    'nui/index.html',
    'nui/style.css',
    'nui/script.js',
    -- Sem esta linha as imagens dao 404 na NUI: arquivo que nao esta em
    -- `files{}` simplesmente nao existe pro CEF. `Images` com I MAIUSCULO —
    -- servidor Linux diferencia, e ali o caminho errado some calado.
    'nui/Images/*.png',
}

lua54 'yes'
