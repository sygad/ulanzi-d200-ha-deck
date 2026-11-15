/* Ulanzi Deck — the configuration panel.
 *
 * A port of the design mock-up (not kept in this repo) into a Home Assistant
 * custom panel. The markup, styles and behaviour are the mockup's; what changed
 * is where the data comes from: entities from Home Assistant instead of a
 * sample list, the draft in Home Assistant's storage instead of the browser's,
 * and Send to device actually sending.
 */
const STATIC=new URL(".",import.meta.url).pathname.replace(/\/$/,"");
let ICONS={}, ALIAS={};
const assets=Promise.all([
  fetch(STATIC+"/icons.json").then(r=>r.json()),
  fetch(STATIC+"/alias.json").then(r=>r.json())
]).then(([i,a])=>{ICONS=i;ALIAS=a});

// @font-face does not register from inside a shadow root, so it goes on the document
if(!document.getElementById("ulanzi-deck-mdi")){
  const st=document.createElement("style");
  st.id="ulanzi-deck-mdi";
  st.textContent='@font-face{font-family:"UlanziMDI";src:url("'+STATIC+'/mdi.woff2") format("woff2");font-display:block}';
  document.head.appendChild(st);
}

const STYLE=`
/* Layout: HA app bar on top, deck preview left, key inspector right; one column on a phone. */
:host{
  --bg:var(--primary-background-color,#f5f5f5); --card:var(--card-background-color,#fff);
  --fg:var(--primary-text-color,#212121); --fg2:var(--secondary-text-color,#727272);
  --divider:var(--divider-color,rgba(0,0,0,.12)); --primary:var(--primary-color,#03a9f4);
  --bar:var(--app-header-background-color,var(--primary-color,#03a9f4)); --bar-fg:var(--app-header-text-color,#fff);
  --ok:#43a047; --deck-shell:#1f2124; --deck-face:#0b0c0d;
  /* A black key is shown a shade off black here, so its shape can be seen against
     the deck's face; on the deck itself it is true black (BACKGROUND in render.py).
     --track is the unfilled part of a bar or dial on such a key. */
  --keybg:#17181a; --track:#2c2c2c;
  --sunk:var(--input-fill-color,rgba(127,127,127,.1)); --hover:rgba(127,127,127,.14);
  --font:var(--ha-font-family-body,"Roboto",system-ui,-apple-system,"Segoe UI",sans-serif);
  --mono:"Roboto Mono",ui-monospace,SFMono-Regular,Menlo,monospace;
  display:block;height:100vh;overflow:auto;background:var(--bg);color:var(--fg);
  font-family:var(--font);font-size:14px;line-height:1.45;-webkit-font-smoothing:antialiased}
[hidden]{display:none!important}
img{max-width:100%}
*{box-sizing:border-box}
h1,h2{margin:0;font-weight:500;text-wrap:balance}
.mi{font-family:"UlanziMDI";font-style:normal;font-weight:400;line-height:1;display:inline-block;
  -webkit-font-smoothing:antialiased;font-feature-settings:normal;font-variant:normal}

.bar{background:var(--bar);color:var(--bar-fg);position:sticky;top:0;z-index:40;
  box-shadow:0 2px 4px rgba(0,0,0,.18)}
.bar-in{padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px));
  min-height:64px;display:flex;align-items:center;gap:14px;flex-wrap:wrap}
.bar h1{font-size:20px;font-weight:400;flex:1;min-width:0}
.dots{appearance:none;border:0;background:none;color:inherit;cursor:pointer;padding:10px 6px;margin-left:-6px;border-radius:50%;display:flex;flex-direction:column;gap:4px;opacity:.9}.dots i{width:18px;height:2px;background:currentColor;border-radius:2px}
.dots:focus-visible{outline:2px solid currentColor}
.getapp{grid-column:1/-1;max-width:620px;margin:6vh auto 0}
.getapp .card-b{display:flex;flex-direction:column;align-items:flex-start;gap:14px;padding:32px 30px}
.getapp h2{margin:0;font-size:22px;font-weight:500}
.getapp p{margin:0;line-height:1.6;color:var(--fg2);font-size:14.5px}
.getapp #btn-getapp{margin-top:6px;padding:13px 22px;font-size:14px}
.getapp .getapp-note{font-size:13px}
.getapp .getapp-note a{color:var(--fg2)}
.getapp .getapp-err{color:#c62828;font-size:13px}
.gatehelp{border-top:1px solid var(--divider);margin-top:4px;padding-top:16px;
  display:flex;flex-direction:column;align-items:flex-start;gap:10px}
.gatehelp h3{margin:0;font-size:15px;font-weight:500}
.gatehelp p{margin:0;font-size:13.5px;line-height:1.55;color:var(--fg2)}
.gatehelp b{color:var(--fg);font-weight:500}
.gatehelp .btn{text-decoration:none;display:inline-block}
.chip{display:inline-flex;align-items:center;gap:7px;font-size:12.5px;padding:5px 11px;border-radius:14px;
  background:rgba(255,255,255,.16);white-space:nowrap}
.gear{appearance:none;border:0;background:none;color:inherit;cursor:pointer;padding:8px;border-radius:50%;
  line-height:1;display:inline-flex;opacity:.9}
.gear .mi{font-size:20px}
.gear:hover{background:rgba(255,255,255,.16);opacity:1}
.gear:focus-visible{outline:2px solid currentColor;outline-offset:2px}
.dot{width:7px;height:7px;border-radius:50%;background:#9e9e9e;box-shadow:0 0 0 3px rgba(158,158,158,.3)}
.dot.ok{background:var(--ok);box-shadow:0 0 0 3px rgba(67,160,71,.3)}
.dot.warn{background:#ffa000;box-shadow:0 0 0 3px rgba(255,160,0,.3)}

.wrap{padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px));
  padding-block:20px 40px;max-width:1240px;margin:0 auto;
  display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1.15fr);gap:20px;align-items:start}
@media (max-width:960px){.wrap{grid-template-columns:minmax(0,1fr)}}
.card{background:var(--card);border-radius:12px;box-shadow:0 2px 2px rgba(0,0,0,.06),0 1px 5px rgba(0,0,0,.08);min-width:0}
.card-h{padding:16px 18px 0;display:flex;align-items:baseline;gap:10px;flex-wrap:wrap}
.card-h h2{font-size:16px}.card-h .sub{font-size:12.5px;color:var(--fg2)}
.card-b{padding:16px 18px 18px}
#configCard{background:none;box-shadow:none}
#configCard>.card-b{padding:0}

.tabs{display:flex;gap:2px;border-bottom:1px solid var(--divider);padding:0 10px 0 18px;overflow-x:auto;align-items:center}
.tab{appearance:none;border:0;background:none;color:var(--fg2);font:500 13px/1 var(--font);letter-spacing:.4px;
  text-transform:uppercase;padding:14px 13px 12px;border-bottom:2px solid transparent;cursor:pointer;white-space:nowrap}
.tab[aria-selected="true"]{color:var(--primary);border-bottom-color:var(--primary)}
.tab:focus-visible,.addp:focus-visible{outline:2px solid var(--primary);outline-offset:-2px}
.addp{appearance:none;border:0;background:none;color:var(--fg2);cursor:pointer;font-size:20px;padding:6px 10px;border-radius:50%}
.addp:hover{background:var(--hover);color:var(--fg)}

/* the tab row, with the screens scrolling and the preview button pinned right */
.tabrow{display:flex;align-items:stretch;border-bottom:1px solid var(--divider)}
.tabrow .tabs{flex:1;min-width:0;border-bottom:0}
.livebtn{appearance:none;border:0;background:none;color:var(--fg2);cursor:pointer;flex:none;
  font:500 13px/1 var(--font);letter-spacing:.4px;text-transform:uppercase;white-space:nowrap;
  display:inline-flex;align-items:center;gap:7px;padding:0 18px 0 14px;margin:0;border-radius:0}
.livebtn .mi{font-size:17px}
.livebtn:hover{color:var(--fg);background:var(--hover)}
.livebtn[aria-pressed="true"]{color:var(--primary)}
.livebtn:focus-visible{outline:2px solid var(--primary);outline-offset:-2px}
/* in preview mode the deck is live: no selection ring, no menus, nothing to drag */
.screen.live .key{cursor:pointer}
.screen.live .kdots{display:none}
.screen.live .key[aria-pressed="true"]{box-shadow:inset 0 1px 0 rgba(255,255,255,.07)}
.screen.live .key.down{filter:brightness(1.22)}
.livenote{font:400 12.5px var(--font);color:var(--fg2);padding:8px 18px 0;margin:0}

.deck-stage{display:flex;justify-content:center;padding:6px 0 2px}
.deck{position:relative;background:var(--deck-shell);border-radius:16px;padding:14px;width:100%;max-width:580px;
  box-shadow:inset 0 1px 0 rgba(255,255,255,.08),0 10px 24px rgba(0,0,0,.3)}
.screen{background:var(--deck-face);border-radius:8px;padding:9px;display:grid;grid-template-columns:repeat(5,1fr);gap:9px;
  container-type:inline-size}
/* Everything inside a key is sized as a fraction of the key's own width, --k, so
   the preview keeps its proportions at any window size and the deck renderer can
   use the same numbers (render.py draws a key 200 px wide: these fractions x 200).
   The reference: on a key 100 wide, an icon is 54 and a label is 14. */
.key{--k:calc((100cqw - 36px)/5);
  position:relative;aspect-ratio:16/15;border:0;border-radius:7px;cursor:pointer;padding:calc(var(--k)*.06) calc(var(--k)*.04) calc(var(--k)*.05);
  display:flex;flex-direction:column;align-items:center;justify-content:center;gap:calc(var(--k)*.03);
  background:var(--keybg);color:#3a3a3a;font-family:var(--font);
  box-shadow:inset 0 1px 0 rgba(255,255,255,.07);transition:transform .08s ease,box-shadow .12s ease}
.key:hover{transform:translateY(-1px)}.key:active{transform:translateY(1px)}
.key:focus-visible{outline:2px solid var(--primary);outline-offset:2px}
.key[aria-pressed="true"]{box-shadow:inset 0 1px 0 rgba(255,255,255,.07),0 0 0 2px var(--primary),0 0 0 5px rgba(3,169,244,.28)}
.key .mi{font-size:calc(var(--k)*.54)}
.key:not(.ent):not(.h)>.mi{margin-bottom:calc(var(--k)*.03)}
.key.nav{background:var(--keybg)}
.key .kl{font-size:calc(var(--k)*.14);line-height:1.15;font-weight:500;text-align:center;max-width:100%;
  overflow:hidden;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;word-break:break-word}
.key .empty{font-size:calc(var(--k)*.2);font-weight:300;color:#43484f}

.field{margin-top:16px}.field:first-child{margin-top:0}
.lab{display:block;font-size:12px;font-weight:500;color:var(--fg2);letter-spacing:.3px;margin-bottom:6px}
input[type=text]{width:100%;font:400 14px var(--font);color:var(--fg);background:var(--sunk);
  border:1px solid var(--divider);border-radius:6px;padding:10px 11px}
input[type=text]:focus{outline:none;border-color:var(--primary);box-shadow:0 0 0 2px rgba(3,169,244,.22)}

/* HA-style combo box */
.combo{position:relative}
.combo .box{display:flex;align-items:center;gap:9px;background:var(--sunk);border:1px solid var(--divider);
  border-radius:6px;padding:0 6px 0 11px}
.combo .box:focus-within{border-color:var(--primary);box-shadow:0 0 0 2px rgba(3,169,244,.22)}
.combo .box input{flex:1;min-width:0;border:0;background:none;outline:none;color:var(--fg);
  font:400 14px var(--font);padding:10px 0}
.combo .lead{font-size:21px;color:var(--fg2);flex:none}
.combo .ctl{appearance:none;border:0;background:none;color:var(--fg2);cursor:pointer;padding:5px;border-radius:50%;
  font-size:17px;line-height:1;flex:none}
.combo .ctl:hover{background:var(--hover);color:var(--fg)}
.pop{position:absolute;left:0;right:0;top:calc(100% + 4px);z-index:30;background:var(--card);
  border:1px solid var(--divider);border-radius:6px;box-shadow:0 6px 20px rgba(0,0,0,.22);
  max-height:290px;overflow-y:auto;padding:4px}
.opt{display:flex;align-items:center;gap:11px;padding:8px 10px;border-radius:5px;cursor:pointer}
.opt:hover,.opt.hi{background:var(--hover)}
.opt .mi{font-size:22px;color:var(--fg2);flex:none;width:24px;text-align:center}
.opt .txt{min-width:0;flex:1}
.opt .p{font-size:14px;color:var(--fg);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.opt .s{font-size:11.5px;color:var(--fg2);font-family:var(--mono);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.opt .st{font-size:11px;color:var(--fg2);flex:none;text-transform:uppercase;letter-spacing:.3px}
.pop .none{padding:16px 10px;color:var(--fg2);font-size:13px;text-align:center}
.pop .grp{padding:9px 10px 4px;font-size:11px;font-weight:500;letter-spacing:.5px;text-transform:uppercase;color:var(--fg2)}

.swatches{display:flex;gap:8px;flex-wrap:wrap}
.swatches.locked{opacity:.4;pointer-events:none}
/* Foreground and background as two overlapping squares, the way paint programs
   show them: the front one is the icon and text, the back one the key behind
   them. The one with the ring is the one the swatches will set. */
.colourrow{display:flex;align-items:center;gap:18px;flex-wrap:wrap}
.colourrow .swatches{flex:1;min-width:0}
.fgbg{position:relative;width:48px;height:48px;flex:none}
.fgbg .sq{position:absolute;width:31px;height:31px;border-radius:7px;padding:0;cursor:pointer;
  border:2px solid var(--card);box-shadow:0 0 0 1px rgba(127,127,127,.6)}
.fgbg .fgsq{left:0;top:0;z-index:2}
.fgbg .bgsq{right:0;bottom:0;z-index:1}
.fgbg .sq[aria-pressed="true"]{box-shadow:0 0 0 2px var(--primary),0 0 0 5px rgba(3,169,244,.28)}
.fgbg .sq:focus-visible{outline:2px solid var(--primary);outline-offset:3px}
.sw{width:30px;height:30px;border-radius:50%;border:2px solid transparent;cursor:pointer;padding:0;
  box-shadow:inset 0 0 0 1px rgba(0,0,0,.18)}
.sw[aria-pressed="true"]{border-color:var(--fg);box-shadow:inset 0 0 0 1px rgba(0,0,0,.18),0 0 0 2px var(--card)}
.sw:focus-visible{outline:2px solid var(--primary);outline-offset:2px}
.hint{font-size:12px;color:var(--fg2);margin-top:6px}
.hint:empty{display:none}
.hint code{font-family:var(--mono);font-size:11.5px;background:var(--sunk);padding:1px 5px;border-radius:3px}
.row{display:flex;gap:10px;margin-top:20px;flex-wrap:wrap}
.btn{appearance:none;border:0;border-radius:6px;font:500 13.5px var(--font);letter-spacing:.4px;text-transform:uppercase;
  padding:11px 18px;cursor:pointer;background:var(--primary);color:#fff}
.btn.ghost{background:none;color:var(--primary);box-shadow:inset 0 0 0 1px var(--divider)}
.btn:focus-visible{outline:2px solid var(--primary);outline-offset:2px}
.none{color:var(--fg2);font-size:13.5px;padding:26px 0;text-align:center}
.toolbar{display:flex;align-items:center;gap:10px;flex-wrap:wrap;padding:12px 18px 0}
.toolbar .lab{flex:none}
.toolbar input{flex:1;min-width:120px;max-width:260px}
.btn.danger{background:none;color:#e53935;box-shadow:inset 0 0 0 1px rgba(229,57,53,.45);
  display:inline-flex;align-items:center;gap:6px;padding:9px 14px}
.btn.danger:hover{background:rgba(229,57,53,.1)}
.btn.danger .mi{font-size:17px}
.key.wide{grid-column:span 2;aspect-ratio:32/15}
.key.ent{background:var(--keybg)}
.key .val{font:500 calc(var(--k)*.28)/1 var(--font);font-variant-numeric:tabular-nums;letter-spacing:-.4px}
.key .clock{font:500 calc(var(--k)*.34)/1 var(--font);font-variant-numeric:tabular-nums;letter-spacing:-.5px}
.key .clockdate{font-size:calc(var(--k)*.14);font-weight:400;opacity:.75;margin-top:calc(var(--k)*.03)}
.key .clock.long{font-size:calc(var(--k)*.22)}
.key.wide .clock{font-size:calc(var(--k)*.53)}
.key.wide .clock.long{font-size:calc(var(--k)*.46)}
.key .val u{font-size:calc(var(--k)*.16);font-weight:400;text-decoration:none;opacity:.75;margin-left:1px}
.key.ent .mi{font-size:calc(var(--k)*.29);opacity:.85}
.range2{display:flex;gap:10px}
.range2 label{flex:1;min-width:0}
.key{cursor:pointer;touch-action:none}
.screen{user-select:none;-webkit-user-select:none}
/* the cursor is ours throughout the drag, including over the children */
.screen.dragging,.screen.dragging *{cursor:move!important}
:host(.dragging-keys),:host(.dragging-keys) *{cursor:move!important}
.key.dragging{opacity:.35;cursor:move}
.key.over{box-shadow:inset 0 1px 0 rgba(255,255,255,.07),0 0 0 2px #8bc34a,0 0 0 6px rgba(139,195,74,.3)}
.key .bar{width:82%;height:calc(var(--k)*.08);border-radius:calc(var(--k)*.04);background:var(--track);overflow:hidden;flex:none}
.key .bar i{display:block;height:100%;border-radius:calc(var(--k)*.04);background:currentColor}
/* stacked, a bar takes the room a graph would (.32k high, 84% wide), so the two
   kinds of key put their reading and name in the same places */
.key>.bar{width:84%;margin:calc(var(--k)*.12) 0}
/* with no name under it the reading stands a little further off the bar or graph,
   rather than crowding up against it with empty key below */
.key.noname>.bar{margin-bottom:calc(var(--k)*.18)}
.key.noname>svg.sp{margin-bottom:calc(var(--k)*.06)}
.key svg.g{width:calc(var(--k)*.40);height:auto;flex:none;overflow:visible}
.key .gv{position:relative;width:calc(var(--k)*.60);aspect-ratio:1;flex:none}
.key .gv.solo{width:calc(var(--k)*.75)}
.key .gv svg.g{width:100%;height:100%;display:block}
.key .gvv{position:absolute;left:0;right:0;top:47%;transform:translateY(-50%);text-align:center;
  font:500 calc(var(--k)*.215)/1 var(--font);font-variant-numeric:tabular-nums}
.key .gv.solo .gvv{font-size:calc(var(--k)*.27)}
.key .gvu{position:absolute;left:0;right:0;top:86%;transform:translateY(-50%);text-align:center;
  font:400 calc(var(--k)*.10)/1 var(--font);opacity:.75}
.key .gv.solo .gvu{font-size:calc(var(--k)*.125)}
.key svg.sp{width:84%;height:calc(var(--k)*.32);flex:none;overflow:visible}
.key .valsm{font:500 calc(var(--k)*.20)/1 var(--font);font-variant-numeric:tabular-nums}
.key .valsm u{font-size:calc(var(--k)*.13);font-weight:400;text-decoration:none;opacity:.75}
.screen{overflow:hidden}
.key{overflow:hidden}
/* Wide key: each element keeps its own width, and the leftover space is split into
   equal thirds — before the gauge, between the two, and after the text. */
.key.h{flex-direction:row;align-items:center;justify-content:space-evenly;gap:0;padding:calc(var(--k)*.05) 0}
.key.hr{flex-direction:row-reverse}
.key.h .art{flex:0 0 auto;display:flex;align-items:center;justify-content:center}
.key.h .kcol{flex:0 1 auto;min-width:0;display:flex;align-items:center;justify-content:center}
.key.h .art svg.g{width:calc(var(--k)*.58);height:auto}
.key.h .art svg.sp{width:calc(var(--k)*.90);height:calc(var(--k)*.40)}
.key.h .art .bar{width:calc(var(--k)*.64)}
.key.h .art .mi{font-size:calc(var(--k)*.58)}
.key.h .ktext{display:flex;flex-direction:column;align-items:flex-start;gap:2px;min-width:0}
.key.h .ktext .kl{text-align:left;-webkit-line-clamp:2}
.key.h .val{font-size:calc(var(--k)*.345)}
.sw.custom{position:relative;overflow:hidden;padding:0;border:2px solid var(--divider);
  background:var(--sunk)}
.sw.custom input{position:absolute;inset:-6px;width:calc(100% + 12px);height:calc(100% + 12px);
  opacity:0;cursor:pointer;border:0;padding:0}
.sw.custom span{position:absolute;inset:0;display:grid;place-items:center;font-size:18px;
  pointer-events:none}
.pencil{appearance:none;border:0;background:none;color:var(--fg2);cursor:pointer;padding:7px;
  border-radius:50%;line-height:1;display:inline-flex}
.pencil .mi{font-size:18px}
.pencil:hover{background:var(--hover);color:var(--primary)}
.pencil:focus-visible,.sw.custom:focus-within{outline:2px solid var(--primary);outline-offset:2px}
.dlgwrap{position:fixed;inset:0;z-index:60;background:rgba(0,0,0,.45);display:flex;
  align-items:center;justify-content:center;padding:max(16px,env(safe-area-inset-left,0px))}
.dlg{background:var(--card);color:var(--fg);border-radius:14px;width:min(460px,100%);
  box-shadow:0 12px 40px rgba(0,0,0,.4);display:flex;flex-direction:column;max-height:86vh}
.dlg h3{margin:0;font-size:19px;font-weight:400;padding:22px 24px 4px}
.dlgbody{padding:8px 24px 18px;overflow-y:auto}
.dlgfoot{display:flex;align-items:center;gap:10px;flex-wrap:wrap;padding:14px 18px 16px;
  border-top:1px solid var(--divider)}
.dlgspacer{flex:1}
.linkdanger{appearance:none;border:0;background:none;color:#e53935;font:500 13.5px var(--font);
  letter-spacing:.3px;cursor:pointer;padding:11px 10px;border-radius:6px}
.linkdanger:hover{background:rgba(229,57,53,.1)}
.linkdanger[disabled]{opacity:.4;cursor:not-allowed}
.linkdanger:focus-visible{outline:2px solid var(--primary);outline-offset:2px}
.sect{border:1px solid var(--divider);border-radius:8px;margin-bottom:12px;background:var(--card)}
.sect>summary{list-style:none;cursor:pointer;padding:14px 16px;font:500 14px var(--font);
  display:flex;align-items:center;gap:9px}
.sect>summary::-webkit-details-marker{display:none}
.sect>summary::after{content:"";margin-left:auto;width:8px;height:8px;border-right:2px solid var(--fg2);
  border-bottom:2px solid var(--fg2);transform:rotate(45deg) translateY(-2px);transition:transform .15s}
.sect[open]>summary::after{transform:rotate(-135deg) translateY(-2px)}
.sect>summary:focus-visible{outline:2px solid var(--primary);outline-offset:-2px;border-radius:8px}
.sectb{display:flex;flex-direction:column;gap:16px;padding:14px 16px 16px;border-top:1px solid var(--divider)}
.sectb>*,.sectb .tf,.sectb .field{margin-top:0}
#buttonOnly,#clockOnly{display:flex;flex-direction:column;gap:16px}
.tabitem{display:inline-flex;align-items:center;flex:none}
.tabitem .tab{padding-right:4px}
.tabpencil{appearance:none;border:0;background:none;color:var(--fg2);cursor:pointer;
  padding:4px 6px 4px 2px;border-radius:50%;line-height:1;display:inline-flex;opacity:.55}
.tabpencil .mi{font-size:15px}
.tabitem:hover .tabpencil,.tabpencil:focus-visible{opacity:1;color:var(--primary)}
.tabpencil:focus-visible{outline:2px solid var(--primary);outline-offset:1px}
.btn.pub{padding:9px 16px;background:#fff;color:var(--primary)}
.btn.pub[disabled]{opacity:.5;cursor:default}
/* --- controls modelled on Home Assistant's card editor --- */
.tf{display:block;position:relative;margin-top:16px;background:var(--sunk);
  border-radius:6px 6px 0 0;border-bottom:1px solid var(--fg2);padding:7px 12px 6px}
.tf:focus-within{border-bottom:2px solid var(--primary);padding-bottom:5px}
.tfl{display:block;font-size:11.5px;color:var(--fg2);line-height:1.4}
.tf:focus-within .tfl{color:var(--primary)}
.tf input,.tf select{width:100%;border:0;background:none;outline:none;color:var(--fg);
  font:400 15px var(--font);padding:1px 0 2px;appearance:none}
.tf.sel{position:relative}
.tf.sel::after{content:"";position:absolute;right:12px;bottom:14px;width:7px;height:7px;
  border-right:2px solid var(--fg2);border-bottom:2px solid var(--fg2);
  transform:rotate(45deg);pointer-events:none}
.tf select{padding-right:22px;cursor:pointer}
.tf input::placeholder{color:var(--fg2);opacity:.7}
.tf input{padding-right:26px}
.tfx{position:absolute;right:6px;bottom:6px;appearance:none;border:0;background:none;
  color:var(--fg2);font-size:17px;line-height:1;padding:4px 6px;border-radius:50%;cursor:pointer}
.tfx:hover{background:var(--hover);color:var(--fg)}
.tfx:focus-visible{outline:2px solid var(--primary);outline-offset:1px}
.radios{display:flex;flex-direction:column;gap:2px}
.radio{display:flex;align-items:center;gap:11px;padding:7px 2px;cursor:pointer;font-size:15px}
.radio input{appearance:none;width:19px;height:19px;border:2px solid var(--fg2);border-radius:50%;
  margin:0;flex:none;position:relative;cursor:pointer}
.radio input:checked{border-color:var(--primary)}
.radio input:checked::after{content:"";position:absolute;inset:3px;border-radius:50%;background:var(--primary)}
.radio input:focus-visible{outline:2px solid var(--primary);outline-offset:2px}
.switchrow{display:flex;align-items:center;justify-content:space-between;gap:14px;padding:16px 0 0;font-size:15px;border-top:1px solid var(--divider);margin:0}
.switch{appearance:none;border:0;width:44px;height:24px;border-radius:12px;background:var(--divider);
  position:relative;cursor:pointer;flex:none;transition:background .15s}
.switch::after{content:"";position:absolute;top:3px;left:3px;width:18px;height:18px;border-radius:50%;
  background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.3);transition:transform .15s}
.switch[aria-checked="true"]{background:var(--primary)}
.switch[aria-checked="true"]::after{transform:translateX(20px)}
.switch:focus-visible{outline:2px solid var(--primary);outline-offset:2px}
.sectb .lab{margin-bottom:6px}
#targetField,#targetField2{margin-top:12px}  /* field -> sub-field */
.sublab{display:block;margin-bottom:6px}
.kdots{position:absolute;top:1px;right:1px;width:22px;height:22px;display:grid;place-items:center;
  font-family:"UlanziMDI";font-style:normal;font-weight:400;line-height:1;-webkit-font-smoothing:antialiased;
  color:rgba(255,255,255,.4);font-size:16px;max-height:none;border-radius:50%;opacity:0;transition:opacity .12s}
.key:hover .kdots,.key:focus-within .kdots{opacity:1}
.kdots:hover{color:#fff;background:rgba(255,255,255,.14)}
.kmenu{position:absolute;z-index:20;background:var(--card);border:1px solid var(--divider);
  border-radius:8px;box-shadow:0 8px 24px rgba(0,0,0,.35);padding:4px;min-width:150px}
.kmenu-item{display:flex;align-items:center;gap:10px;width:100%;appearance:none;border:0;background:none;
  color:var(--fg);font:400 14px var(--font);padding:9px 11px;border-radius:5px;cursor:pointer;text-align:left}
.kmenu-item:hover{background:var(--hover)}
.kmenu-item .mi{font-size:18px;color:var(--fg2)}
.kmenu-item.danger,.kmenu-item.danger .mi{color:#e53935}
.kmenu-item.danger:hover{background:rgba(229,57,53,.12)}
.kmenu-item.danger[data-armed="1"]{background:rgba(229,57,53,.14);font-weight:500}
.kmenu-item:focus-visible{outline:2px solid var(--primary);outline-offset:-2px}
@media (prefers-reduced-motion:reduce){*{transition:none!important}}
.loading{padding:48px 16px;text-align:center;color:var(--fg2)}
`;

