local Tunnel = module("vrp", "lib/Tunnel")
local Proxy  = module("vrp", "lib/Proxy")
vRP = Proxy.getInterface("vRP")

vCLIMA = {}
Tunnel.bindInterface("axl_clima", vCLIMA)

local function log(...)
    if Config.debug then print("^6[AXL CLIMA]^7", ...) end
end

-- =====================================================================
--  ESTADO — o servidor e o dono. O client so aplica o que chega; nada de
--  hora ou clima e decidido la, senao dois jogadores veem ceus diferentes.
-- =====================================================================

local estado = {
    hora = Config.padrao.hora, min = Config.padrao.min,
    correndo = true, vel = Config.velPadrao,

    clima = Config.padrao.clima,

    rotacao = Config.rotacaoPadrao, intervalo = Config.intervaloPadrao,
    -- COPIA: apontando pra tabela do Config, mexer no sorteio editaria o
    -- proprio padrao de fabrica em memoria.
    sorteio = { table.unpack(Config.sorteioPadrao) },

    apagao = false, apagaoCarros = false,
}

local padrao      = { hora = Config.padrao.hora, min = Config.padrao.min,
                      clima = Config.padrao.clima }
local aoReiniciar = Config.aoReiniciar

local pronto = false   -- so responde a NUI depois de ler o banco
local sujo   = false   -- ha mudanca ainda nao gravada?

-- Fora das threads porque precisam ser zerados de fora. Ver `zerarContagem`.
local accRelogio, accRotacao = 0, 0

-- Anti-spam do botao de raio, por jogador: sem isto um clique preso enfia
-- rajada em cima de rajada e a cidade vira estroboscopio.
local ultimoRaioDe = {}

-- =====================================================================
--  PERMISSAO — em TODA acao, nunca so na abertura. O Tunnel e canal
--  aberto: quem tem executor chama o vCLIMA sem passar pelo /clima.
-- =====================================================================

local function autorizado(source)
    local user_id = vRP.getUserId(source)
    if not user_id then return false end
    return vRP.hasPermission(user_id, Config.permissao)
end

local function negar(source)
    TriggerClientEvent("Notify", source, "negado", "Você não tem permissão para isso.")
    return nil
end

-- =====================================================================
--  SANEAMENTO — nada da NUI entra no estado sem passar aqui. Campo torto
--  cai no valor de agora, entao pacote incompleto nao zera o que valia.
-- =====================================================================

local function limitar(v, minimo, maximo, atual)
    v = tonumber(v)
    if not v then return atual end
    v = math.floor(v)
    if v < minimo then return minimo end
    if v > maximo then return maximo end
    return v
end

local function saoBool(v, atual)
    if v == true or v == false then return v end
    return atual
end

