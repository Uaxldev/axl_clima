/* =====================================================================
   axl_clima — NUI.

   O SERVIDOR e o dono do estado. Isto aqui e uma copia de trabalho: o
   admin mexe a vontade, e so o "Aplicar na cidade" manda. O que volta do
   Lua e que vira verdade — se o servidor corrigiu um valor, o painel
   passa a mostrar o corrigido, nao o que foi digitado.
   ===================================================================== */

const RES = (typeof GetParentResourceName === "function")
  ? GetParentResourceName() : "axl_clima";

const post = (nome, dados) =>
  fetch(`https://${RES}/${nome}`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=UTF-8" },
    body: JSON.stringify(dados || {}),
  }).catch(() => {});   /* NUI fechando no meio do fetch nao e erro */

const $ = (id) => document.getElementById(id);
const p2 = (v) => String(v).padStart(2, "0");

/* ---------- desenhos dos climas ----------
   Nome de icone desconhecido cai em `nuvem`: clima novo no config.lua com
   icone errado aparece feio, mas nao quebra a grade. */
const ICO = {
  sol:      '<circle cx="12" cy="12" r="4.2"/><path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.2 5.2l1.4 1.4M17.4 17.4l1.4 1.4M18.8 5.2l-1.4 1.4M6.6 17.4l-1.4 1.4"/>',
  nuvem:    '<path d="M7 18h10a3.6 3.6 0 0 0 .3-7.2A5.3 5.3 0 0 0 7.1 11 3.5 3.5 0 0 0 7 18z"/>',
  solnuvem: '<circle cx="8" cy="8" r="3"/><path d="M8 2.6v1.6M2.6 8h1.6M4.4 4.4l1.1 1.1"/><path d="M10 19h7a3 3 0 0 0 .2-6 4.5 4.5 0 0 0-8.6-.6A3 3 0 0 0 10 19z"/>',
  nevoa:    '<path d="M7 14h10a3.4 3.4 0 0 0 .3-6.8A5 5 0 0 0 7.1 7.4 3.3 3.3 0 0 0 7 14z"/><path d="M4 17.5h16M6.5 20.5h11"/>',
  chuva:    '<path d="M7 15h10a3.4 3.4 0 0 0 .3-6.8A5 5 0 0 0 7.1 8.4 3.3 3.3 0 0 0 7 15z"/><path d="M8.5 18l-1 2.5M12 18l-1 2.5M15.5 18l-1 2.5"/>',
  raio:     '<path d="M7 14.5h10a3.4 3.4 0 0 0 .3-6.8A5 5 0 0 0 7.1 7.9 3.3 3.3 0 0 0 7 14.5z"/><path d="M12.8 16.5l-2.6 3.4h3l-1.2 2.6"/>',
  neve:     '<path d="M7 14h10a3.4 3.4 0 0 0 .3-6.8A5 5 0 0 0 7.1 7.4 3.3 3.3 0 0 0 7 14z"/><path d="M8.5 17.6v.02M12 19.2v.02M15.5 17.6v.02M12 16.6v.02"/>',
};
const svg = (d) => '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" '
  + 'stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'
  + (d || ICO.nuvem) + '</svg>';

/* ---------- copia de trabalho ---------- */
let CLIMAS = [];                 /* vem do Config.climas do Lua */

/* Nos guardados no `montarGrades`, pra o `pinta()` nao varrer o DOM. */
let CELULAS = [], FICHAS = [], OPCOES = [];
let nomeDe = {};                 /* id -> nome, pra vitrine e faixa */
let st     = null;               /* estado em edicao */
let padrao = { hora: 6, min: 20, clima: "CLEAR" };
let reinicio = "padrao";
let sujo   = false;              /* ha edicao ainda nao aplicada? */

/* ---------- monta as grades uma vez ----------
   `innerHTML` aqui e seguro: acontece na abertura, nao em loop. */
function montarGrades() {
  /* Com `img` a celula vira o proprio ceu; sem ela cai no desenho vetorial.
     O caminho e relativo ao index.html, entao `Images/` e nao `nui/Images/`. */
  $("climas").innerHTML = CLIMAS.map(c => {
    const temImg = typeof c.img === "string" && c.img !== "";
    const fundo  = temImg ? ` style="background-image:url('Images/${c.img}')"` : "";
    const miolo  = temImg ? "" : svg(ICO[c.icone]);
    return `<div class="cli${temImg ? " comImg" : ""}" data-id="${c.id}" title="${c.id}"${fundo}>`
         + `${miolo}<span class="n">${c.nome}</span></div>`;
  }).join("");

  $("fichas").innerHTML = CLIMAS.map(c =>
    `<span class="fi" data-id="${c.id}">${c.nome}</span>`).join("");

  /* Guarda os nos: eles nao mudam mais depois daqui, e o `pinta()` varria o
     DOM atras deles a cada desenho. */
  CELULAS = [...document.querySelectorAll(".cli")];
  FICHAS  = [...document.querySelectorAll(".fi")];
  OPCOES  = [...document.querySelectorAll("#segReinicio .op")];
}