const MARKUP=`
<div class="bar"><div class="bar-in">
  <button class="dots" id="menuBtn" title="Menu" aria-label="Menu" hidden><i></i><i></i><i></i></button>
  <h1>Ulanzi Deck</h1>
  <span class="chip"><span class="dot" id="chipDot"></span> <span id="chipText">Connecting…</span></span>
  <button class="gear" id="btn-settings" title="Deck settings" aria-label="Deck settings"><span class="mi"></span></button>
  <button class="btn pub" id="btn-allow" hidden>Allow</button>
  <button class="btn pub" id="btn-publish">Send to device</button>
</div></div>

<div class="wrap">
  <div class="card getapp" id="getApp" hidden>
    <div class="card-b">
      <h2>Connect a Mac</h2>
      <p>Your deck has no network of its own. It plugs into a Mac over USB, and a small
         companion app on that Mac carries it to Home Assistant.</p>
      <p>The app arrives knowing this server, so there is nothing to type and nothing to
         allow. Set it up once and your keys appear here.</p>
      <button class="btn" id="btn-getapp">Get the companion app</button>
      <p class="getapp-err" id="getAppErr" hidden></p>
      <div class="gatehelp" id="gateHelp" hidden>
        <h3>macOS will block it the first time</h3>
        <p>Open the zip and double-click <b>Ulanzi Deck</b>. macOS will say it cannot check the
           app: press <b>Done</b> — not Move to Bin.</p>
        <p>Then open Privacy &amp; Security, scroll to <b>Security</b>, and press
           <b>Open Anyway</b>. It asks once more: press <b>Open Anyway</b> again.</p>
        <a class="btn ghost" id="btn-privacy" href="x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension">Open Privacy &amp; Security</a>
      </div>
      <p class="getapp-note"><a href="https://github.com/sygad/ulanzi-d200-ha-deck#what-the-companion-app-is-before-you-run-it" target="_blank" rel="noreferrer">What it does, and what it never does</a></p>
    </div>
  </div>
  <div class="card" id="configCard">
    <div class="card-b">
      <div id="insp">
        <details class="sect" open><summary>Key</summary>
        <div class="sectb">
          <div class="field">
            <span class="lab">Key type</span>
            <div class="radios" id="f-type">
              <label class="radio"><input type="radio" name="ktype" value="button" checked><span>Button</span></label>
              <label class="radio"><input type="radio" name="ktype" value="entity"><span>Entity</span></label>
              <label class="radio"><input type="radio" name="ktype" value="clock"><span>Clock</span></label>
            </div>
            <p class="hint" id="typeHint">A button runs something when you press it.</p>
          </div>
          <label class="tf"><span class="tfl">Label</span>
            <input type="text" id="f-label" placeholder="Optional" maxlength="18">
            <button type="button" class="tfx" id="f-label-clear" title="Clear" hidden>&times;</button></label>
        </div></details>

        <details class="sect"><summary>What it does</summary>
        <div class="sectb">
          <div class="field" id="entityPick" hidden>
            <span class="lab">Entity</span>
            <div class="combo" id="c-entity">
              <div class="box"><span class="mi lead" data-lead></span>
                <input type="text" placeholder="Start typing&hellip;" autocomplete="off" role="combobox" aria-expanded="false" aria-label="Entity">
                <button class="ctl" data-clear title="Clear">&times;</button>
                <button class="ctl" data-toggle title="Show all">&#9662;</button></div>
            </div>
            <p class="hint" id="f-sensor"></p>
          </div>
          <div id="clockOnly" hidden>
            <label class="tf sel"><span class="tfl">Time format</span>
              <select id="f-clockfmt">
                <option value="24">24 hour &mdash; 18:42</option>
                <option value="12">12 hour &mdash; 6:42 pm</option>
              </select></label>
            <div class="switchrow"><span>Show seconds</span>
              <button class="switch" role="switch" aria-checked="false" data-sw="secs"></button></div>
            <div class="switchrow"><span>Show the date</span>
              <button class="switch" role="switch" aria-checked="false" data-sw="date"></button></div>
          </div>
          <div id="buttonOnly">
            <div class="field">
              <span class="lab">Tap behaviour</span>
              <div class="combo" id="c-action">
              <div class="box"><span class="mi lead" data-lead></span>
                <input type="text" placeholder="Search actions&hellip;" autocomplete="off" role="combobox" aria-expanded="false" aria-label="Tap behaviour">
                <button class="ctl" data-clear title="Clear">&times;</button>
                <button class="ctl" data-toggle title="Show all">&#9662;</button></div>
            </div>
              <div id="targetField">
                <span class="lab sublab" id="targetLab">Entity</span>
                <div class="combo" id="c-target">
              <div class="box"><span class="mi lead" data-lead></span>
                <input type="text" placeholder="Start typing&hellip;" autocomplete="off" role="combobox" aria-expanded="false" aria-label="Tap target">
                <button class="ctl" data-clear title="Clear">&times;</button>
                <button class="ctl" data-toggle title="Show all">&#9662;</button></div>
            </div>
                <p class="hint" id="f-state"></p>
              </div>
            </div>
            <div class="field">
              <span class="lab">Hold behaviour</span>
              <div class="combo" id="c-action2">
              <div class="box"><span class="mi lead" data-lead></span>
                <input type="text" placeholder="Search actions&hellip;" autocomplete="off" role="combobox" aria-expanded="false" aria-label="Hold behaviour">
                <button class="ctl" data-clear title="Clear">&times;</button>
                <button class="ctl" data-toggle title="Show all">&#9662;</button></div>
            </div>
              <div id="targetField2">
                <span class="lab sublab" id="targetLab2">Entity</span>
                <div class="combo" id="c-target2">
              <div class="box"><span class="mi lead" data-lead></span>
                <input type="text" placeholder="Start typing&hellip;" autocomplete="off" role="combobox" aria-expanded="false" aria-label="Hold target">
                <button class="ctl" data-clear title="Clear">&times;</button>
                <button class="ctl" data-toggle title="Show all">&#9662;</button></div>
            </div>
                <p class="hint" id="f-state2"></p>
              </div>
            </div>
          </div>
        </div></details>

        <details class="sect"><summary>Appearance</summary>
        <div class="sectb">
          <label class="tf sel" id="styleField"><span class="tfl">Display</span>
            <select id="f-style">
              <option value="icon">Icon</option>
              <option value="number">Number</option>
              <option value="bar">Bar</option>
              <option value="gauge">Gauge</option>
              <option value="graph">Graph</option>
            </select></label>
          <div id="iconField">
            <span class="lab">Icon</span>
            <div class="combo" id="c-icon">
              <div class="box"><span class="mi lead" data-lead></span>
                <input type="text" placeholder="Start typing&hellip;" autocomplete="off" role="combobox" aria-expanded="false" aria-label="Icon">
                <button class="ctl" data-clear title="Clear">&times;</button>
                <button class="ctl" data-toggle title="Show all">&#9662;</button></div>
            </div>
          </div>
          <div class="field">
            <span class="lab">Colour</span>
            <div class="colourrow">
              <div class="fgbg" role="group" aria-label="Which colour to set">
                <button class="sq bgsq" data-target="bg" title="Background" aria-label="Background colour"></button>
                <button class="sq fgsq" data-target="fg" title="Icon and text" aria-label="Icon and text colour"></button>
              </div>
              <div class="swatches" id="f-colors" role="group" aria-label="Colour"></div>
            </div>
            <p class="hint" id="colourHint" hidden>Colour by level is on, so this key takes its
              colour from the reading rather than from a fixed choice.</p>
          </div>
          <label class="tf sel" id="layoutField" hidden><span class="tfl">Arrangement</span>
            <select id="f-layout">
              <option value="v">Stacked</option>
              <option value="h">Graphic left</option>
              <option value="hr">Graphic right</option>
            </select></label>
          <div class="field" id="rangeField">
            <div class="range2">
              <label class="tf"><span class="tfl">Minimum value</span>
                <input type="text" id="f-min" inputmode="decimal"></label>
              <label class="tf"><span class="tfl">Maximum value</span>
                <input type="text" id="f-max" inputmode="decimal"></label>
            </div>
          </div>
          <div class="field" id="bandField" hidden>
            <span class="lab">Levels</span>
            <div class="range2">
              <label class="tf"><span class="tfl">Amber above</span>
                <input type="text" id="f-warn" inputmode="decimal"></label>
              <label class="tf"><span class="tfl">Red above</span>
                <input type="text" id="f-alert" inputmode="decimal"></label>
            </div>
            <p class="hint">Below the first the key is green, between them amber, above the second red.</p>
          </div>
          <div class="switchrow" id="sw-icon"><span>Show icon</span>
            <button class="switch" role="switch" aria-checked="true" data-sw="icon"></button></div>
          <div class="switchrow" id="sw-name"><span>Show name</span>
            <button class="switch" role="switch" aria-checked="false" data-sw="name"></button></div>
          <div class="switchrow" id="sw-band"><span>Colour by level</span>
            <button class="switch" role="switch" aria-checked="false" data-sw="band"></button></div>
        </div></details>
      </div>
    </div>
  </div>

  <div class="card" id="deckCard">
    <div class="tabrow">
      <div class="tabs" role="tablist" id="tabs"></div>
      <button class="livebtn" id="btn-live" aria-pressed="false"
        title="Try the keys here before sending them to the deck">
        <span class="mi"></span><span id="liveLabel">Preview</span></button>
    </div>
    <p class="livenote" id="liveNote" hidden>Preview is on: a key here really does what it says,
      using your unsent changes. The deck is not touched.</p>
    <div class="card-b">
      <div class="deck-stage"><div class="deck">
        <div class="screen" id="screen"></div>
        <div class="kmenu" id="keyMenu" hidden>
          <button class="kmenu-item danger" data-kmenu="delete">
            <span class="mi" data-ico></span><span data-text>Delete</span></button>
        </div>
      </div></div>
    </div>
  </div>

</div>

<div class="dlgwrap" id="setDlg" hidden>
  <div class="dlg" role="dialog" aria-modal="true" aria-labelledby="setTitle">
    <h3 id="setTitle">Deck settings</h3>
    <div class="dlgbody">
      <div class="field">
        <label class="tf sel"><span class="tfl">Turn the screen off after</span>
          <select id="set-sleep">
            <option value="0">Never</option>
            <option value="1">1 minute</option>
            <option value="2">2 minutes</option>
            <option value="5">5 minutes</option>
            <option value="10">10 minutes</option>
            <option value="15">15 minutes</option>
            <option value="20">20 minutes</option>
            <option value="30">30 minutes</option>
            <option value="45">45 minutes</option>
            <option value="60">1 hour</option>
            <option value="90">1 hour 30 minutes</option>
            <option value="120">2 hours</option>
            <option value="180">3 hours</option>
            <option value="240">4 hours</option>
          </select></label>
        <p class="hint">With nothing happening for this long the deck’s screen goes dark, to save it.
          Any key wakes it, and that first press does nothing else.</p>
      </div>
    </div>
    <div class="dlgfoot">
      <span class="dlgspacer"></span>
      <button class="btn ghost" id="set-cancel">Cancel</button>
      <button class="btn" id="set-save">Save</button>
    </div>
  </div>
</div>

<div class="dlgwrap" id="viewDlg" hidden>
  <div class="dlg" role="dialog" aria-modal="true" aria-labelledby="dlgTitle">
    <h3 id="dlgTitle">Edit screen</h3>
    <div class="dlgbody">
      <div class="field">
        <label class="lab" for="dlg-name">Name</label>
        <input type="text" id="dlg-name" maxlength="24" placeholder="Screen name">
      </div>
      <div class="field">
        <span class="lab">Icon shown on the screen&rsquo;s own key</span>
        <div class="combo" id="c-viewicon">
          <div class="box"><span class="mi lead" data-lead></span>
            <input type="text" placeholder="Start typing&hellip;" autocomplete="off" role="combobox" aria-expanded="false" aria-label="Screen icon">
            <button class="ctl" data-clear title="Clear">&times;</button>
            <button class="ctl" data-toggle title="Show all">&#9662;</button></div>
        </div>
      </div>
    </div>
    <div class="dlgfoot">
      <button class="linkdanger" id="dlg-del">Delete screen</button>
      <span class="dlgspacer"></span>
      <button class="btn ghost" id="dlg-cancel">Cancel</button>
      <button class="btn" id="dlg-save">Save</button>
    </div>
  </div>
</div>

`;