-- NUNCA vazia, e o motivo forte nao e a rotacao ficar sem o que tirar:
-- tabela Lua vazia sai do `json.encode` como `{}` (objeto, nao lista), e a
-- NUI faz `sorteio.indexOf(...)` nela e estoura o painel inteiro.
local function sanearSorteio(lista, atual)
    if type(lista) ~= "table" then return atual end

    local vistos, limpa = {}, {}
    for _, id in ipairs(lista) do
        if type(id) == "string" and Config.climaValido[id] and not vistos[id] then
            vistos[id] = true
            limpa[#limpa + 1] = id
        end
    end

    if #limpa == 0 then return atual end
    return limpa
end

local function sanearClima(id, atual)
    if type(id) == "string" and Config.climaValido[id] then return id end
    return atual
end

-- =====================================================================
--  BANCO — uma chave de srvdata por coisa; e uma linha global.
--
--  oxmysql DIRETO e nao `vRP.setSData`: aquele cai em `MySQL.update.await`
--  e CEDE A CORROTINA — no Tunnel o painel esperava o banco pra responder,
--  e no `onResourceStop` a espera nunca voltava e a gravacao se perdia.
-- =====================================================================

local SQL_LER   = "SELECT dvalue FROM vrp_srv_data WHERE dkey = ?"
local SQL_GRAVA = "REPLACE INTO vrp_srv_data (dkey, dvalue) VALUES (?, ?)"

-- Sem callback e sem await: dispara e segue.
local function gravar(chave, valor)
    exports.oxmysql:execute(SQL_GRAVA, { chave, valor })
end

-- Com await, e tudo bem: so acontece no boot, dentro de thread.
local function lerJson(chave)
    local p = promise.new()
    exports.oxmysql:execute(SQL_LER, { chave }, function(r) p:resolve(r or {}) end)
    local linhas = Citizen.Await(p)

    local cru = linhas[1] and linhas[1].dvalue
    if type(cru) ~= "string" or cru == "" then return nil end

    -- srvdata e texto livre: uma linha editada na mao derrubaria o start.
    local ok, valor = pcall(json.decode, cru)
    if not ok or type(valor) ~= "table" then
        print("^3[AXL CLIMA] '" .. chave .. "' esta ilegivel no banco — usando o config.^7")
        return nil
    end
    return valor
end

local function gravarPadraoNoBanco()
    gravar("axl_clima:padrao",
        json.encode({ hora = padrao.hora, min = padrao.min, clima = padrao.clima,
                      aoReiniciar = aoReiniciar }))
end

-- So grava o estado vivo quando ele vai ser LIDO de volta: em "padrao" o
-- boot descarta esta chave, e gravar seria um REPLACE por clique a toa.
local function gravarEstadoNoBanco(forcar)
    if aoReiniciar ~= "manter" and not forcar then return end
    gravar("axl_clima:estado", json.encode(estado))
    sujo = false
end

-- =====================================================================
--  DIFUSAO — `tick` corre a cada minuto e leva dois numeros; `sync` leva o
--  estado inteiro e so sai quando algo muda. O `sync` carrega campos que so
--  o painel usa: ele nao roda em laco, e um formato so e o que faz dois
--  admins verem a mesma coisa.
-- =====================================================================

local function difundirTick(alvo)
    TriggerClientEvent("axl_clima:tick", alvo or -1, estado.hora, estado.min)
end

local function difundirTudo(alvo)
    TriggerClientEvent("axl_clima:sync", alvo or -1, estado)
end

-- Vai o NUMERO DO ESTILO; quem toca a sequencia e o client, que ja tem a
-- tabela pelo `config.lua` compartilhado. Mandar clarao por clarao seria um
-- evento por piscada, e ainda chegariam embolados.
local function difundirRaio(estilo)
    TriggerClientEvent("axl_clima:raio", -1, estilo)
end

-- =====================================================================
--  RELOGIO
-- =====================================================================

local function avancarMinuto()
    estado.min = estado.min + 1
    if estado.min >= 60 then
        estado.min = 0
        estado.hora = (estado.hora + 1) % 24
    end
    sujo = true
end

-- Acumulador de 1s, e nao `Wait(vel * 1000)`: com o Wait longo, baixar a
-- velocidade no painel so valeria quando o Wait velho terminasse.
CreateThread(function()
    while true do
        Wait(1000)
        if pronto and estado.correndo then
            accRelogio = accRelogio + 1
            if accRelogio >= estado.vel then
                accRelogio = 0
                avancarMinuto()
                difundirTick()
            end
        end
    end
end)

-- =====================================================================
--  ROTACAO — `intervalo` e em minutos REAIS, nao de jogo: nao acompanha a
--  velocidade do relogio.
-- =====================================================================

local function sortearClima()
    local lista = estado.sorteio
    if #lista == 0 then return end

    -- `math.random(#lista)`, nao `math.random(1)`: o vrp_timesync usava o
    -- segundo, que sempre devolve 1 — a rotacao dele nunca saiu do CLEAR.
    if #lista == 1 then
        if lista[1] == estado.clima then return end
        estado.clima = lista[1]
    else
        -- Ate cair num diferente: repetir o atual parece rotacao quebrada.
        local novo = estado.clima
        for _ = 1, 8 do
            novo = lista[math.random(#lista)]
            if novo ~= estado.clima then break end
        end
        if novo == estado.clima then return end
        estado.clima = novo
    end

    sujo = true
    gravarEstadoNoBanco()
    log("rotacao sorteou", estado.clima)
    difundirTudo()
end

CreateThread(function()
    while true do
        Wait(60000)
        if pronto and estado.rotacao then
            accRotacao = accRotacao + 1
            if accRotacao >= estado.intervalo then
                accRotacao = 0
                sortearClima()
            end
        else
            -- Religar a rotacao nao deve disparar sorteio imediato.
            accRotacao = 0
        end
    end
end)

-- =====================================================================
--  ZERAR CONTAGEM — sem isto os contadores correm por baixo da acao
--  manual: clima escolhido 20s antes do sorteio era trocado 20s depois
--  (o buraco que o botao "Travar" tapava), e hora acertada com o contador
--  em 4 de 5 virava o minuto 1s depois.
-- =====================================================================

local function zerarContagemRelogio()  accRelogio = 0 end
local function zerarContagemRotacao()  accRotacao = 0 end

-- =====================================================================
--  GRAVACAO PERIODICA — so pro "manter" ter onde voltar, e so se mudou.
-- =====================================================================

CreateThread(function()
    -- `math.max(1, ...)`: `salvarACada = 0` viraria Wait(0) gravando por frame.
    local espera = math.max(1, tonumber(Config.salvarACada) or 5) * 60000
    while true do
        Wait(espera)
        if pronto and sujo and aoReiniciar == "manter" then
            gravarEstadoNoBanco()
            log("estado gravado")
        end
    end
end)

-- =====================================================================
--  CARGA INICIAL
-- =====================================================================

CreateThread(function()
    Wait(2000)   -- espera o oxmysql subir

    -- Rede pro config: sorteio vazio quebra a NUI (ver `sanearSorteio`).
    if #estado.sorteio == 0 then
        estado.sorteio = { Config.padrao.clima }
        print("^3[AXL CLIMA] Config.sorteioPadrao esta vazio — usando so o clima padrao.^7")
    end

    local p = lerJson("axl_clima:padrao")
    if p then
        padrao.hora  = limitar(p.hora, 0, 23, padrao.hora)
        padrao.min   = limitar(p.min,  0, 59, padrao.min)
        padrao.clima = sanearClima(p.clima, padrao.clima)
        if p.aoReiniciar == "manter" or p.aoReiniciar == "padrao" then
            aoReiniciar = p.aoReiniciar
        end
    end

    if aoReiniciar == "manter" then
        local e = lerJson("axl_clima:estado")
        if e then
            estado.hora      = limitar(e.hora, 0, 23, estado.hora)
            estado.min       = limitar(e.min,  0, 59, estado.min)
            estado.vel       = limitar(e.vel,  1, 60, estado.vel)
            estado.intervalo = limitar(e.intervalo, 1, 60, estado.intervalo)
            estado.correndo  = saoBool(e.correndo, estado.correndo)
            estado.rotacao   = saoBool(e.rotacao,  estado.rotacao)
            estado.clima     = sanearClima(e.clima, estado.clima)
            estado.sorteio   = sanearSorteio(e.sorteio, estado.sorteio)


            -- Apagao NAO sobrevive ao restart, de proposito: subir a cidade
            -- no escuro sem ninguem ter pedido, e quem ligou nem online.
            estado.apagao, estado.apagaoCarros = false, false
        end
    else
        estado.hora, estado.min = padrao.hora, padrao.min
        estado.clima = padrao.clima
    end

    pronto = true
    -- Para -1: cobre quem entrou nos 2s e teve o pedirSync recusado.
    difundirTudo()
    log(("pronto — %02d:%02d, %s, reinicio=%s")
        :format(estado.hora, estado.min, estado.clima, aoReiniciar))
end)

-- Sem isto o jogador que entra so acerta o relogio no primeiro tick, e o
-- clima so na primeira mudanca.
RegisterServerEvent("axl_clima:pedirSync")
AddEventHandler("axl_clima:pedirSync", function()
    if not pronto then return end
    difundirTudo(source)
end)

-- =====================================================================
--  TUNNEL — o que a NUI pode pedir
-- =====================================================================

function vCLIMA.abrir()
    local source = source
    if not autorizado(source) then return negar(source) end
    if not pronto then return nil end

    return {
        estado      = estado,
        padrao      = padrao,
        aoReiniciar = aoReiniciar,
        climas      = Config.climas,
    }
end

-- Devolve o estado JA SANEADO: valor corrigido aqui (vel 900 -> 60) tem que
-- aparecer corrigido no painel, nao o que o admin digitou.
function vCLIMA.aplicar(dados)
    local source = source
    if not autorizado(source) then return negar(source) end
    if not pronto or type(dados) ~= "table" then return nil end

    local horaAntes   = estado.hora
    local minAntes    = estado.min
    local climaAntes  = estado.clima
    local apagaoAntes = estado.apagao

    estado.hora      = limitar(dados.hora, 0, 23, estado.hora)
    estado.min       = limitar(dados.min,  0, 59, estado.min)
    estado.vel       = limitar(dados.vel,  1, 60, estado.vel)
    estado.intervalo = limitar(dados.intervalo, 1, 60, estado.intervalo)
    estado.correndo  = saoBool(dados.correndo, estado.correndo)
    estado.rotacao   = saoBool(dados.rotacao,  estado.rotacao)
    estado.clima     = sanearClima(dados.clima, estado.clima)
    estado.sorteio   = sanearSorteio(dados.sorteio, estado.sorteio)
    estado.apagao    = saoBool(dados.apagao, estado.apagao)


    -- Filho nao sobrevive ao pai: sem isto, desligar e religar o apagao
    -- traria os farois apagados de volta sem ninguem pedir.
    estado.apagaoCarros = estado.apagao and saoBool(dados.apagaoCarros, estado.apagaoCarros) or false

    if estado.hora ~= horaAntes or estado.min ~= minAntes then zerarContagemRelogio() end
    if estado.clima ~= climaAntes then zerarContagemRotacao() end

    sujo = true
    gravarEstadoNoBanco()
    difundirTudo()

    local quem = GetPlayerName(source) or "?"
    if estado.clima ~= climaAntes then
        print(("[axl_clima] %s trocou o clima para %s"):format(quem, estado.clima))
    end
    if estado.apagao ~= apagaoAntes then
        print(("[axl_clima] %s %s o apagao"):format(quem, estado.apagao and "LIGOU" or "desligou"))
    end

    return estado
end

-- Acao, nao ajuste: nao mexe no estado nem grava nada, so dispara.
function vCLIMA.soltarRaio()
    local source = source
    if not autorizado(source) then return negar(source) end
    if not pronto then return nil end

    local agora = GetGameTimer()
    if ultimoRaioDe[source] and (agora - ultimoRaioDe[source]) < 1000 then return nil end
    ultimoRaioDe[source] = agora

    -- `math.random(0)` estoura com "interval is empty": lista esvaziada no
    -- config derrubaria a chamada do Tunnel a cada clique no botao.
    local quantos = #Config.raioEstilos
    if quantos == 0 then
        print("^3[AXL CLIMA] Config.raioEstilos esta vazio — nao ha ritmo pra sortear.^7")
        return nil
    end

    -- Sorteia AQUI e nao em cada client: assim todo mundo na cidade ve o
    -- mesmo ritmo. Cada um sorteando daria trovoadas diferentes lado a lado.
    local estilo = math.random(quantos)

    difundirRaio(estilo)
    log("raio solto por", GetPlayerName(source) or "?", Config.raioEstilos[estilo].nome)
    return true
end

function vCLIMA.gravarPadrao()
    local source = source
    if not autorizado(source) then return negar(source) end
    if not pronto then return nil end

    padrao.hora, padrao.min, padrao.clima = estado.hora, estado.min, estado.clima
    gravarPadraoNoBanco()

    print(("[axl_clima] %s gravou o padrao: %02d:%02d %s")
        :format(GetPlayerName(source) or "?", padrao.hora, padrao.min, padrao.clima))

    return padrao
end

function vCLIMA.voltarPadrao()
    local source = source
    if not autorizado(source) then return negar(source) end
    if not pronto then return nil end

    local climaAntes = estado.clima

    estado.hora, estado.min = padrao.hora, padrao.min
    estado.clima = padrao.clima

    if Config.voltarPadraoDerrubaApagao then
        estado.apagao, estado.apagaoCarros = false, false
    end

    zerarContagemRelogio()
    if estado.clima ~= climaAntes then zerarContagemRotacao() end

    sujo = true
    gravarEstadoNoBanco()
    difundirTudo()
    return estado
end

function vCLIMA.definirReinicio(v)
    local source = source
    if not autorizado(source) then return negar(source) end
    if v ~= "padrao" and v ~= "manter" then return nil end

    aoReiniciar = v
    gravarPadraoNoBanco()

    -- `forcar` porque o aoReiniciar acabou de mudar: sem gravar agora, um
    -- restart antes do salvamento periodico cairia num estado velho.
    if v == "manter" then gravarEstadoNoBanco(true) end

    return aoReiniciar
end

-- =====================================================================
--  /time hora minuto — era do vrp_timesync, que fica `stop`. Sem isto o
--  comando sumiria junto e o dedo do admin ja esta viciado nele.
-- =====================================================================

RegisterCommand("time", function(source, args)
    if source == 0 then return end
    if not autorizado(source) then
        TriggerClientEvent("Notify", source, "negado", "Você não tem permissão para isso.")
        return
    end

    local h, m = tonumber(args[1]), tonumber(args[2] or 0)
    if not h or not m or h < 0 or h > 23 or m < 0 or m > 59 then
        TriggerClientEvent("Notify", source, "negado", "Use: /time hora minuto (0-23 e 0-59)")
        return
    end

    estado.hora, estado.min = math.floor(h), math.floor(m)
    zerarContagemRelogio()

    sujo = true
    gravarEstadoNoBanco()
    difundirTudo()

    print(("[axl_clima] %s mudou a hora para %02d:%02d")
        :format(GetPlayerName(source) or "?", estado.hora, estado.min))
end, false)

-- A tabela do anti-spam so cresce se ninguem limpar.
AddEventHandler("playerDropped", function()
    ultimoRaioDe[source] = nil
end)

-- Funciona porque `gravar` nao espera resposta. Com await aqui, a gravacao
-- ficaria esperando um banco que ninguem mais vai escutar.
AddEventHandler("onResourceStop", function(nome)
    if nome ~= GetCurrentResourceName() then return end
    if pronto and sujo and aoReiniciar == "manter" then gravarEstadoNoBanco() end
end)
