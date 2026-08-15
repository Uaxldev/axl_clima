-- So o Tunnel: quem resolve permissao e user_id e o server.lua.
local Tunnel = module("vrp", "lib/Tunnel")
vSERVER = Tunnel.getInterface("axl_clima")

local function log(...)
    if Config.debug then print("^6[AXL CLIMA]^7", ...) end
end

-- =====================================================================
--  ESTADO LOCAL — copia do que o servidor mandou. O client nunca decide
--  hora nem clima sozinho.
-- =====================================================================

local hora, minuto = Config.padrao.hora, Config.padrao.min
local temEstado    = false          -- ja recebeu o primeiro sync?

local climaAtual   = nil            -- o que esta aplicado no jogo AGORA
local apagao       = false
local apagaoCarros = false

local painelAberto = false
local abrindo      = false          -- trava contra dois /clima seguidos

-- =====================================================================
--  RELOGIO — `NetworkOverrideClockTime` nao gruda: o relogio do jogo segue
--  andando, entao a chamada tem que se repetir. Fica no frame de proposito:
--  espacada, o jogo avanca entre as chamadas e o HUD pisca o minuto
--  seguinte quando esse avanco cruza a virada.
-- =====================================================================

CreateThread(function()
    while true do
        if temEstado then
            NetworkOverrideClockTime(hora, minuto, 0)
            Wait(0)
        else
            Wait(500)   -- antes do primeiro sync nao ha hora pra impor
        end
    end
end)

RegisterNetEvent("axl_clima:tick")
AddEventHandler("axl_clima:tick", function(h, m)
    if type(h) ~= "number" or type(m) ~= "number" then return end

    hora, minuto = h, m
    temEstado = true

    -- So com o painel na tela: fora dele seria uma mensagem pro CEF a cada
    -- minuto de jogo, pra sempre, em todo cliente.
    if painelAberto then
        SendNUIMessage({ acao = "tick", h = h, m = m })
    end
end)

-- =====================================================================
--  CLIMA — aplicado so quando muda. O vrp_timesync reescrevia as cinco
--  natives a cada 5s pra sempre; aqui a troca acontece uma vez.
-- =====================================================================

local function aplicarClima(novo, comTransicao)
    if novo == climaAtual then return end
    climaAtual = novo
    log("clima ->", novo)

    if comTransicao then
        SetWeatherTypeOverTime(novo, Config.transicaoClima + 0.0)
        Wait(math.floor(Config.transicaoClima * 1000) + 200)

        -- Outro clima chegou no meio da transicao: quem manda e ele.
        if climaAtual ~= novo then return end
    end

    ClearOverrideWeather()
    ClearWeatherTypePersist()
    SetWeatherTypePersist(novo)
    SetWeatherTypeNow(novo)
    SetWeatherTypeNowPersist(novo)
end

-- =====================================================================
--  APAGAO — corta poste, semaforo e luz de predio; o ceu nao muda.
-- =====================================================================

local function aplicarApagao(ligado, carros)
    -- So toca nas natives quando muda: o sync chega inteiro a cada sorteio,
    -- e reimpor o mesmo apagao em toda troca de clima seria trabalho a toa.
    if ligado == apagao and carros == apagaoCarros then return end

    apagao, apagaoCarros = ligado, carros
    SetArtificialLightsState(ligado)
    SetArtificialLightsStateAffectsVehicles(carros)
    log("apagao =", ligado, "carros =", carros)
end

-- =====================================================================
--  RAIOS — `CreateLightningThunder` nao tem parametro, e o desenho do raio
--  quem sorteia e o jogo. O que o "estilo" muda e a ASSINATURA do disparo:
--  quantos claroes e com que espaco. A tabela vem do `config.lua`, que e
--  shared_script, entao o servidor so precisa mandar o numero.
-- =====================================================================

local soltando = false

RegisterNetEvent("axl_clima:raio")
AddEventHandler("axl_clima:raio", function(idx)
    local estilo = Config.raioEstilos[math.floor(tonumber(idx) or 0)]
    if not estilo then return end

    -- Pedido em cima de sequencia em curso e ignorado: dois ritmos tocando
    -- juntos embolam o espacamento e viram estroboscopio.
    --
    -- A trava sobe AQUI, e nao dentro da thread: la ela so valeria quando a
    -- thread comecasse a rodar, e dois eventos no mesmo tick passariam os
    -- dois pela guarda antes disso — justo o que ela existe pra impedir.
    if soltando then return end
    soltando = true

    CreateThread(function()
        for i = 1, estilo.claroes do
            CreateLightningThunder()
            if i < estilo.claroes then Wait(math.floor(estilo.espaco * 1000)) end
        end
        soltando = false
    end)
end)

-- =====================================================================
--  SYNC COMPLETO
-- =====================================================================