function build(host,init){
const root=host.shadowRoot;
const ch=cp=>String.fromCodePoint(parseInt(cp,16));
const ico=n=>ICONS[n]?ch(ICONS[n]):"";
const ICON_NAMES=Object.keys(ICONS);
const COLORS=["#ffffff","#000000","#03a9f4","#ffc107","#8bc34a","#ff7043","#ba68c8","#4dd0e1","#f06292"];
// a key with no background of its own is drawn on this (BACKGROUND in render.py, --keybg here)
// a key with no background of its own is black (BACKGROUND in render.py)
const KEYBG="#000000";
const bgOf=k=>(k&&k.bg)||KEYBG;
// how a key's background is painted in the preview: black a shade lifted, so the key shows
const paintBg=k=>bgOf(k)===KEYBG?"var(--keybg)":bgOf(k);
let target="fg";    // which of a key's two colours the swatches set: "fg" icon and text, "bg" the key behind them
// the unfilled part of a bar or dial: a step darker than a light key, lighter than a dark one
// (track_for in render.py does the same sum)
const trackOf=bg=>{const n=parseInt(bg.slice(1),16),c=[n>>16,n>>8&255,n&255];
  const light=.299*c[0]+.587*c[1]+.114*c[2]>90;
  return "rgb("+c.map(v=>light?Math.round(v*.78):Math.round(v+(255-v)*.17)).join(",")+")"};
const DOMICON={light:"lightbulb",cover:"window-shutter",media_player:"speaker",script:"script-text",
  scene:"palette",switch:"toggle-switch-variant",fan:"fan",sensor:"gauge"};
const WIDE=13, NKEYS=14;   // bottom-right key spans two columns

const ACTIONS=[
 {g:"Lights",id:"light.toggle",label:"Light: Toggle",dom:["light"],icon:"lightbulb"},
 {g:"Lights",id:"light.turn_on",label:"Light: Turn on",dom:["light"],icon:"lightbulb-on"},
 {g:"Lights",id:"light.turn_off",label:"Light: Turn off",dom:["light"],icon:"lightbulb-off"},
 {g:"Switches",id:"switch.toggle",label:"Switch: Toggle",dom:["switch"],icon:"toggle-switch-outline"},
 {g:"Switches",id:"switch.turn_on",label:"Switch: Turn on",dom:["switch"],icon:"toggle-switch"},
 {g:"Switches",id:"switch.turn_off",label:"Switch: Turn off",dom:["switch"],icon:"toggle-switch-off"},
 {g:"Buttons",id:"button.press",label:"Button: Press",dom:["button"],icon:"gesture-tap-button"},
 {g:"Covers",id:"cover.toggle",label:"Cover: Toggle",dom:["cover"],icon:"window-shutter-auto"},
 {g:"Covers",id:"cover.open_cover",label:"Cover: Open",dom:["cover"],icon:"window-shutter-open"},
 {g:"Covers",id:"cover.close_cover",label:"Cover: Close",dom:["cover"],icon:"window-shutter"},
 {g:"Media",id:"media_player.media_play_pause",label:"Media player: Play / pause",dom:["media_player"],icon:"play-pause"},
 {g:"Media",id:"media_player.volume_up",label:"Media player: Volume up",dom:["media_player"],icon:"volume-plus"},
 {g:"Media",id:"media_player.volume_down",label:"Media player: Volume down",dom:["media_player"],icon:"volume-minus"},
 {g:"Scripts and scenes",id:"script.turn_on",label:"Script: Run",dom:["script"],icon:"script-text-play"},
 {g:"Scripts and scenes",id:"scene.turn_on",label:"Scene: Activate",dom:["scene"],icon:"palette"},
 {g:"Screens",id:"deck.previous_page",label:"Deck: Previous screen",nav:1,icon:"chevron-left"},
 {g:"Screens",id:"deck.next_page",label:"Deck: Next screen",nav:1,icon:"chevron-right"},
 {g:"Screens",id:"deck.go_to_page",label:"Deck: Go to screen\u2026",page:1,icon:"view-grid"},
 {g:"Screens",id:"deck.back",label:"Deck: Back",nav:1,icon:"arrow-u-left-top"},
 {g:"Other",id:"none",label:"Nothing",icon:"minus-circle-outline"}
];
const ACT=id=>ACTIONS.find(a=>a.id===id)||ACTIONS[ACTIONS.length-1];
/* ---------- Home Assistant's entities, in the shape the pickers want ---------- */
const hass=()=>host._hass;
const domainOf=id=>id.split(".")[0];
const nameOf=st=>st.attributes.friendly_name||st.entity_id;
function areaOf(id){
  const h=hass(), e=h.entities&&h.entities[id];
  let a=e&&e.area_id;
  if(!a&&e&&e.device_id&&h.devices&&h.devices[e.device_id])a=h.devices[e.device_id].area_id;
  return a&&h.areas&&h.areas[a]?h.areas[a].name:"";
}
const CLASSICON={temperature:"thermometer",humidity:"water-percent",power:"flash",energy:"lightning-bolt",
  carbon_dioxide:"molecule-co2",illuminance:"brightness-5",battery:"battery",pressure:"gauge",pm25:"air-filter",
  pm10:"air-filter",voltage:"sine-wave",current:"current-ac",signal_strength:"wifi",moisture:"water",
  gas:"meter-gas",distance:"ruler",duration:"timer-outline",motion:"motion-sensor",door:"door",window:"window-closed"};
function iconOf(st){
  const i=st.attributes.icon;
  if(i&&i.startsWith("mdi:")&&ICONS[i.slice(4)])return i.slice(4);
  return CLASSICON[st.attributes.device_class]||DOMICON[domainOf(st.entity_id)]||"gauge";
}
// round the way the deck will, so the preview and the deck agree
function shown(st){
  const raw=st.state, v=Number(raw);
  if(raw===""||isNaN(v))return raw==="unavailable"||raw==="unknown"?"--":raw;
  const e=hass().entities&&hass().entities[st.entity_id];
  let p=e&&e.display_precision;
  if(p===undefined||p===null){
    if(!raw.includes("."))return raw;
    p=Math.min(raw.split(".")[1].length,Math.abs(v)<10?2:Math.abs(v)<1000?1:0);
  }
  return v.toFixed(p);
}
const entRow=st=>[st.entity_id,nameOf(st),areaOf(st.entity_id),st.state];
const senRow=st=>[st.entity_id,nameOf(st),areaOf(st.entity_id),shown(st),st.attributes.unit_of_measurement||"",iconOf(st)];
const ENT=id=>{const st=id&&hass().states[id];return st?entRow(st):undefined};
const SEN=id=>{const st=id&&hass().states[id];return st?senRow(st):undefined};
const ACTION_DOMS=new Set(ACTIONS.flatMap(a=>a.dom||[]));
const byName=(a,b)=>a[1].localeCompare(b[1]);
const ENTS=()=>Object.values(hass().states).filter(st=>ACTION_DOMS.has(domainOf(st.entity_id))).map(entRow).sort(byName);
// sensors first: they are what an entity key is nearly always for
const SENSORS=()=>{const all=Object.values(hass().states).map(senRow).sort(byName);
  return all.filter(e=>domainOf(e[0])==="sensor").concat(all.filter(e=>domainOf(e[0])!=="sensor"))};

/* ---------- a day of history for graph keys, fetched once and kept five minutes ---------- */
const HIST={}, histAt={};
function needHist(ent){
  if(!ent)return;
  const now=Date.now();
  if(histAt[ent]&&now-histAt[ent]<300000)return;
  histAt[ent]=now;
  const start=now-24*3600e3;
  hass().callWS({type:"history/history_during_period",start_time:new Date(start).toISOString(),
    entity_ids:[ent],minimal_response:true,no_attributes:true,significant_changes_only:false}).then(r=>{
    const rows=((r&&r[ent])||[]).map(x=>[(x.lu||x.lc||0)*1000,parseFloat(x.s)]).filter(x=>!isNaN(x[1]));
    const out=[];let i=0,last=null;
    for(let h=1;h<=24;h++){const edge=start+h*3600e3;
      while(i<rows.length&&rows[i][0]<=edge){last=rows[i][1];i++}
      if(last!==null)out.push(last)}
    HIST[ent]=out; paintDeck();
  }).catch(()=>{});
}

const RANGES={"ppm":[400,2000],"\u00b0C":[0,30],"%":[0,100],"W":[0,500],"kWh":[0,1000],
  "lx":[0,1000],"\u00b5g/m\u00b3":[0,50],"m":[0,6]};
const rangeFor=ent=>{const e=SEN(ent);return (e&&RANGES[e[4]])||[0,100]};
const levelsFor=(lo,hi)=>({warn:+(lo+(hi-lo)*0.5).toFixed(2), alert:+(lo+(hi-lo)*0.75).toFixed(2)});
const pages=init.pages;
// the deck's own settings, as against any one screen's
const SET_DEFAULTS={sleep:20};
const settings=Object.assign({},SET_DEFAULTS,init.settings||{});
let pi=0, sel=null;
const $=s=>root.querySelector(s);
const cur=()=>sel===null?null:pages[pi].keys[sel];
const CLOCK_DEFAULTS={fmt:"24",secs:false,date:false};
const BLANK=()=>({type:"button",l:"",i:"",c:"#ffffff",layout:"v",
  tap:{a:"none",t:""},hold:{a:"none",t:""}});
let blankView=null;                       // what the panel shows for an empty slot
const view=()=>cur()||blankView;          // read from this
function ensureKey(){                     // write through this: it creates the key
  if(sel===null)return null;
  if(!pages[pi].keys[sel]){pages[pi].keys[sel]=blankView||BLANK();blankView=null}
  return pages[pi].keys[sel];
}
const slotOf=w=>{const k=view();return k&&k.type==="button"?k[w]:null};
const slotRW=w=>{const k=ensureKey();return k&&k.type==="button"?k[w]:null};
const esc=s=>String(s).replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));