/* `Array.isArray` nao e paranoia: tabela Lua VAZIA sai do `json.encode` como
   `{}` — objeto, nao lista — e o `indexOf` do clique numa ficha estouraria
   o painel. Normalizar num lugar so e mais barato que checar em cada uso. */
function adota(e) {
  st = e || {};
  if (!Array.isArray(st.sorteio)) st.sorteio = [];
}

/* ---------- desenha ----------
   Duas funcoes: o tique mexe em dois digitos, e o `pinta()` inteiro ali
   redesenharia as 15 celulas e as 15 fichas por nada. */
function pintaRelogio() {
  if (!st) return;
  $("relogio").textContent = `${p2(st.hora)}:${p2(st.min)}`;
  $("vHora").textContent = st.hora + " h";
  $("vMin").textContent  = st.min + " min";
  $("sHora").value = st.hora;
  $("sMin").value  = st.min;
}

function pinta() {
  if (!st) return;

  pintaRelogio();

  $("vVel").textContent = st.vel + " s";
  $("sVel").value = st.vel;
  /* 1440 minutos de jogo x vel segundos, em horas reais. */
  const horasReais = (1440 * st.vel) / 3600;
  $("obsVel").textContent = "Um dia inteiro leva "
    + (horasReais >= 1
        ? horasReais.toFixed(horasReais % 1 ? 1 : 0) + "h"
        : Math.round(horasReais * 60) + "min")
    + " de tempo real.";

  $("vInt").textContent = st.intervalo + " min";
  $("sInt").value = st.intervalo;


  const nome = nomeDe[st.clima] || st.clima;
  $("rotClima").textContent = st.clima;
  $("agora").textContent = `${nome} · 1 min a cada ${st.vel}s`;


  liga("swCongela", st.correndo);
  liga("swRot",     st.rotacao);
  liga("swApagao",  st.apagao);
  liga("swApagaoCarros", st.apagaoCarros);

  $("swApagaoCarros").classList.toggle("off", !st.apagao);
  $("cpVel").classList.toggle("off", !st.correndo);

  const noSorteio = new Set(st.sorteio);
  CELULAS.forEach(el => el.classList.toggle("on", el.dataset.id === st.clima));
  FICHAS.forEach(el => el.classList.toggle("on", noSorteio.has(el.dataset.id)));

  selo("seloTempo",  st.correndo ? "Correndo" : "Congelado", st.correndo ? "on" : "trav");
  selo("seloClima",  st.rotacao ? "Rotação ativa" : "Clima fixo", st.rotacao ? "on" : "trav");
  selo("seloApagao", st.apagao ? "Apagão" : "Luzes ok", st.apagao ? "perigo" : "on");

  $("padVal").innerHTML = `${p2(padrao.hora)}:${p2(padrao.min)}`
    + ` <span class="sep">·</span> ${nomeDe[padrao.clima] || padrao.clima}`;
  OPCOES.forEach(el => el.classList.toggle("on", el.dataset.v === reinicio));

  const av = $("aviso");
  av.textContent = sujo ? "Alterado — clique em Aplicar pra valer na cidade." : " ";
  av.classList.remove("alerta");
}

function liga(id, v) { $(id).classList.toggle("on", !!v); }
function selo(id, texto, classe) {
  const el = $(id);
  el.textContent = texto;
  el.className = "selo " + classe;
}
function mexeu() { sujo = true; pinta(); }

/* =====================================================================
   ENTRADA — o que o Lua manda
   ===================================================================== */

window.addEventListener("message", (ev) => {
  const d = ev.data || {};

  if (d.acao === "abrir") {
    CLIMAS = d.climas || [];
    nomeDe = {};
    CLIMAS.forEach(c => { nomeDe[c.id] = c.nome; });
    /* Remonta SEMPRE: `CLIMAS` chega novo a cada abertura, e a trava de "so
       na primeira vez" que morava aqui deixava a grade com as celulas
       velhas quando a lista mudava. */
    montarGrades();

    adota(d.estado);
    padrao   = d.padrao || padrao;
    reinicio = d.aoReiniciar || "padrao";
    sujo     = false;

    $("painel").classList.remove("fechado");
    pinta();

  } else if (d.acao === "fechar") {
    $("painel").classList.add("fechado");

  } else if (d.acao === "estado") {
    /* Verdade do servidor: descarta a edicao pendente. E daqui — e SO daqui
       — que o "alterado" se apaga, porque e a confirmacao de que ele
       aceitou. */
    adota(d.estado);
    sujo = false;
    pinta();

  } else if (d.acao === "padrao") {
    padrao = d.padrao;
    pinta();

  } else if (d.acao === "reinicio") {
    reinicio = d.v;
    pinta();

  } else if (d.acao === "tick") {
    /* Relogio da cidade andando. Ignorado enquanto ha edicao pendente:
       senao o tick puxaria o slider de hora de volta debaixo do dedo de
       quem esta arrastando. */
    if (st && !sujo) { st.hora = d.h; st.min = d.m; pintaRelogio(); }
  }
});

