Config = {}

-- =====================================================================
--  ACESSO
-- =====================================================================

Config.comando   = "clima"              -- /clima abre o painel
Config.permissao = "admin.permissao"    -- a mesma que o vrp_timesync usava
Config.debug     = false

-- =====================================================================
--  PADRAO DE FABRICA
--
--  Isto e so a PRIMEIRA carga. Assim que alguem grava um padrao pelo
--  painel, o valor vai pra tabela `vrp_srv_data` e este bloco nao e mais
--  consultado — mexer aqui depois disso nao muda nada no servidor que ja
--  rodou. Pra voltar de verdade ao de fabrica, apague as chaves
--  `axl_clima:padrao` e `axl_clima:estado` dessa tabela.
-- =====================================================================

Config.padrao = { hora = 6, min = 20, clima = "CLEAR" }

-- "padrao" = o servidor sobe no horario/clima gravados acima.
-- "manter" = sobe onde parou (o estado vivo e salvo de tempos em tempos).
Config.aoReiniciar = "padrao"

-- =====================================================================
--  OPERACAO — valores iniciais dos controles do painel
-- =====================================================================

Config.velPadrao       = 5      -- segundos reais por minuto no jogo
-- Minutos REAIS entre um sorteio e outro: nao acompanha a velocidade do
-- relogio. Com velPadrao = 5, dez minutos reais sao duas horas de jogo.
Config.intervaloPadrao = 10
Config.rotacaoPadrao   = true

-- Quais climas a rotacao automatica pode tirar. O painel edita esta lista.
Config.sorteioPadrao = { "CLEAR", "CLEARING", "EXTRASUNNY", "CLOUDS" }

-- Segundos que o clima leva pra virar. 0 troca no talho, e fica feio.
Config.transicaoClima = 15.0

-- =====================================================================
--  RAIOS
--
--  `CreateLightningThunder` nao tem parametro nenhum: e um clarao no ceu
--  inteiro, sem cor, formato nem posicao pra escolher. O desenho do raio
--  em si quem sorteia e o jogo, e sai diferente a cada disparo.
--
--  Por isso "estilo" aqui e a ASSINATURA DO DISPARO — quantos claroes e
--  com que espaco entre eles. E o unico eixo que existe, e da tres raios
--  bem distintos de se ver.
-- =====================================================================

-- O botao SORTEIA um destes a cada clique — nao ha escolha no painel, e de
-- proposito: o que o jogador ve e o ceu, e raio que cai sempre igual
-- denuncia o script. Some-se a isso o desenho do raio, que o jogo ja
-- sorteia sozinho a cada clarao.
--
-- `espaco` e em segundos, entre um clarao e o proximo do MESMO ritmo. Sao
-- seis porque seis da pra distinguir; passar disso vira variacao de meio
-- segundo que ninguem percebe. Acrescentar linha aqui basta.
Config.raioEstilos = {
    { nome = "Simples",        claroes = 1, espaco = 0.00 },
    { nome = "Duplo rapido",   claroes = 2, espaco = 0.20 },
    { nome = "Duplo espacado", claroes = 2, espaco = 0.80 },
    { nome = "Triplo rapido",  claroes = 3, espaco = 0.25 },
    { nome = "Sequencia",      claroes = 3, espaco = 1.20 },
    { nome = "Descarga",       claroes = 4, espaco = 0.15 },
}

-- O botao "Voltar ao padrao" mexe em hora e clima — e o que o rotulo diz.
-- Ligando isto, ele derruba o apagao junto, tratando o botao como
-- "normalizar a cidade" em vez de "restaurar hora e clima".
Config.voltarPadraoDerrubaApagao = false

-- De quanto em quanto tempo (minutos) o estado vivo e gravado, pro
-- "Manter o atual" ter onde voltar. So grava se algo mudou.
Config.salvarACada = 5

-- =====================================================================
--  CLIMAS — os 15 do GTA V
--
--  `id` e o que vai pro SetWeatherType: mexer nele quebra o jogo.
--  `nome` e so o rotulo do painel, pode traduzir a vontade.
--  `img` e o arquivo em `nui/Images/`, usado como FUNDO da celula. Clima
--  sem `img` cai no desenho vetorial do `icone` (sol, nuvem, solnuvem,
--  nevoa, chuva, raio, neve; nome desconhecido vira nuvem).
--
--  Arquivo novo aqui precisa entrar no `files{}` do fxmanifest — o
--  curinga `nui/Images/*.png` ja cobre, mas so vale apos restart.
-- =====================================================================

Config.climas = {
    { id = "EXTRASUNNY", nome = "Sol forte",  icone = "sol",      img = "sol_forte.png"  },
    { id = "CLEAR",      nome = "Limpo",      icone = "sol",      img = "limpo.png"      },
    { id = "NEUTRAL",    nome = "Neutro",     icone = "nuvem",    img = "neutro.png"     },
    { id = "SMOG",       nome = "Poluído",    icone = "nevoa",    img = "poluido.png"    },
    { id = "FOGGY",      nome = "Neblina",    icone = "nevoa",    img = "neblina.png"    },
    { id = "OVERCAST",   nome = "Encoberto",  icone = "nuvem",    img = "encoberto.png"  },
    { id = "CLOUDS",     nome = "Nublado",    icone = "nuvem",    img = "nublado.png"    },
    { id = "CLEARING",   nome = "Abrindo",    icone = "solnuvem", img = "abrindo.png"    },
    { id = "RAIN",       nome = "Chuva",      icone = "chuva",    img = "chuva.png"      },
    { id = "THUNDER",    nome = "Tempestade", icone = "raio",     img = "tempestade.png" },
    { id = "SNOW",       nome = "Neve",       icone = "neve",     img = "neve.png"       },
    { id = "BLIZZARD",   nome = "Nevasca",    icone = "neve",     img = "nevasca.png"    },
    { id = "SNOWLIGHT",  nome = "Neve fraca", icone = "neve",     img = "neve_fraca.png" },
    { id = "XMAS",       nome = "Natal",      icone = "neve",     img = "natal.png"      },
    { id = "HALLOWEEN",  nome = "Halloween",  icone = "raio",     img = "halloween.png"  },
}

-- =====================================================================
--  INDICE DERIVADO — `Config.climaValido[id]` responde em O(1).
--
--  Existe porque o servidor confere TODO clima que vem da NUI, e varrer a
--  lista de 15 a cada clique seria trabalho repetido a toa. Tambem e o que
--  garante que um pacote forjado com "RAIN; DROP TABLE" nunca chegue no
--  SetWeatherType: o que nao esta neste indice e recusado.
-- =====================================================================

Config.climaValido = {}
for _, c in ipairs(Config.climas) do
    Config.climaValido[c.id] = c.nome
end