/* ---------- combo box ---------- */
function Combo(root,cfg){
  const box=root.querySelector(".box"), input=root.querySelector("input"),
        lead=root.querySelector("[data-lead]"), pop=document.createElement("div");
  pop.className="pop"; pop.hidden=true; root.appendChild(pop);
  let items=[], hi=-1, open=false, typed=false;
  function render(){
    if(!items.length){pop.innerHTML='<div class="none">No matches</div>';return}
    let out="",last=null;
    items.forEach((it,n)=>{
      if(cfg.group){const g=cfg.group(it); if(g&&g!==last){out+=`<div class="grp">${esc(g)}</div>`;last=g}}
      out+=cfg.row(it,n===hi,n);
    });
    pop.innerHTML=out;
  }
  function show(){open=true;pop.hidden=false;input.setAttribute("aria-expanded","true")}
  function hide(){open=false;pop.hidden=true;hi=-1;input.setAttribute("aria-expanded","false")}
  function filter(q){items=cfg.find(q).slice(0,cfg.max||60);hi=items.length?0:-1;render()}
  input.addEventListener("focus",()=>{typed=false;filter("");show()});
  input.addEventListener("input",()=>{typed=true;filter(input.value.trim());show()});
  input.addEventListener("keydown",e=>{
    if(e.key==="ArrowDown"||e.key==="ArrowUp"){e.preventDefault();
      if(!open){filter(typed?input.value.trim():"");show()}
      hi=Math.max(0,Math.min(items.length-1,hi+(e.key==="ArrowDown"?1:-1)));render();
      const el=pop.querySelector(`[data-n="${hi}"]`);if(el&&el.scrollIntoView)el.scrollIntoView({block:"nearest"});return}
    if(e.key==="Enter"&&open&&hi>=0){e.preventDefault();pick(items[hi]);return}
    if(e.key==="Escape"){hide();input.blur()}});
  input.addEventListener("blur",()=>setTimeout(()=>{hide();sync()},140));
  pop.addEventListener("mousedown",e=>{const r=e.target.closest("[data-n]");if(!r)return;
    e.preventDefault();pick(items[+r.dataset.n])});
  box.querySelector("[data-clear]").addEventListener("mousedown",e=>{e.preventDefault();cfg.onPick("");sync()});
  box.querySelector("[data-toggle]").addEventListener("mousedown",e=>{e.preventDefault();
    open?hide():input.focus()});
  function pick(it){cfg.onPick(cfg.value(it));hide();sync();input.blur()}
  function sync(){const v=cfg.get();input.value=v?cfg.label(v):"";lead.textContent=cfg.lead?cfg.lead(v):""}
  return {sync};
}
const optRow=(i,hiOn,glyph,primary,secondary,tail)=>
  `<div class="opt${hiOn?" hi":""}" data-n="${i}"><span class="mi">${glyph}</span><span class="txt">
   <span class="p">${esc(primary)}</span>${secondary?`<span class="s">${esc(secondary)}</span>`:""}</span>
   ${tail?`<span class="st">${esc(tail)}</span>`:""}</div>`;