/* =====================================================================
   SAIDA — o que o admin faz
   ===================================================================== */

$("sHora").oninput = e => { st.hora = +e.target.value; mexeu(); };
$("sMin").oninput  = e => { st.min  = +e.target.value; mexeu(); };
$("sVel").oninput  = e => { st.vel  = +e.target.value; mexeu(); };
$("sInt").oninput  = e => { st.intervalo = +e.target.value; mexeu(); };

document.querySelectorAll(".at").forEach(el =>
  el.onclick = () => { st.hora = +el.dataset.h; st.min = 0; mexeu(); });

/* O toggle diz "Relógio correndo", entao ligado = correndo. */
$("swCongela").onclick = () => { st.correndo = !st.correndo; mexeu(); };
$("swRot").onclick     = () => { st.rotacao  = !st.rotacao;  mexeu(); };

$("swApagao").onclick = () => {
  st.apagao = !st.apagao;
  if (!st.apagao) st.apagaoCarros = false;   /* filho nao sobrevive ao pai */
  mexeu();
};
$("swApagaoCarros").onclick = () => {
  if (!st.apagao) return;
  st.apagaoCarros = !st.apagaoCarros;
  mexeu();
};

/* Nao chama `mexeu()` nem espera resposta: soltar raio e acao, nao ajuste.
   Marcar o painel como "alterado" faria o admin achar que tem coisa
   esperando o Aplicar, e o efeito esta no ceu, nao na tela. */
$("btRaio").onclick = () => post("soltarRaio");

$("climas").onclick = (e) => {
  const el = e.target.closest(".cli"); if (!el) return;
  st.clima = el.dataset.id; mexeu();
};

$("fichas").onclick = (e) => {
  const el = e.target.closest(".fi"); if (!el) return;
  const id = el.dataset.id;
  const i  = st.sorteio.indexOf(id);
  /* Sorteio vazio faria a rotacao nao ter o que tirar — a ultima ficha
     nao sai. O servidor recusa igual, isto aqui e so pra dar o retorno
     na hora em vez de deixar o clique parecer que funcionou. */
  if (i >= 0) { if (st.sorteio.length > 1) st.sorteio.splice(i, 1); }
  else st.sorteio.push(id);
  mexeu();
};

/* NAO limpa o `sujo` aqui: quem limpa e a resposta do servidor. Limpando no
   clique, admin sem permissao via o "alterado" sumir como se tivesse dado
   certo, e a tela passava a mentir sobre o que a cidade vivia. */
$("btAplicar").onclick = () => post("aplicar", st);
$("btPadrao").onclick  = () => post("voltarPadrao");

/* Quem grava e o SERVIDOR, a partir do estado dele — nao do que esta na
   tela por aplicar. Com edicao pendente os dois nao batem, entao avisa em
   vez de gravar o inesperado. */
$("btGravaPadrao").onclick = () => {
  if (sujo) {
    const av = $("aviso");
    av.textContent = "Aplique primeiro — o padrão grava o que já está na cidade.";
    av.classList.add("alerta");
    return;
  }
  post("gravarPadrao");
};

$("segReinicio").onclick = (e) => {
  const el = e.target.closest(".op"); if (!el) return;
  post("reinicio", { v: el.dataset.v });
};

/* =====================================================================
   FECHAMENTO — clique e tecla, padrao da base
   ===================================================================== */

const fecha = () => {
  $("painel").classList.add("fechado");
  post("fechar");
};

$("btEsc").onclick = fecha;

document.addEventListener("keydown", (e) => {
  /* Guarda de INPUT com a ressalva que ja mordeu: `type=range` TAMBEM e
     INPUT e fica com foco apos qualquer arrasto — sem excluir o range, mexer
     num slider e apertar ESC nao fecharia mais o painel. */
  const alvo = e.target;
  if (alvo && alvo.tagName === "INPUT" && alvo.type !== "range") {
    if (e.key === "Escape") alvo.blur();
    return;
  }
  if (e.key === "Escape") fecha();
});