RegisterNetEvent("axl_clima:sync")
AddEventHandler("axl_clima:sync", function(e)
    if type(e) ~= "table" then return end
    if type(e.hora) ~= "number" or type(e.min) ~= "number" then return end

    hora, minuto = e.hora, e.min
    temEstado = true

    -- Thread so quando muda: `aplicarClima` da Wait na transicao e nao cabe
    -- no handler. Na primeira carga entra seco — 15s de transicao fariam a
    -- cidade abrir com o ceu errado.
    --
    -- Quem responde "e a primeira?" e o `climaAtual`, nao o `temEstado`:
    -- este ultimo tambem e ligado pelo tick, que vai pra -1 e costuma
    -- chegar antes do sync de quem acabou de entrar. Com ele aqui, o
    -- jogador nascia vendo a transicao de 15s.
    if e.clima ~= climaAtual then
        local primeira = (climaAtual == nil)
        CreateThread(function() aplicarClima(e.clima, not primeira) end)
    end

    aplicarApagao(e.apagao and true or false, e.apagaoCarros and true or false)

    -- Dois admins mexendo ao mesmo tempo tem que ver a mesma coisa.
    if painelAberto then
        SendNUIMessage({ acao = "estado", estado = e })
    end
end)

AddEventHandler("playerSpawned", function()
    TriggerServerEvent("axl_clima:pedirSync")
end)

-- =====================================================================
--  PAINEL — hoverfy anda SEMPRE em par, e o `false` precisa sair em todo
--  caminho de fechamento: botao/ESC, morte e `onResourceStop`. Esquecer num
--  deles derruba os pontos de todos os outros resources.
-- =====================================================================

local function abrirPainel(dados)
    if painelAberto then return end
    painelAberto = true

    SetNuiFocus(true, true)
    TriggerEvent("hoverfy:hidden", true)
    SendNUIMessage({
        acao        = "abrir",
        estado      = dados.estado,
        padrao      = dados.padrao,
        aoReiniciar = dados.aoReiniciar,
        climas      = dados.climas,
    })
end

local function fecharPainel()
    if not painelAberto then return end
    painelAberto = false

    SetNuiFocus(false, false)
    TriggerEvent("hoverfy:hidden", false)
    SendNUIMessage({ acao = "fechar" })
end

RegisterCommand(Config.comando, function()
    if painelAberto then return fecharPainel() end
    if abrindo then return end
    abrindo = true

    CreateThread(function()
        -- O Tunnel cede a corrotina: sem a trava, dois /clima rapidos
        -- abririam dois paineis e o segundo ficaria com foco preso.
        local dados = vSERVER.abrir()
        abrindo = false
        if type(dados) == "table" then abrirPainel(dados) end
        -- Sem dados = sem permissao; o Notify ja saiu do servidor.
    end)
end, false)

TriggerEvent("chat:addSuggestion", "/" .. Config.comando, "Horário, clima e apagão da cidade")
TriggerEvent("chat:addSuggestion", "/time", "Mudar a hora da cidade", {
    { name = "hora",   help = "0 a 23" },
    { name = "minuto", help = "0 a 59" },
})

-- Morte fecha o painel: sem isto o admin morre com ele aberto e fica com o
-- foco de mouse preso na tela de morte. Laco adaptativo, no idioma do
-- unity_core — 500ms so com o painel na tela.
CreateThread(function()
    while true do
        if painelAberto then
            if IsEntityDead(PlayerPedId()) then
                log("painel fechado pela morte")
                fecharPainel()
            end
            Wait(500)
        else
            Wait(2000)
        end
    end
end)

RegisterNUICallback("fechar", function(_, cb)
    fecharPainel()
    cb("ok")
end)

-- Aplica o que o SERVIDOR devolveu, nao o que a NUI mandou.
RegisterNUICallback("aplicar", function(dados, cb)
    CreateThread(function()
        local e = vSERVER.aplicar(dados)
        if type(e) == "table" then SendNUIMessage({ acao = "estado", estado = e }) end
        cb("ok")
    end)
end)

-- Acao: nao devolve estado porque nao mudou nada — o efeito esta no ceu.
RegisterNUICallback("soltarRaio", function(_, cb)
    CreateThread(function()
        vSERVER.soltarRaio()
        cb("ok")
    end)
end)

RegisterNUICallback("gravarPadrao", function(_, cb)
    CreateThread(function()
        local p = vSERVER.gravarPadrao()
        if type(p) == "table" then SendNUIMessage({ acao = "padrao", padrao = p }) end
        cb("ok")
    end)
end)

RegisterNUICallback("voltarPadrao", function(_, cb)
    CreateThread(function()
        local e = vSERVER.voltarPadrao()
        if type(e) == "table" then SendNUIMessage({ acao = "estado", estado = e }) end
        cb("ok")
    end)
end)

RegisterNUICallback("reinicio", function(dados, cb)
    CreateThread(function()
        local v = vSERVER.definirReinicio(dados and dados.v)
        if v then SendNUIMessage({ acao = "reinicio", v = v }) end
        cb("ok")
    end)
end)

-- Desfaz o que este resource impos no cliente. Sem isto, um restart com
-- apagao ligado deixa a cidade no escuro sem ninguem no ar pra desligar.
AddEventHandler("onResourceStop", function(nome)
    if nome ~= GetCurrentResourceName() then return end

    SetArtificialLightsState(false)
    SetArtificialLightsStateAffectsVehicles(false)
    if painelAberto then SetNuiFocus(false, false) end
    TriggerEvent("hoverfy:hidden", false)
end)