/* ---------- matching, the way Home Assistant's own pickers do it ----------
   The query is split into words. Every word has to appear somewhere in the
   item — in any order, in any of its fields — so "lounge wall" finds
   "Counter" in the Kitchen, and "light.kitchen" or "kitchen counter" work too. */
const words=q=>q.toLowerCase().split(/[\s_.:\-]+/).filter(Boolean);
const hit=(ws,fields)=>{const all=fields.map(f=>(f||"").toLowerCase()).join(" ");return ws.every(w=>all.includes(w))};
// best first: every word is in the name itself rather than only in the area or
// the entity id, and within that, names that start with what was typed
function rank(q,items,fieldsOf){
  const ws=words(q); if(!ws.length)return items;
  const out=[];
  for(const it of items){
    const f=fieldsOf(it); if(!hit(ws,f))continue;
    const name=(f[0]||"").toLowerCase();
    out.push([(hit(ws,[name])?0:2)+(name.startsWith(ws[0])?0:1),it]);
  }
  return out.sort((a,b)=>a[0]-b[0]).map(x=>x[1]);
}

/* ---------- pickers ---------- */
const iconCombo=new Combo($("#c-icon"),{max:80,
  find:q=>rank(q,ICON_NAMES,n=>[n,ALIAS[n]]),
  row:(n,h,i)=>optRow(i,h,ico(n),n,"mdi:"+n),
  value:n=>n,label:n=>n,lead:n=>n?ico(n):"",
  get:()=>{const k=view();return k?k.i:""},
  onPick:v=>{const k=ensureKey();if(!k)return;k.i=v||"";drawDeck()}});

function actionPair(w,actId,tgtId,fieldId,stateId,labId){
  const A=new Combo($(actId),{max:30,
    find:q=>{const ws=words(q);return ACTIONS.filter(a=>hit(ws,[a.label,a.id,a.g]))},   // kept in group order
    group:a=>a.g,
    row:(a,h,i)=>optRow(i,h,ico(a.icon),a.label,a.id==="none"?"":a.id),
    value:a=>a.id,label:id=>ACT(id).label,lead:id=>id?ico(ACT(id).icon):"",
    get:()=>{const a=slotOf(w);return a?a.a:""},
    onPick:v=>{const a=slotRW(w);if(!a)return;a.a=v||"none";a.t="";refresh();drawDeck()}});
  const T=new Combo($(tgtId),{max:60,
    find:q=>{const a=slotOf(w);if(!a)return[];
      const d=ACT(a.a);
      if(d.page)return rank(q,pages.map((p,n)=>({page:n,name:p.name})),x=>[x.name,"screen "+(x.page+1)]);
      const doms=d.dom;
      return rank(q,ENTS().filter(e=>!doms||doms.includes(e[0].split(".")[0])),e=>[e[1],e[2],e[0]])},
    row:(it,h,i)=>{
      if(it.page!==undefined)return optRow(i,h,ico("view-grid"),"Screen "+(it.page+1)+" \u2014 "+it.name,"");
      const dom=it[0].split(".")[0];
      return optRow(i,h,ico(DOMICON[dom]||"shape"),it[1],(it[2]?it[2]+" \u00b7 ":"")+it[0],
        ["on","off","open","closed","idle","unavailable"].includes(it[3])?it[3]:"")},
    value:it=>it.page!==undefined?String(it.page):it[0],
    label:v=>{const a=slotOf(w);if(a&&ACT(a.a).page){const p=pages[+v];return p?"Screen "+(+v+1)+" \u2014 "+p.name:v}
      const e=ENT(v);return e?e[1]+(e[2]?" ("+e[2]+")":""):v},
    lead:v=>{const a=slotOf(w);if(!v)return"";if(a&&ACT(a.a).page)return ico("view-grid");
      const e=ENT(v);return e?ico(DOMICON[e[0].split(".")[0]]||"shape"):""},
    get:()=>{const a=slotOf(w);return a?a.t:""},
    onPick:v=>{const a=slotRW(w);if(!a)return;a.t=v;refresh();drawDeck()}});
  function refresh(){
    const a=slotOf(w); if(!a)return;
    const d=ACT(a.a);
    $(fieldId).hidden=(d.id==="none"||!!d.nav);
    $(labId).textContent=d.page?"Screen":"Entity";
    T.sync();
    const e=ENT(a.t);
    $(stateId).innerHTML=e?`<code>${esc(e[0])}</code> &middot; currently <b>${esc(e[3])}</b>`:"";
  }
  return {sync:()=>{A.sync();refresh()}, refresh};
}
const tapPair=actionPair("tap","#c-action","#c-target","#targetField","#f-state","#targetLab");
const holdPair=actionPair("hold","#c-action2","#c-target2","#targetField2","#f-state2","#targetLab2");
function refreshTargets(){tapPair.refresh();holdPair.refresh()}

const entityCombo=new Combo($("#c-entity"),{max:60,
  find:q=>rank(q,SENSORS(),e=>[e[1],e[2],e[0]]),
  row:(e,h,i)=>optRow(i,h,ico(e[5]),e[1],(e[2]?e[2]+" · ":"")+e[0],e[3]+" "+e[4]),
  value:e=>e[0],
  label:v=>{const e=SEN(v);return e?e[1]+(e[2]?" ("+e[2]+")":""):v},
  lead:v=>{const e=SEN(v);return e?ico(e[5]):""},
  get:()=>{const k=view();return k&&k.type==="entity"?k.ent:""},
  onPick:v=>{const k=ensureKey();if(!k)return;k.ent=v;const e=SEN(v);
    if(e&&k.i)k.i=e[5];                      // a deliberately blank icon stays blank
    const r=rangeFor(v);k.min=r[0];k.max=r[1];
    const lv=levelsFor(k.min,k.max);k.warn=lv.warn;k.alert=lv.alert;
    $("#f-min").value=k.min;$("#f-max").value=k.max;
    $("#f-warn").value=k.warn;$("#f-alert").value=k.alert;
    iconCombo.sync();refreshSensor();drawDeck()}});

/* ---------- drawing ---------- */
function drawTabs(){
  $("#tabs").innerHTML=pages.map((p,n)=>
    `<span class="tabitem"><button class="tab" role="tab" aria-selected="${n===pi}" data-p="${n}">${esc(p.name)}</button>`
    +`<button class="tabpencil" data-editp="${n}" title="Edit ${esc(p.name)}"><span class="mi">${ico("pencil")}</span></button></span>`).join("")
    +`<button class="addp" data-addp title="Add a screen">+</button>`;
}
const sideBySide=(art,text)=>
  `<span class="art">${art}</span><span class="kcol"><span class="ktext">${text}</span></span>`;
// every key type lays out the same way: graphic beside the text, or above it,
// and a blank graphic takes no room at all
const tileBody=(art,text,horiz)=>horiz
  ? (art?sideBySide(art,text):`<span class="kcol"><span class="ktext">${text}</span></span>`)
  : `${art}${text}`;
const showsIcon=k=>k.showIcon!==false;          // absent means yes
const glyphOf=k=>(k.i&&showsIcon(k))?`<span class="mi">${ico(k.i)}</span>`:"";
// the graphic a key draws beside or above its text, if it draws one at all
function artOf(k,frac){
  if(k.type!=="entity")return glyphOf(k);
  if(k.style==="bar")return `<span class="bar"><i style="width:${((frac||0)*100).toFixed(1)}%"></i></span>`;
  if(k.style==="gauge")return dial(frac||0);
  if(k.style==="graph")return (needHist(k.ent),HIST[k.ent])?spark(k.ent):"";
  if(k.style==="icon")return glyphOf(k);
  return "";                                    // number: the value stands alone
}
const hasArt=k=>artOf(k,0)!=="";
const horizClass=(k,n)=>n!==WIDE?"":(k.layout==="h"?" h":k.layout==="hr"?" h hr":"");
function entityBody(k,e,frac,name,horiz){
  const u=e?e[4]:"";
  if(k.style==="gauge"&&!horiz){
    // stacked: the reading sits inside the dial and the unit in the gap at its foot,
    // which lets the dial be half as big again (the deck draws it the same way)
    const art=`<span class="gv${name?"":" solo"}">${dial(frac)}<span class="gvv">${e?esc(e[3]):"--"}</span>`
      +`<span class="gvu">${esc(u)}</span></span>`;
    return tileBody(art,name,false);
  }
  const art=artOf(k,frac);
  // a graphic above the value leaves less room, so the value is set smaller there
  const big=horiz||k.style==="icon"||k.style==="number"||!art;
  const text=`<span class="${big?"val":"valsm"}">${e?esc(e[3]):"--"}<u>${esc(u)}</u></span>${name}`;
  return tileBody(art,text,horiz);
}
function clockText(k){
  const d=new Date(), p=n=>String(n).padStart(2,"0");
  let h=d.getHours(), ap="";
  if(k.fmt==="12"){ap=h<12?" am":" pm";h=h%12||12}
  return (k.fmt==="12"?h:p(h))+":"+p(d.getMinutes())+(k.secs?":"+p(d.getSeconds()):"")+ap;
}
const clockDate=()=>new Date().toLocaleDateString(undefined,
  {weekday:"short",day:"numeric",month:"short"});
function bandColour(v,k){
  const lv=levelsFor(k.min,k.max);
  const warn=k.warn===undefined?lv.warn:k.warn, alert=k.alert===undefined?lv.alert:k.alert;
  return v<warn?"#8bc34a":v<alert?"#ffc107":"#ff5252";
}
function dial(f){
  const R=16, C=2*Math.PI*R, gap=C*0.25, arc=C-gap;      // 270-degree dial
  return `<svg class="g" viewBox="0 0 40 40" aria-hidden="true">
    <circle cx="20" cy="20" r="${R}" fill="none" stroke="var(--track)" stroke-width="4"
      stroke-linecap="round" stroke-dasharray="${arc.toFixed(2)} ${C.toFixed(2)}"
      transform="rotate(135 20 20)"/>
    <circle cx="20" cy="20" r="${R}" fill="none" stroke="currentColor" stroke-width="4"
      stroke-linecap="round" stroke-dasharray="${(arc*f).toFixed(2)} ${C.toFixed(2)}"
      transform="rotate(135 20 20)"/></svg>`;
}
function spark(ent){
  const h=HIST[ent];
  if(!h||h.length<2)return '<svg class="sp" viewBox="0 0 100 26" aria-hidden="true"></svg>';
  const lo=Math.min(...h), hi=Math.max(...h), span=(hi-lo)||1;
  const pts=h.map((v,i)=>[(i/(h.length-1))*100, 24-((v-lo)/span)*22]);
  const d=pts.map(p=>p[0].toFixed(1)+","+p[1].toFixed(1)).join(" ");
  const last=pts[pts.length-1];
  return `<svg class="sp" viewBox="0 0 100 26" preserveAspectRatio="none" aria-hidden="true">
    <polyline points="${d}" fill="none" stroke="currentColor" stroke-width="1.6"
      stroke-linejoin="round" stroke-linecap="round" vector-effect="non-scaling-stroke"/>
    <circle cx="${last[0].toFixed(1)}" cy="${last[1].toFixed(1)}" r="2" fill="currentColor"/></svg>`;
}
function keyHTML(k,n){
  const wide=n===WIDE?" wide":"";
  if(!k)return `<button class="key${wide}" aria-pressed="${sel===n}" data-k="${n}" aria-label="Empty key ${n+1}">
    <span class="empty">+</span></button>`;
  if(k.type==="clock"){
    const text=`<span class="clock${k.secs||k.fmt==="12"?" long":""}" data-clock>${esc(clockText(k))}</span>`
      +(k.date?`<span class="clockdate">${esc(clockDate())}</span>`:"")
      +(k.l?`<span class="kl">${esc(k.l)}</span>`:"");
    const ch=horizClass(k,n);
    return `<button class="key ent${wide}${ch}" aria-pressed="${sel===n}" data-k="${n}"
      style="color:${k.c};background:${paintBg(k)}" aria-label="${esc(k.l||"Clock")}">
      <span class="kdots" data-menu="${n}" title="More">${ico("dots-vertical")}</span>${tileBody(artOf(k,0),text,ch)}</button>`;
  }
  if(k.type==="entity"){
    const e=SEN(k.ent), v=e?parseFloat(e[3]):NaN;
    const frac=isNaN(v)?0:Math.max(0,Math.min(1,(v-k.min)/((k.max-k.min)||1)));
    const col=k.band?bandColour(isNaN(v)?k.min:v,k):k.c;
    const name=k.show==="full"&&(k.l||e)?`<span class="kl">${esc(k.l||e[1])}</span>`:"";
    const horiz=horizClass(k,n);
    return `<button class="key ent${wide}${horiz}${name?"":" noname"}" aria-pressed="${sel===n}" data-k="${n}"
      style="color:${col};background:${paintBg(k)};--track:${trackOf(bgOf(k))}" aria-label="${esc(k.l||(e?e[1]:"Entity"))}">
      <span class="kdots" data-menu="${n}" title="More">${ico("dots-vertical")}</span>${entityBody(k,e,frac,name,!!horiz)}</button>`;
  }
  const d=ACT(k.tap.a), nav=!!(d.nav||d.page), e=ENT(k.tap.t);
  // a key that drives an entity follows it: off looks off
  // ...unless it is a thing that just fires (a script, a scene, a button): those have no off
  const lit=nav||!e||["button","input_button","scene","script"].includes(domainOf(e[0]))
    ||!["off","closed","unavailable","unknown"].includes(e[3]);
  const bhoriz=horizClass(k,n);
  const label=k.l?`<span class="kl">${esc(k.l)}</span>`:"";
  const inner=tileBody(artOf(k,0),label,bhoriz);
  return `<button class="key${nav?" nav":""}${wide}${bhoriz}" aria-pressed="${sel===n}" data-k="${n}"
    style="color:${lit?k.c:"#545454"};background:${paintBg(k)}" aria-label="${esc(k.l||"Key "+(n+1))}">
    <span class="kdots" data-menu="${n}" title="More">${ico("dots-vertical")}</span>${inner}</button>`;
}
function paintDeck(){
  if(drag&&drag.active)return;                // never pull a key out from under a drag
  $("#screen").innerHTML=pages[pi].keys.map(keyHTML).join("");
  liveSig=sigNow();
}
function drawDeck(){
  $("#screen").innerHTML=pages[pi].keys.map(keyHTML).join("");
  liveSig=sigNow();
  markDraft();
}
// the states the keys on this screen are showing; when it changes, the preview is stale
let liveSig="";
function sigNow(){
  const s=hass().states;
  return pages[pi].keys.map(k=>{if(!k)return"";
    const id=k.type==="entity"?k.ent:k.type==="button"?k.tap.t:"";
    return id&&s[id]?s[id].state:""}).join("|");
}
host._onHass=()=>{if(sigNow()!==liveSig&&menuFor===null)paintDeck()};
function drawColors(){
  const k=view(); if(!k)return;
  const c=target==="fg"?k.c:bgOf(k), preset=COLORS.includes(c);
  $("#f-colors").innerHTML=COLORS.map(x=>
    `<button class="sw" data-c="${x}" aria-pressed="${x===c}" style="background:${x}" title="${x}"></button>`).join("")
   +`<span class="sw custom" aria-pressed="${!preset}" title="Pick any colour"
      ${preset?"":`style="background:${esc(c)}"`}>
      <input type="color" id="f-custom" value="${esc(c)}" aria-label="Pick any colour">
      <span class="mi">${ico("palette")}</span></span>`;
  const inp=$("#f-custom");
  inp.addEventListener("input",e=>{const k=ensureKey();if(!k)return;
    if(target==="fg")k.c=e.target.value; else k.bg=e.target.value;
    e.target.parentNode.style.background=e.target.value;
    $("#f-colors").querySelectorAll(".sw[data-c]").forEach(b=>b.setAttribute("aria-pressed","false"));
    e.target.parentNode.setAttribute("aria-pressed","true");paintSquares();drawDeck()});
  inp.addEventListener("change",()=>drawColors());
  paintSquares();
}
// the two overlapping squares: what each colour is, and which one is being set
function paintSquares(){
  const k=view(); if(!k)return;
  const fg=root.querySelector('[data-target="fg"]'), bg=root.querySelector('[data-target="bg"]');
  fg.style.background=k.c; bg.style.background=bgOf(k);
  fg.setAttribute("aria-pressed",target==="fg"); bg.setAttribute("aria-pressed",target==="bg");
}
function refreshSensor(){
  const k=view(); if(!k||k.type!=="entity"){$("#f-sensor").innerHTML="";return}
  const e=SEN(k.ent);
  $("#f-sensor").innerHTML=e?`<code>${esc(e[0])}</code> &middot; reading <b>${esc(e[3])} ${esc(e[4])}</b>`
    :"Nothing picked yet.";
}
const setSwitch=(name,on)=>{const b=root.querySelector(`[data-sw="${name}"]`);
  if(b)b.setAttribute("aria-checked",on?"true":"false")};
const hasRange=k=>k.type==="entity"&&(k.style==="bar"||k.style==="gauge");
const canBand=k=>k.type==="entity"&&["bar","gauge","graph"].includes(k.style);
function applyType(){
  const k=view(); if(!k)return;
  const isEnt=k.type==="entity";
  const isClock=k.type==="clock";
  $("#entityPick").hidden=!isEnt;
  $("#buttonOnly").hidden=isEnt||isClock;
  $("#clockOnly").hidden=!isClock;
  $("#styleField").hidden=!isEnt;
  const iconIsOptional=!isEnt;                   // entity keys choose it through Display
  $("#sw-icon").hidden=!iconIsOptional;
  setSwitch("icon",showsIcon(k));
  $("#iconField").hidden=(isEnt&&k.style!=="icon")||(iconIsOptional&&!showsIcon(k));
  $("#typeHint").textContent=isClock
    ? "A clock key shows the time from the deck itself. It needs nothing from Home Assistant."
    : isEnt
    ? "An entity key shows a live reading. The screen redraws whenever the value changes."
    : "A button runs something when you press it.";
  if(isClock){
    $("#f-clockfmt").value=k.fmt||"24";
    setSwitch("secs",!!k.secs); setSwitch("date",!!k.date);
  }
  $("#f-type").querySelectorAll("input").forEach(r=>{r.checked=(r.value===k.type)});
  if(!k.layout)k.layout="v";
  $("#layoutField").hidden=(sel!==WIDE)||!hasArt(k);   // nothing to place beside the text
  $("#f-layout").value=k.layout;
  $("#rangeField").hidden=!hasRange(k);
  $("#sw-band").hidden=!canBand(k);
  $("#sw-name").hidden=!isEnt;
  setSwitch("name",k.show==="full");
  setSwitch("band",!!k.band);
  const overridden=canBand(k)&&!!k.band;        // colour-by-level wins over the swatches
  const fgLocked=overridden&&target==="fg";     // the background is still the user's to choose
  $("#colourHint").hidden=!fgLocked;
  $("#f-colors").classList.toggle("locked",fgLocked);
  $("#bandField").hidden=!overridden;
  if(overridden){
    const lv=levelsFor(k.min,k.max);
    if(k.warn===undefined)k.warn=lv.warn;
    if(k.alert===undefined)k.alert=lv.alert;
    $("#f-warn").value=k.warn; $("#f-alert").value=k.alert;
  }
  if(isEnt){
    $("#f-style").value=k.style;
    $("#f-min").value=k.min; $("#f-max").value=k.max;
    entityCombo.sync(); refreshSensor();
  } else { tapPair.sync(); holdPair.sync() }
}
function openKey(n){
  sel=n;
  blankView=pages[pi].keys[n]?null:BLANK();   // an empty slot gets blank fields, not a new key
  const k=view();
  $("#f-label").value=k.l;syncLabelClear();
  drawColors();iconCombo.sync();applyType();drawDeck();
}
/* Every clickable data-* hook, in one place, so a new control cannot be left unwired. */
const HANDLED=["p","k","c","target","addp","editp","sw","menu","kmenu"].map(n=>`[data-${n}]`).join(",");
root.addEventListener("click",e=>{
  const t=e.target.closest(HANDLED);
  if(!t)return;
  if(t.dataset.editp!==undefined){pi=+t.dataset.editp;drawTabs();openKey(0);openViewDlg();return}
  if(t.dataset.addp!==undefined){pages.push({name:"Screen "+(pages.length+1),icon:"",keys:Array(NKEYS).fill(null)});
    pi=pages.length-1;drawTabs();openKey(0);return}
  if(t.dataset.p!==undefined){pi=+t.dataset.p;drawTabs();openKey(0);return}
  if(t.dataset.menu!==undefined){openKeyMenu(+t.dataset.menu,t);return}
  if(t.dataset.kmenu!==undefined){
    if(t.dataset.kmenu==="delete"&&menuFor!==null){
      if(t.dataset.armed!=="1"){armDelete(t);return}      // ask once, act on the second click
      const gone=menuFor;
      pages[pi].keys[gone]=null;
      if(sel===gone)openKey(gone); else drawDeck();   // stay put, fields go blank
    }
    closeKeyMenu();return}
  if(t.dataset.k!==undefined){closeKeyMenu();openKey(+t.dataset.k);return}
  // choosing which colour to set changes nothing about the key, so it must not create one
  if(t.dataset.target){target=t.dataset.target;drawColors();applyType();return}
  const k=ensureKey();if(!k)return;
  if(t.dataset.sw){
    const on=t.getAttribute("aria-checked")!=="true";
    t.setAttribute("aria-checked",on?"true":"false");
    if(t.dataset.sw==="icon"){k.showIcon=on;applyType()}
    if(t.dataset.sw==="secs")k.secs=on;
    if(t.dataset.sw==="date")k.date=on;
    if(t.dataset.sw==="name")k.show=on?"full":"value";
    if(t.dataset.sw==="band"){k.band=on;applyType()}
    drawDeck();return}
  if(t.dataset.c){if(target==="fg")k.c=t.dataset.c;else k.bg=t.dataset.c;drawColors();drawDeck()}
});

/* radios and selects report through change, not click */
$("#f-type").addEventListener("change",e=>{
  const k=ensureKey(); if(!k)return;
  const v=e.target.value; if(k.type===v)return;
  if(v==="entity"){k.type="entity";k.ent=k.ent||"";
    k.show=k.show||"value";k.style=k.style||"icon";k.layout=k.layout||"v";
    const r=rangeFor(k.ent);if(k.min===undefined){k.min=r[0];k.max=r[1];k.band=false}
    const se=SEN(k.ent);if(se)k.i=se[5]}
  else if(v==="clock"){k.type="clock";
    k.fmt=k.fmt||CLOCK_DEFAULTS.fmt; if(k.secs===undefined)k.secs=CLOCK_DEFAULTS.secs;
    if(k.date===undefined)k.date=CLOCK_DEFAULTS.date; k.i="clock-outline"}
  else{k.type="button";
    k.tap=k.tap||{a:"light.toggle",t:""};k.hold=k.hold||{a:"none",t:""}}
  iconCombo.sync();applyType();drawDeck();
});
$("#f-style").addEventListener("change",e=>{
  const k=ensureKey(); if(!k)return;
  k.style=e.target.value;
  applyType();                 // single source of truth for what is shown
  drawDeck();
});
$("#f-clockfmt").addEventListener("change",e=>{
  const k=ensureKey(); if(!k)return; k.fmt=e.target.value; drawDeck();
});
$("#f-layout").addEventListener("change",e=>{
  const k=ensureKey(); if(!k)return; k.layout=e.target.value; drawDeck();
});
/* ---------- the three-dot menu on a key ---------- */
let menuFor=null;
function openKeyMenu(n,el){
  menuFor=n;
  const m=$("#keyMenu"), deck=el.closest(".deck"), r=el.getBoundingClientRect(), d=deck.getBoundingClientRect();
  m.hidden=false;
  m.style.left=Math.min(r.left-d.left, d.width-m.offsetWidth-6)+"px";
  m.style.top=(r.bottom-d.top+4)+"px";
}
const DEL_ICON="delete-outline", DEL_WARN="alert-circle-outline";
let armTimer=null;
function setDeleteItem(el,armed){
  el.dataset.armed=armed?"1":"";
  el.querySelector("[data-ico]").textContent=ico(armed?DEL_WARN:DEL_ICON);
  el.querySelector("[data-text]").textContent=armed?"Are you sure?":"Delete";
}
function armDelete(el){
  setDeleteItem(el,true);
  clearTimeout(armTimer);
  armTimer=setTimeout(()=>setDeleteItem(el,false),4000);
}
function closeKeyMenu(){
  menuFor=null; $("#keyMenu").hidden=true;
  clearTimeout(armTimer);
  const el=$("#keyMenu").querySelector("[data-kmenu]"); if(el)setDeleteItem(el,false);
}
root.addEventListener("mousedown",e=>{
  if($("#keyMenu").hidden)return;
  if(!e.target.closest("#keyMenu")&&!e.target.closest("[data-menu]"))closeKeyMenu();
});
root.addEventListener("keydown",e=>{if(e.key==="Escape")closeKeyMenu()});

/* ---------- preview mode ----------
   With it on, the preview stops being a picture and behaves like the deck: a key
   does what it says, using the unsent draft, so a key can be tried before it goes
   to the device. The rules for tap and hold are the deck's own (on_key in
   deckd.c): a key with nothing on hold acts the moment it is pressed, otherwise
   hold fires at half a second and tap on release before that. Screen keys are
   handled here and never reach Home Assistant, again as on the deck. */
let live=false, press=null, liveHist=[], noteTimer=null;
const NOTE="Preview is on: a key here really does what it says, using your unsent changes. "
  +"The deck is not touched.";
function note(text){
  const el=$("#liveNote");
  clearTimeout(noteTimer);
  el.textContent=text||NOTE;
  if(text)noteTimer=setTimeout(()=>{el.textContent=NOTE},3500);
}
function setLive(on){
  live=on;
  if(press){clearTimeout(press.timer);press=null}
  screenEl.classList.toggle("live",on);
  screenEl.querySelectorAll(".down").forEach(el=>el.classList.remove("down"));
  $("#btn-live").setAttribute("aria-pressed",on?"true":"false");
  $("#liveLabel").textContent=on?"Preview on":"Preview";
  $("#btn-live").querySelector(".mi").textContent=ico(on?"gesture-tap":"gesture-tap-button");
  $("#liveNote").hidden=!on;
  liveHist=[];
  note("");
}
function goScreen(n,remember){
  if(n<0||n>=pages.length||n===pi)return;
  if(remember)liveHist.push(pi);
  pi=n; drawTabs(); paintDeck();      // paint, not draw: moving about changes nothing to save
  note("Screen "+(n+1)+", \u201c"+pages[n].name+"\u201d");
}
function liveFire(n,gesture){
  const k=pages[pi].keys[n];
  if(!k)return;
  const name=k.l||("Key "+(n+1));
  if(k.type==="entity"){note(name+": a reading, so a press does nothing");return}
  if(k.type==="clock"){note(name+": a clock, so a press does nothing");return}
  const slot=k[gesture]||{}, action=slot.a||"none", target=slot.t||"";
  if(action==="none"){note(name+": nothing set for "+gesture);return}
  if(action==="deck.next_page"){goScreen((pi+1)%pages.length,true);return}
  if(action==="deck.previous_page"){goScreen((pi+pages.length-1)%pages.length,true);return}
  if(action==="deck.go_to_page"){goScreen(+target||0,true);return}
  if(action==="deck.back"){
    if(liveHist.length)goScreen(liveHist.pop(),false); else note(name+": nowhere to go back to");
    return}
  note(name+": "+action+(target?" \u2192 "+target:""));
  hass().callWS({type:"ulanzi_deck/press",screen:pi,key:n,gesture})
    .catch(e=>note(name+": it did not run \u2014 "+(e&&e.message?e.message:"Home Assistant said no")));
}
function liveDown(n){
  const k=pages[pi].keys[n];
  const el=screenEl.querySelector(`[data-k="${n}"]`);
  if(el)el.classList.add("down");
  press={n,fired:false,timer:null};
  const hasHold=k&&k.type!=="entity"&&k.type!=="clock"&&((k.hold&&k.hold.a)||"none")!=="none";
  if(!hasHold){press.fired=true;liveFire(n,"tap");return}
  press.timer=setTimeout(()=>{
    if(press&&press.n===n){press.fired=true;liveFire(n,"hold")}
  },500);
}
function liveUp(){
  if(!press)return;
  const p=press; press=null;
  clearTimeout(p.timer);
  const el=screenEl.querySelector(`[data-k="${p.n}"]`);
  if(el)el.classList.remove("down");
  if(!p.fired)liveFire(p.n,"tap");
}
$("#btn-live").addEventListener("click",()=>setLive(!live));

/* ---------- select and drag, within one screen ----------
   Pointer events, and no pointer capture: capturing retargets the follow-up
   click to the capturing element, so clicks on a key stopped selecting it.
   Selection happens on pointerup instead, so nothing depends on click order. */
const screenEl=$("#screen");
let drag=null, swallowClick=false;
const keyUnder=(x,y)=>{
  const el=root.elementFromPoint(x,y);
  const b=el&&el.closest?el.closest("[data-k]"):null;
  return b?+b.dataset.k:null;
};
function markOver(n){
  screenEl.querySelectorAll(".over").forEach(el=>el.classList.remove("over"));
  if(!drag||n===null||n===drag.from)return;
  const el=screenEl.querySelector(`[data-k="${n}"]`); if(el)el.classList.add("over");
}
function endDrag(){
  drag=null;
  window.removeEventListener("pointermove",onDragMove);
  window.removeEventListener("pointerup",onDragUp);
  window.removeEventListener("pointercancel",onDragCancel);
  screenEl.classList.remove("dragging");
  host.classList.remove("dragging-keys");
  screenEl.querySelectorAll(".over,.dragging").forEach(el=>el.classList.remove("over","dragging"));
}
function onDragMove(e){
  if(!drag)return;
  if(!drag.active){
    if(Math.hypot(e.clientX-drag.x,e.clientY-drag.y)<5)return;   // a small wobble is still a click
    drag.active=true;
    screenEl.classList.add("dragging");
    host.classList.add("dragging-keys");
    const el=screenEl.querySelector(`[data-k="${drag.from}"]`); if(el)el.classList.add("dragging");
  }
  markOver(keyUnder(e.clientX,e.clientY));
}
function onDragUp(e){
  if(!drag)return;
  const d=drag, to=d.active?keyUnder(e.clientX,e.clientY):null;
  endDrag();
  swallowClick=true;                 // this interaction is already handled
  if(!d.active){openKey(d.from);return}            // a plain press selects
  if(to===null||to===d.from){drawDeck();return}
  const ks=pages[pi].keys;
  const a=ks[d.from]; ks[d.from]=ks[to]; ks[to]=a; // a swap: the wide slot is fixed in hardware
  if(sel===d.from)sel=to; else if(sel===to)sel=d.from;
  openKey(sel===null?to:sel);
}
function onDragCancel(){endDrag()}
screenEl.addEventListener("pointerdown",e=>{
  if(e.button!==0)return;
  if(e.target.closest("[data-menu]"))return;       // the three-dot menu is not a handle
  const b=e.target.closest("[data-k]"); if(!b)return;
  if(live){                                        // preview mode: the key acts, nothing moves
    swallowClick=true;
    liveDown(+b.dataset.k);
    window.addEventListener("pointerup",liveUp,{once:true});
    window.addEventListener("pointercancel",liveUp,{once:true});
    return;
  }
  drag={from:+b.dataset.k,x:e.clientX,y:e.clientY,active:false};
  window.addEventListener("pointermove",onDragMove);
  window.addEventListener("pointerup",onDragUp);
  window.addEventListener("pointercancel",onDragCancel);
});
// if that click never arrives (released outside, say) the flag must not survive
root.addEventListener("pointerdown",()=>{swallowClick=false},true);
root.addEventListener("click",e=>{
  if(!swallowClick)return;
  swallowClick=false;
  e.stopPropagation(); e.preventDefault();
},true);

function syncLabelClear(){$("#f-label-clear").hidden=!$("#f-label").value}
$("#f-label").addEventListener("input",e=>{const k=ensureKey();
  if(k){k.l=e.target.value;drawDeck()}syncLabelClear()});
$("#f-label-clear").addEventListener("click",()=>{
  const k=ensureKey(); $("#f-label").value="";
  if(k){k.l="";drawDeck()}
  syncLabelClear(); $("#f-label").focus();
});
$("#f-warn").addEventListener("input",e=>{const k=ensureKey();if(!k)return;
  const v=parseFloat(e.target.value); if(!isNaN(v)){k.warn=v;drawDeck()}});
$("#f-alert").addEventListener("input",e=>{const k=ensureKey();if(!k)return;
  const v=parseFloat(e.target.value); if(!isNaN(v)){k.alert=v;drawDeck()}});
$("#f-min").addEventListener("input",e=>{const k=ensureKey();if(!k)return;
  const v=parseFloat(e.target.value); if(!isNaN(v)){k.min=v;drawDeck()}});
$("#f-max").addEventListener("input",e=>{const k=ensureKey();if(!k)return;
  const v=parseFloat(e.target.value); if(!isNaN(v)){k.max=v;drawDeck()}});
/* ---------- screen editor, the way a dashboard view is edited ---------- */
let dlgIcon="";
const viewIconCombo=new Combo($("#c-viewicon"),{max:80,
  find:q=>rank(q,ICON_NAMES,n=>[n,ALIAS[n]]),
  row:(n,h,i)=>optRow(i,h,ico(n),n,"mdi:"+n),
  value:n=>n,label:n=>n,lead:n=>n?ico(n):"",
  get:()=>dlgIcon,
  onPick:v=>{dlgIcon=v||""}});
function openViewDlg(){
  dlgIcon=pages[pi].icon||"";
  $("#dlg-name").value=pages[pi].name;
  $("#dlgTitle").textContent="Edit screen";
  $("#dlg-del").disabled=pages.length<2;
  $("#dlg-del").textContent=pages.length<2?"Can’t delete the only screen":"Delete screen";
  viewIconCombo.sync();
  $("#viewDlg").hidden=false;
  $("#dlg-name").focus();
}
function closeViewDlg(){$("#viewDlg").hidden=true}
$("#dlg-cancel").addEventListener("click",closeViewDlg);
$("#dlg-save").addEventListener("click",()=>{
  pages[pi].name=$("#dlg-name").value.trim()||"Untitled";
  pages[pi].icon=dlgIcon;
  closeViewDlg();drawTabs();drawDeck();
});
$("#dlg-del").addEventListener("click",e=>{
  if(pages.length<2)return;
  const b=e.currentTarget;
  if(b.dataset.armed!=="1"){b.dataset.armed="1";b.textContent="Really delete “"+pages[pi].name+"”?";
    setTimeout(()=>{if(b.dataset.armed==="1"){b.dataset.armed="";b.textContent="Delete screen"}},4000);return}
  b.dataset.armed="";b.textContent="Delete screen";
  pages.splice(pi,1); pi=Math.max(0,pi-1); closeViewDlg(); drawTabs(); openKey(0);
});
$("#viewDlg").addEventListener("mousedown",e=>{if(e.target===$("#viewDlg"))closeViewDlg()});
root.addEventListener("keydown",e=>{if(e.key==="Escape"&&!$("#viewDlg").hidden)closeViewDlg()});

/* ---------- the deck's own settings ---------- */
$("#btn-settings").querySelector(".mi").textContent=ico("cog");
function closeSetDlg(){$("#setDlg").hidden=true}
$("#btn-settings").addEventListener("click",()=>{
  const dd=$("#set-sleep"), want=String(settings.sleep);
  // a stored value with no option of its own gets one, so nothing is silently changed
  if(![...dd.options].some(o=>o.value===want)){
    const o=document.createElement("option");
    o.value=want; o.textContent=want+(want==="1"?" minute":" minutes");
    dd.appendChild(o);
  }
  dd.value=want;
  $("#setDlg").hidden=false;
  dd.focus();
});
$("#set-cancel").addEventListener("click",closeSetDlg);
$("#setDlg").addEventListener("mousedown",e=>{if(e.target===$("#setDlg"))closeSetDlg()});
root.addEventListener("keydown",e=>{if(e.key==="Escape"&&!$("#setDlg").hidden)closeSetDlg()});
$("#set-save").addEventListener("click",()=>{
  settings.sleep=+$("#set-sleep").value||0;
  closeSetDlg(); markDraft();
});

/* ---------- draft, kept by itself ----------
   Every edit is written to Home Assistant's storage as you make it, so closing
   the page or restarting loses nothing. Only Send to device reaches the deck. */
const snap=()=>JSON.stringify([pages,settings]);
let publishedSnap=init.published?JSON.stringify([init.published,
  Object.assign({},SET_DEFAULTS,init.published_settings||{})]):null;
let savedSnap=snap(), saveTimer=null;
function persist(){
  if(snap()===savedSnap)return;
  clearTimeout(saveTimer);
  saveTimer=setTimeout(()=>{
    const s=snap();
    hass().callWS({type:"ulanzi_deck/save",pages,settings}).then(()=>{savedSnap=s}).catch(()=>{});
  },400);
}
function markDraft(){
  const dirty=snap()!==publishedSnap, btn=$("#btn-publish");
  btn.disabled=!dirty;
  btn.textContent=dirty?"Send to device":"Sent";
  persist();
}
$("#btn-publish").addEventListener("click",()=>{
  const s=snap(), btn=$("#btn-publish");
  clearTimeout(saveTimer);
  btn.disabled=true;
  hass().callWS({type:"ulanzi_deck/publish",pages,settings}).then(()=>{savedSnap=publishedSnap=s;markDraft()})
    .catch(()=>{btn.disabled=false;btn.textContent="Could not send \u2014 try again"});
});

/* ---------- the bridge, and the deck behind it ---------- */
let pendingBridge=null;
function showStatus(st){
  const dot=$("#chipDot"), text=$("#chipText"), allow=$("#btn-allow");
  pendingBridge=st.pending;
  dot.className="dot"+(st.deck?" ok":st.pending?" warn":"");
  text.textContent=st.deck?"Deck connected"
    :st.pending?"\u201c"+st.pending.name+"\u201d wants to connect"
    :st.bridge==="connected"?"Bridge connected, no deck":"Bridge not connected";
  allow.hidden=!st.pending;
  // Until a Mac is connected there is nothing worth configuring, so the setup
  // card is the whole page rather than one card beside the editor.
  const setup=st.bridge==="none";
  $("#getApp").hidden=!setup;
  $("#configCard").hidden=setup;
  $("#deckCard").hidden=setup;
  $("#btn-publish").hidden=setup;
  $("#btn-settings").hidden=setup;
}
$("#btn-getapp").addEventListener("click",async()=>{
  const b=$("#btn-getapp"), err=$("#getAppErr");
  b.disabled=true; b.textContent="Preparing\u2026"; err.hidden=true;
  try{
    // Signed so the download carries this admin's authority: the zip holds a key
    // that lets a Mac in, so it must not be a link anyone could follow.
    const {path}=await hass().callWS({type:"auth/sign_path",path:"/api/ulanzi_deck/companion-app",expires:60});
    location.href=path;
    // The block comes a moment later, so the way past it is on screen first.
    $("#gateHelp").hidden=false;
  }catch(e){
    err.textContent=(e&&e.message)||"It could not be prepared. Try again.";
    err.hidden=false;
  }
  b.disabled=false; b.textContent="Get the companion app";
});
$("#btn-allow").addEventListener("click",()=>{
  if(pendingBridge)hass().callWS({type:"ulanzi_deck/allow",bridge_id:pendingBridge.bridge_id}).catch(()=>{});
});
showStatus(init.status);
$("#menuBtn").addEventListener("click",()=>
  host.dispatchEvent(new CustomEvent("hass-toggle-menu",{bubbles:true,composed:true})));
host._onNarrow=()=>{$("#menuBtn").hidden=!(host._narrow||hass().dockedSidebar==="always_hidden")};
host._onNarrow();
setDeleteItem($("#keyMenu").querySelector("[data-kmenu]"),false);
// whatever must stop when the panel is off screen starts here, so it can start again
host._resume=()=>{
  host._timers.push(setInterval(()=>{
    root.querySelectorAll("[data-clock]").forEach(el=>{
      const n=+el.closest("[data-k]").dataset.k, k=pages[pi].keys[n];
      if(k&&k.type==="clock")el.textContent=clockText(k);
    });
  },1000));
  hass().connection.subscribeMessage(showStatus,{type:"ulanzi_deck/subscribe"})
    .then(u=>{host._unsubs.push(u)}).catch(()=>{});
};
host._resume();
drawTabs();drawDeck();
// start on the first screen with its first key selected. An empty first key shows
// blank fields without creating a key, so loading the page never dirties a draft.
setLive(false);
pi=0;openKey(0);

}

class UlanziDeckPanel extends HTMLElement{
  constructor(){
    super();
    this.attachShadow({mode:"open"});
    this._timers=[]; this._unsubs=[]; this._built=false; this._starting=false;
  }
  set hass(h){
    this._hass=h;
    if(this._built){if(this._onHass)this._onHass()}
    else this._start();
  }
  get hass(){return this._hass}
  set narrow(v){this._narrow=v; if(this._onNarrow)this._onNarrow()}
  set panel(v){this._panel=v}
  set route(v){this._route=v}
  async _start(){
    if(this._starting||Date.now()-(this._failedAt||0)<10000)return;
    this._starting=true;
    this.shadowRoot.innerHTML="<style>"+STYLE+"</style><div class='loading'>Loading\u2026</div>";
    try{
      await assets;
      const init=await this._hass.callWS({type:"ulanzi_deck/get"});
      this.shadowRoot.innerHTML="<style>"+STYLE+"</style>"+MARKUP;
      build(this,init);
      this._built=true;
    }catch(err){
      this._starting=false; this._failedAt=Date.now();
      this.shadowRoot.querySelector(".loading").textContent=
        "Ulanzi Deck could not load: "+((err&&err.message)||err);
    }
  }
  disconnectedCallback(){
    this._timers.forEach(clearInterval); this._timers=[];
    this._unsubs.forEach(u=>{try{u()}catch(_){}}); this._unsubs=[];
  }
  connectedCallback(){
    if(this._built){if(!this._timers.length&&this._resume)this._resume()}
    else if(this._hass)this._start();
  }
}
// reloading the integration makes the browser fetch this file again; define once
if(!customElements.get("ulanzi-deck-panel"))customElements.define("ulanzi-deck-panel",UlanziDeckPanel);
