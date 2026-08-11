#!/usr/bin/env python3
"""Generate the five Premium Looks concepts from ONE shared DOM.

The point of the exercise, made falsifiable: every concept below renders the
*identical* markup — same sidebar, same hero, same three shelves, same focused
card, same skeleton row. Only the stylesheet changes. If the five look like
five different apps, the thesis holds; if they look like one app in five
tints, the vocabulary is wrong and we find that out in week 1 rather than
week 5.

The predecessor mockup (`detail_themes_mockup/`) rendered twenty palettes on
one layout and produced twenty palettes. Same method, different question:
this one varies material, separation, scrim, artwork treatment, focus and
density — the things a palette cannot reach.

    python3 design/mockups/premium_looks_mockup/build.py
"""
import os

OUT = os.path.dirname(os.path.abspath(__file__))

# ── The shared DOM. Identical in all five. ────────────────────────────────
# Classes are SEMANTIC (what a thing is), never presentational (what it looks
# like), so a stylesheet is free to express them however it likes — which is
# exactly the contract `SurfaceTokens.modelFor(family)` will have in Dart.
BODY = """
<div class="tv">
  <div class="grain"></div>
  <div class="bars"></div>

  <nav class="rail">
    <div class="mark">D</div>
    <a class="nav on"><i data-g="home"></i><span>Home</span></a>
    <a class="nav"><i data-g="search"></i><span>Search</span></a>
    <a class="nav"><i data-g="compass"></i><span>Discover</span></a>
    <a class="nav"><i data-g="live"></i><span>Live TV</span></a>
    <a class="nav"><i data-g="cloud"></i><span>Cloud</span></a>
    <a class="nav bot"><i data-g="gear"></i><span>Settings</span></a>
  </nav>

  <section class="hero">
    <div class="art backdrop"></div>
    <div class="scrim"></div>
    <div class="herobody">
      <div class="eyebrow">Continue watching · S2 E4</div>
      <h1 class="title">The Long <em>Night</em></h1>
      <div class="meta">
        <span class="badge">4K</span><span class="badge">HDR</span>
        <span class="badge">ATMOS</span>
        <span class="dot">2019</span><span class="dot">TV-MA</span>
        <span class="dot">48 min left</span>
      </div>
      <p class="blurb">The siege begins at dusk. Everything the watch has
        prepared for arrives at once, and the walls are only as good as the
        people standing on them.</p>
      <div class="btns">
        <button class="pri"><i data-g="play"></i>Resume</button>
        <button class="sec">Episodes</button>
        <button class="sec ic"><i data-g="plus"></i></button>
      </div>
      <div class="prog"><span style="width:62%"></span></div>
    </div>
  </section>

  <div class="shelves">
  <section class="shelf">
    <h2>Continue watching</h2>
    <div class="rowcards">
      <div class="card"><div class="art p1"></div><div class="cap"><b>Ridgeline</b><i>S1 E7</i></div><div class="bar"><span style="width:78%"></span></div></div>
      <div class="card focus"><div class="art p2"></div><div class="cap"><b>Harbour Lights</b><i>S3 E2</i></div><div class="bar"><span style="width:41%"></span></div><div class="ring"></div></div>
      <div class="card"><div class="art p3"></div><div class="cap"><b>Slow Water</b><i>S1 E1</i></div><div class="bar"><span style="width:12%"></span></div></div>
      <div class="card"><div class="art p4"></div><div class="cap"><b>The Cartographer</b><i>S2 E9</i></div><div class="bar"><span style="width:90%"></span></div></div>
      <div class="card"><div class="art p5"></div><div class="cap"><b>Nightjar</b><i>S1 E3</i></div><div class="bar"><span style="width:33%"></span></div></div>
      <div class="card"><div class="art p6"></div><div class="cap"><b>Ember Lake</b><i>S4 E1</i></div><div class="bar"><span style="width:55%"></span></div></div>
    </div>
  </section>

  <section class="shelf">
    <h2>Trending</h2>
    <div class="rowcards">
      <div class="card sk"><div class="art"></div><div class="cap"><b></b><i></i></div></div>
      <div class="card sk"><div class="art"></div><div class="cap"><b></b><i></i></div></div>
      <div class="card sk"><div class="art"></div><div class="cap"><b></b><i></i></div></div>
      <div class="card sk"><div class="art"></div><div class="cap"><b></b><i></i></div></div>
      <div class="card sk"><div class="art"></div><div class="cap"><b></b><i></i></div></div>
      <div class="card sk"><div class="art"></div><div class="cap"><b></b><i></i></div></div>
    </div>
  </section>
  </div>
</div>

<div class="strip">
  <div class="cell"><div class="lb">rest</div>
    <div class="card"><div class="art p3"></div><div class="cap"><b>Slow Water</b><i>S1 E1</i></div><div class="bar"><span style="width:12%"></span></div></div></div>
  <div class="cell"><div class="lb">focused</div>
    <div class="card focus"><div class="art p2"></div><div class="cap"><b>Harbour Lights</b><i>S3 E2</i></div><div class="bar"><span style="width:41%"></span></div><div class="ring"></div></div></div>
  <div class="cell"><div class="lb">loading</div>
    <div class="card sk"><div class="art"></div><div class="cap"><b></b><i></i></div></div></div>
  <div class="cell wide"><div class="lb">controls</div>
    <div class="ctl">
      <button class="pri"><i data-g="play"></i>Resume</button>
      <button class="sec">Episodes</button>
      <span class="badge">4K</span><span class="badge">HDR</span>
      <span class="dot">2019</span>
    </div></div>
</div>
"""

# Stroke glyphs, injected by data-g. No emoji, per the house rule that emoji
# as icons is one of the six things that read "cheap".
GLYPHS = """
<script>
const G={
 home:'M3 11l9-7 9 7v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z',
 search:'M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14zM20 20l-4-4',
 compass:'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM15.5 8.5l-2 5-5 2 2-5z',
 live:'M3 6h18v11H3zM8 21h8M12 17v4',
 cloud:'M7 18h9a4 4 0 0 0 .4-8A6 6 0 0 0 5 11a3.5 3.5 0 0 0 2 7z',
 gear:'M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6zM19 12a7 7 0 0 0-.1-1l2-1.5-2-3.4-2.3 1a7 7 0 0 0-1.7-1L14.5 3h-4l-.4 2.6a7 7 0 0 0-1.7 1l-2.3-1-2 3.4L6 11a7 7 0 0 0 0 2l-2 1.5 2 3.4 2.3-1a7 7 0 0 0 1.7 1l.4 2.6h4l.4-2.6a7 7 0 0 0 1.7-1l2.3 1 2-3.4-2-1.5c.1-.3.1-.7.1-1z',
 play:'M7 4l13 8-13 8z',
 plus:'M12 5v14M5 12h14'};
document.querySelectorAll('[data-g]').forEach(function(e){
  var d=G[e.dataset.g]; if(!d) return;
  e.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" '+
    'stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">'+
    '<path d="'+d+'"/></svg>';
});
</script>
"""

# Geometry every concept shares. Only DECORATION varies below — this block is
# the mockup's own version of D8 ("layout does not change"), so a concept that
# needed to move something would have to declare it, loudly, right here.
BASE = """
*{box-sizing:border-box;margin:0;padding:0}
body{font:14px/1.5 var(--sans);padding:38px 4vw 90px}
svg{width:100%;height:100%}
.tv{width:min(1560px,96vw);aspect-ratio:16/9;position:relative;overflow:hidden;
    box-shadow:0 40px 120px rgba(0,0,0,.75)}
.rail{position:absolute;left:0;top:0;bottom:0;width:var(--railw);
      display:flex;flex-direction:column;align-items:stretch;
      gap:var(--navgap);padding:var(--railpad);z-index:5}
.mark{width:34px;height:34px;display:grid;place-items:center;font-weight:800;
      font-size:15px;margin-bottom:16px;flex:none}
.nav{display:flex;align-items:center;gap:11px;padding:var(--navpad);
     font-size:13px;white-space:nowrap;overflow:hidden}
.nav i{width:19px;height:19px;flex:none;display:block}
.nav.bot{margin-top:auto}
.hero{position:absolute;left:var(--railw);right:0;top:0;height:var(--herow);
      overflow:hidden;z-index:1}
.hero .backdrop{position:absolute;inset:0}
.scrim{position:absolute;inset:0}
.herobody{position:absolute;left:var(--gut);bottom:var(--herob);right:38%;z-index:3}
.eyebrow{font-size:10.5px;letter-spacing:2px;text-transform:uppercase;margin-bottom:10px}
.title{font-size:var(--titlesz);line-height:1.02;margin-bottom:12px}
.meta{display:flex;align-items:center;gap:8px;margin-bottom:12px;font-size:11px;flex-wrap:wrap}
.badge{padding:2px 7px;font-size:9.5px;letter-spacing:1.1px;font-weight:700}
.blurb{font-size:12.5px;line-height:1.6;max-width:520px;margin-bottom:16px}
.btns{display:flex;gap:10px;align-items:center}
button{font:inherit;font-size:12.5px;font-weight:600;padding:9px 20px;
       display:flex;align-items:center;gap:8px;cursor:pointer;border:0}
button i{width:14px;height:14px;display:block}
button.ic{padding:9px 11px}
.prog{height:3px;width:300px;margin-top:16px;overflow:hidden}
.prog span{display:block;height:100%}
.shelves{position:absolute;left:var(--railw);right:0;top:var(--herow);bottom:0;
         z-index:4;overflow:hidden;padding-top:var(--shelftop)}
.shelf{padding:0 var(--gut) var(--shelftop)}
.shelf h2{font-size:13px;margin-bottom:var(--capgap);font-weight:600}
.shelf h2 em{font-style:italic;font-weight:400}
.rowcards{display:flex;gap:var(--cardgap)}
.card{width:var(--cardw);flex:none;position:relative}
.card .art{aspect-ratio:2/3;position:relative;overflow:hidden}
.cap{padding-top:8px}
.cap b{display:block;font-size:11.5px;font-weight:600;white-space:nowrap;
       overflow:hidden;text-overflow:ellipsis}
.cap i{display:block;font-size:10px;font-style:normal;margin-top:2px}
.card .bar{height:2.5px;margin-top:6px;overflow:hidden}
.card .bar span{display:block;height:100%}
.card .ring{position:absolute;left:0;right:0;top:0;aspect-ratio:2/3;
            pointer-events:none}
.card.sk .art{}
.card.sk .cap b{height:9px;width:72%}
.card.sk .cap i{height:8px;width:44%;margin-top:5px}
.grain,.bars{position:absolute;inset:0;pointer-events:none;z-index:6}
/* close-ups: the states a 16:9 frame cannot show at a readable size */
.strip{display:flex;gap:26px;align-items:flex-start;margin-top:26px;flex-wrap:wrap}
.cell{display:flex;flex-direction:column;gap:9px}
.cell .card{position:relative}
.cell.wide{flex:1;min-width:330px}
.lb{font-size:9.5px;letter-spacing:2px;text-transform:uppercase;opacity:.5}
.ctl{display:flex;align-items:center;gap:9px;flex-wrap:wrap;padding-top:2px}
/* page chrome around the mock */
h3.pt{font:600 26px/1.2 var(--sans);letter-spacing:-.3px;margin-bottom:8px}
p.pd{font-size:13.5px;max-width:900px;margin-bottom:26px;line-height:1.6}
.legend{margin-top:26px;display:grid;grid-template-columns:repeat(auto-fit,minmax(215px,1fr));
        gap:14px;max-width:1560px}
.legend div{font-size:12px;line-height:1.55;padding:13px 15px}
.legend b{display:block;font-size:10px;letter-spacing:1.6px;text-transform:uppercase;
          margin-bottom:5px}
a.back{font-size:12px;display:inline-block;margin-bottom:22px}
"""

# Poster stand-ins. Same six in every concept, so grading differences are
# attributable to the concept and not to the fixture.
ART = """
.p1{background:linear-gradient(160deg,#2A4A6B,#0E1E30 62%),radial-gradient(70% 45% at 50% 22%,rgba(255,190,120,.5),transparent)}
.p2{background:linear-gradient(150deg,#6B2F3A,#1B0F16 65%),radial-gradient(60% 40% at 62% 26%,rgba(255,150,110,.55),transparent)}
.p3{background:linear-gradient(200deg,#1F4A42,#08181B 68%),radial-gradient(65% 42% at 38% 30%,rgba(140,225,200,.4),transparent)}
.p4{background:linear-gradient(140deg,#4A3A66,#150F22 64%),radial-gradient(60% 40% at 55% 24%,rgba(190,160,255,.42),transparent)}
.p5{background:linear-gradient(175deg,#6A4A22,#1E1408 66%),radial-gradient(62% 42% at 45% 28%,rgba(255,205,130,.45),transparent)}
.p6{background:linear-gradient(190deg,#243F5E,#0A1420 62%),radial-gradient(58% 40% at 60% 30%,rgba(150,200,255,.38),transparent)}
.backdrop{background:
  radial-gradient(85% 65% at 66% 24%,rgba(255,178,110,.34),transparent 58%),
  radial-gradient(48% 46% at 26% 32%,rgba(110,170,255,.22),transparent 62%),
  linear-gradient(178deg,#12202F 0%,#152538 40%,#0A1119 100%)}
"""

# ── The five concepts. Only these blocks differ. ──────────────────────────
LOOKS = [
 dict(
  id="l1_obsidian_glass", n="1", name="Obsidian Glass", theme="glass",
  register="Apple TV+",
  tag="Everything is a floating pane of tinted glass over the artwork.",
  why="Separation by MATERIAL. Panels are translucent and blurred, so the "
      "artwork is never fully hidden — the page reads as depth rather than as "
      "boxes. The one accent is cold and used only for the cursor.",
  spec=[("separation","glass · sheet+dialog+card glass, settings rule"),
        ("scrim","blurBand — text sits on a frosted strip, not a gradient"),
        ("artwork","contained · radius 14 · no grading"),
        ("focus","ring + soft bloom, 2.5px cold"),
        ("motion","glide — long decelerations"),
        ("density","standard · sound: soft tick")],
  tv="Blur is the whole identity, so TV gets the opaque recipe: the same "
     "panes at higher fill opacity, no BackdropFilter. Stated as a property, "
     "not a degradation.",
  css="""
:root{--sans:'Inter Tight',-apple-system,sans-serif;--railw:186px;--herow:52%;
 --gut:44px;--herob:44px;--titlesz:44px;--cardw:132px;--cardgap:15px;
 --navgap:3px;--navpad:9px 13px;--railpad:22px 14px;--shelftop:20px;--capgap:12px;
 --ink:#F2F5F8;--dim:rgba(242,245,248,.62);--dim2:rgba(242,245,248,.36);
 --acc:#7FD4FF;--glass:rgba(16,22,30,.52);--hair:rgba(255,255,255,.14)}
body{background:#05070A;color:var(--ink)}
.tv{border-radius:14px;background:#05070A}
.rail{background:var(--glass);backdrop-filter:blur(30px) saturate(150%);
      border-right:1px solid var(--hair)}
.mark{background:rgba(255,255,255,.94);color:#06090D;border-radius:10px}
.nav{color:var(--dim);border-radius:11px}
.nav.on{background:rgba(255,255,255,.13);color:var(--ink);
        backdrop-filter:blur(8px)}
.scrim{background:linear-gradient(90deg,rgba(5,7,10,.15) 0%,transparent 55%)}
.herobody{background:var(--glass);backdrop-filter:blur(26px) saturate(140%);
 border:1px solid var(--hair);border-radius:20px;padding:26px 28px 24px;
 left:calc(var(--gut) - 4px);right:40%;box-shadow:0 26px 70px rgba(0,0,0,.42)}
.eyebrow{color:var(--acc)}
.title{font-weight:600;letter-spacing:-1.2px}
.title em{font-style:normal;font-weight:200;color:var(--dim)}
.badge{background:rgba(255,255,255,.13);border-radius:5px;color:var(--ink)}
.dot{color:var(--dim2)}
.blurb{color:var(--dim)}
button.pri{background:rgba(255,255,255,.95);color:#06090D;border-radius:11px}
button.sec{background:rgba(255,255,255,.11);color:var(--ink);border-radius:11px;
 border:1px solid var(--hair)}
.prog{background:rgba(255,255,255,.16);border-radius:2px}
.prog span{background:var(--acc)}
.shelf h2{color:var(--dim)}
.card .art{border-radius:13px;border:1px solid rgba(255,255,255,.08)}
.cap b{color:var(--ink)}.cap i{color:var(--dim2)}
.card .bar{background:rgba(255,255,255,.14);border-radius:2px}
.card .bar span{background:var(--acc)}
.card.focus .ring{border:2.5px solid var(--acc);border-radius:15px;margin:-4px;
 box-shadow:0 0 0 6px rgba(127,212,255,.16),0 14px 40px rgba(127,212,255,.22)}
.card.sk .art{background:rgba(255,255,255,.07)}
.card.sk .cap b,.card.sk .cap i{background:rgba(255,255,255,.09);border-radius:4px}
.legend div{background:rgba(255,255,255,.045);border:1px solid var(--hair);
 border-radius:12px;color:var(--dim)}
.legend b{color:var(--acc)}
a.back{color:var(--dim)}
h3.pt{color:var(--ink)}p.pd{color:var(--dim)}
"""),

 dict(
  id="l2_deep_field", n="2", name="Deep Field", theme="field",
  register="Netflix",
  tag="No boxes anywhere. Artwork bleeds, and space alone does the separating.",
  why="Separation by SPACE. Nothing has a fill or a border — not the rail, not "
      "the hero, not a card. The eye groups by rhythm and by the vignette, and "
      "the artwork runs to the edge of the screen.",
  spec=[("separation","space · card/shelf/hero bare; settings fall back to rule"),
        ("scrim","bottomGradient + vignette"),
        ("artwork","bleed · hero is the page background · reactiveRoom high"),
        ("focus","scale 1.06 + bloom, no ring"),
        ("motion","settle — spring, slight overshoot"),
        ("density","airy · theater idle")],
  tv="Cheapest concept on TV: no blur, no fills, shadows only around focus. "
     "The vignette is a static gradient. reactiveRoom rides the existing "
     "tvHeroTint wire.",
  css="""
:root{--sans:'Inter Tight',-apple-system,sans-serif;--railw:172px;--herow:56%;
 --gut:54px;--herob:52px;--titlesz:56px;--cardw:138px;--cardgap:20px;
 --navgap:6px;--navpad:8px 4px;--railpad:26px 18px;--shelftop:26px;--capgap:14px;
 --ink:#FFFFFF;--dim:rgba(255,255,255,.66);--dim2:rgba(255,255,255,.38);
 --acc:#E8503A}
body{background:#000;color:var(--ink)}
.tv{border-radius:0;background:#000}
/* the hero art IS the page: it spans the whole frame, BEHIND everything.
   Note this is a z-order and inset change only — the rail, the hero body and
   the shelves stay exactly where the other four concepts put them. */
.hero{left:0;height:100%;z-index:0}
.hero .backdrop{inset:-1px;transform:scale(1.04)}
/* The art spans the frame, but the hero TEXT stays in the band the other
   four concepts put it in — bleeding the artwork must not move the copy. */
.herobody{left:calc(var(--railw) + var(--gut));
 bottom:calc(100% - var(--herow) + 22px);right:44%}
.scrim{background:
  linear-gradient(0deg,#000 0%,rgba(0,0,0,.92) 26%,rgba(0,0,0,.5) 52%,transparent 76%),
  linear-gradient(90deg,rgba(0,0,0,.72) 0%,rgba(0,0,0,.3) 34%,transparent 58%),
  radial-gradient(120% 92% at 50% 42%,transparent 42%,rgba(0,0,0,.62) 100%)}
.rail{background:none;border:0;z-index:5}
.mark{background:var(--acc);color:#fff;border-radius:0;font-size:16px}
.nav{color:var(--dim2);padding:8px 4px}
.nav.on{color:var(--ink);font-weight:600}
.nav.on i{color:var(--acc)}
.herobody{z-index:4;right:44%;bottom:calc(var(--herob) + 2px)}
.eyebrow{color:var(--dim2);letter-spacing:2.6px}
.title{font-weight:800;letter-spacing:-2.4px;text-shadow:0 4px 26px rgba(0,0,0,.6)}
.title em{font-style:normal;font-weight:200}
.badge{background:none;border:1px solid rgba(255,255,255,.34);color:var(--dim);
 border-radius:0}
.dot{color:var(--dim2)}
.blurb{color:var(--dim);max-width:470px}
button.pri{background:#fff;color:#000;border-radius:3px;padding:11px 26px}
button.sec{background:rgba(255,255,255,.18);color:#fff;border-radius:3px;padding:11px 22px}
.prog{background:rgba(255,255,255,.26)}
.prog span{background:var(--acc)}
.shelves{background:linear-gradient(0deg,#000 24%,rgba(0,0,0,.86) 62%,transparent 100%)}
.shelf h2{color:var(--ink);font-weight:700;font-size:14px}
.shelf h2 em{color:var(--dim)}
.card .art{border-radius:3px;transition:none}
.cap b{color:var(--dim)}.cap i{color:var(--dim2)}
.card .bar{background:rgba(255,255,255,.22)}
.card .bar span{background:var(--acc)}
/* focus = the card grows and blooms; no ring at all */
.card.focus{transform:scale(1.075);z-index:6}
.card.focus .art{box-shadow:0 0 0 2px #fff,0 22px 54px rgba(0,0,0,.75),
                 0 0 70px rgba(232,80,58,.3)}
.card.focus .cap b{color:#fff}
.card.sk .art{background:rgba(255,255,255,.06)}
.card.sk .cap b,.card.sk .cap i{background:rgba(255,255,255,.08)}
.legend div{background:none;border-left:2px solid var(--acc);color:var(--dim);
 padding-left:14px}
.legend b{color:var(--ink)}
a.back{color:var(--dim2)}
h3.pt{color:var(--ink)}p.pd{color:var(--dim)}
"""),

 dict(
  id="l3_warm_room", n="3", name="Warm Room", theme="hearth",
  register="a lamp-lit living room",
  tag="Matte, warm and unhurried — the one you leave on at eleven at night.",
  why="Separation by FILL, but a warm matte one with a lit top edge instead of "
      "a border. Nothing is pure black or pure white; artwork fades into the "
      "page rather than sitting in a frame.",
  spec=[("separation","fill · matte + 1px sheen, no hairline borders"),
        ("scrim","plate — a solid warm slab under the text"),
        ("artwork","faded · masked into the ground · warm grade"),
        ("focus","lift — raises with a soft shadow, amber ring"),
        ("motion","glide, tempo 1.15 — everything settles slowly"),
        ("density","generous · dimChrome idle · felt-thud sounds")],
  tv="Shadows are the identity, so TV keeps only the near-hard ones (the "
     "existing shadowFor rule); the sheen is a 1px gradient and costs nothing.",
  css="""
:root{--sans:'Inter Tight',-apple-system,sans-serif;--railw:196px;--herow:52%;
 --gut:50px;--herob:46px;--titlesz:42px;--cardw:140px;--cardgap:19px;
 --navgap:5px;--navpad:11px 14px;--railpad:24px 16px;--shelftop:26px;--capgap:14px;
 --ink:#F6EFE6;--dim:rgba(246,239,230,.66);--dim2:rgba(246,239,230,.4);
 --acc:#E8A13C;--pane:#1D1917;--pane2:#252019;--page:#141110}
body{background:#0C0A09;color:var(--ink)}
.tv{border-radius:16px;background:var(--page)}
.rail{background:var(--pane);border-right:0;
 box-shadow:1px 0 0 rgba(255,255,255,.05),8px 0 30px rgba(0,0,0,.4)}
.mark{background:var(--acc);color:#241703;border-radius:12px}
.nav{color:var(--dim);border-radius:12px}
.nav.on{background:linear-gradient(180deg,rgba(232,161,60,.2),rgba(232,161,60,.12));
 color:var(--ink);box-shadow:inset 0 1px 0 rgba(255,220,170,.22)}
.hero .backdrop{filter:sepia(.32) saturate(1.05) brightness(.92)}
/* artwork FADES into the page instead of ending at an edge */
.scrim{background:
 linear-gradient(0deg,var(--page) 0%,rgba(20,17,16,.86) 22%,rgba(20,17,16,.3) 52%,transparent 74%),
 linear-gradient(90deg,var(--page) 0%,rgba(20,17,16,.55) 30%,transparent 62%)}
.herobody{background:linear-gradient(180deg,rgba(37,32,25,.94),rgba(29,25,23,.97));
 border-radius:18px;padding:24px 26px 22px;right:42%;
 box-shadow:inset 0 1px 0 rgba(255,224,180,.16),0 20px 50px rgba(0,0,0,.5)}
.eyebrow{color:var(--acc)}
.title{font-weight:600;letter-spacing:-.9px}
.title em{font-style:italic;font-weight:300;color:var(--acc)}
.badge{background:rgba(232,161,60,.16);color:#F3C078;border-radius:6px}
.dot{color:var(--dim2)}
.blurb{color:var(--dim)}
button.pri{background:var(--acc);color:#241703;border-radius:12px;
 box-shadow:inset 0 1px 0 rgba(255,232,190,.5),0 6px 18px rgba(232,161,60,.28)}
button.sec{background:var(--pane2);color:var(--ink);border-radius:12px;
 box-shadow:inset 0 1px 0 rgba(255,224,180,.12)}
.prog{background:rgba(246,239,230,.16);border-radius:3px}
.prog span{background:var(--acc)}
.shelf h2{color:var(--dim)}
.card .art{border-radius:12px;
 box-shadow:inset 0 1px 0 rgba(255,224,180,.14),0 8px 22px rgba(0,0,0,.42);
 filter:sepia(.28) saturate(1.04) brightness(.95);
 -webkit-mask-image:linear-gradient(180deg,#000 78%,rgba(0,0,0,.55) 100%);
 mask-image:linear-gradient(180deg,#000 78%,rgba(0,0,0,.55) 100%)}
.cap b{color:var(--ink)}.cap i{color:var(--dim2)}
.card .bar{background:rgba(246,239,230,.16);border-radius:3px}
.card .bar span{background:var(--acc)}
.card.focus{transform:translateY(-7px)}
.card.focus .ring{border:2.5px solid var(--acc);border-radius:14px;margin:-3px;
 box-shadow:0 18px 40px rgba(0,0,0,.6),0 0 30px rgba(232,161,60,.22)}
.card.sk .art{background:var(--pane2);filter:none;box-shadow:inset 0 1px 0 rgba(255,224,180,.1)}
.card.sk .cap b,.card.sk .cap i{background:var(--pane2);border-radius:5px}
.legend div{background:var(--pane);border-radius:12px;color:var(--dim);
 box-shadow:inset 0 1px 0 rgba(255,224,180,.1)}
.legend b{color:var(--acc)}
a.back{color:var(--dim)}
h3.pt{color:var(--ink)}p.pd{color:var(--dim)}
"""),

 dict(
  id="l4_console", n="4", name="Console", theme="console",
  register="an instrument, not a store",
  tag="Hairlines, monospace and hard edges. Focus inverts instead of glowing.",
  why="Separation by RULE. No fills at all — only 1px lines and generous "
      "gutters. Type is mono, everything is square, and the cursor is a "
      "block-invert, the way a terminal shows selection.",
  spec=[("separation","rule · hairlines only; settings capped to rule"),
        ("scrim","plate — a hard-edged black slab"),
        ("artwork","contained · square · no grading (data, not mood)"),
        ("focus","invert — the card flips to ink-on-accent"),
        ("motion","snap — no easing, minimum durations"),
        ("density","dense · scanline skeletons · terminal clicks")],
  tv="Nothing here costs anything on TV: no blur, no shadow, no grading. The "
     "scanline wait state is a repeating linear-gradient, not an animation.",
  css="""
:root{--sans:'JetBrains Mono',ui-monospace,monospace;--railw:180px;--herow:50%;
 --gut:34px;--herob:34px;--titlesz:34px;--cardw:120px;--cardgap:12px;
 --navgap:0px;--navpad:9px 10px;--railpad:18px 12px;--shelftop:16px;--capgap:10px;
 --ink:#D8E0D8;--dim:rgba(216,224,216,.6);--dim2:rgba(216,224,216,.34);
 --acc:#8CE0A8;--hair:rgba(216,224,216,.17)}
body{background:#050706;color:var(--ink)}
.tv{border-radius:0;background:#080B09;border:1px solid var(--hair)}
.rail{background:none;border-right:1px solid var(--hair)}
.mark{background:none;border:1px solid var(--acc);color:var(--acc);border-radius:0}
.nav{color:var(--dim);border-radius:0;font-size:11.5px;letter-spacing:.4px;
 text-transform:uppercase;border-left:2px solid transparent}
.nav.on{color:#050706;background:var(--acc);border-left-color:var(--acc)}
.hero .backdrop{filter:grayscale(1) contrast(1.12) brightness(.62)}
.scrim{background:linear-gradient(90deg,#080B09 0%,rgba(8,11,9,.94) 46%,rgba(8,11,9,.3) 74%,transparent 100%)}
.herobody{right:40%;border-left:2px solid var(--acc);padding-left:16px}
.eyebrow{color:var(--acc);letter-spacing:2.4px}
.title{font-weight:700;letter-spacing:-1px;text-transform:uppercase;font-size:32px}
.title em{font-style:normal;font-weight:300;color:var(--dim)}
.badge{background:none;border:1px solid var(--hair);color:var(--dim);border-radius:0}
.dot{color:var(--dim2)}
.blurb{color:var(--dim);font-size:11.5px;max-width:440px}
button.pri{background:var(--acc);color:#050706;border-radius:0;font-weight:700;
 text-transform:uppercase;letter-spacing:1px;font-size:11.5px}
button.sec{background:none;border:1px solid var(--hair);color:var(--ink);
 border-radius:0;text-transform:uppercase;letter-spacing:1px;font-size:11.5px}
.prog{background:none;border:1px solid var(--hair);height:6px}
.prog span{background:repeating-linear-gradient(90deg,var(--acc) 0 3px,transparent 3px 6px)}
.shelf{border-top:1px solid var(--hair);padding-top:12px;margin-top:8px}
.shelf h2{color:var(--dim);font-size:11px;text-transform:uppercase;letter-spacing:1.8px}
.shelf h2 em{font-style:normal;color:var(--ink)}
.card .art{border-radius:0;border:1px solid var(--hair);
 filter:grayscale(1) contrast(1.1) brightness(.78)}
.cap b{color:var(--dim);font-size:10.5px;font-weight:500}
.cap i{color:var(--dim2);font-size:9.5px}
.card .bar{background:none;border:1px solid var(--hair);height:4px}
.card .bar span{background:var(--acc)}
/* focus INVERTS the whole cell */
.card.focus .art{filter:none;border-color:var(--acc)}
.card.focus .cap{background:var(--acc);padding:6px 6px 5px}
.card.focus .cap b,.card.focus .cap i{color:#050706;font-weight:700}
.card.focus .ring{border:1px solid var(--acc);margin:-4px}
.card.sk .art{background:repeating-linear-gradient(0deg,rgba(216,224,216,.09) 0 2px,transparent 2px 5px);
 filter:none}
.card.sk .cap b,.card.sk .cap i{background:repeating-linear-gradient(0deg,rgba(216,224,216,.1) 0 2px,transparent 2px 5px)}
.legend div{background:none;border:1px solid var(--hair);border-radius:0;color:var(--dim)}
.legend b{color:var(--acc)}
a.back{color:var(--dim)}
h3.pt{color:var(--ink)}p.pd{color:var(--dim)}
"""),

 dict(
  id="l5_midnight_cinema", n="5", name="Midnight Cinema", theme="reel",
  register="a projected print",
  tag="Grain, letterbox bars and a warm grade — the app as a screening room.",
  why="Separation by fill, but the page is a PROJECTION: bars top and bottom, "
      "grain over everything, and every poster warm-graded so the whole board "
      "looks like one print rather than a wall of thumbnails.",
  spec=[("separation","fill · deep matte, hairline rules"),
        ("scrim","plate under a letterboxed frame"),
        ("artwork","matted · warm grade on every image"),
        ("focus","lift + bloom, warm"),
        ("motion","settle, tempo 1.15 — nothing is in a hurry"),
        ("density","cinematic · grain texture · theater idle")],
  tv="Grain is the one thing this look cannot have on TV — the existing "
     "grainFor rule forces it to 0 there, so the TV variant carries the bars, "
     "the grade and the warmth without the speckle.",
  css="""
:root{--sans:'Inter Tight',-apple-system,sans-serif;--railw:184px;--herow:54%;
 --gut:46px;--herob:56px;--titlesz:46px;--cardw:134px;--cardgap:17px;
 --navgap:4px;--navpad:10px 13px;--railpad:34px 15px;--shelftop:22px;--capgap:13px;
 --ink:#EDE4D8;--dim:rgba(237,228,216,.6);--dim2:rgba(237,228,216,.34);
 --acc:#D9A441;--pane:#12100E;--hair:rgba(237,228,216,.11)}
body{background:#070605;color:var(--ink)}
.tv{border-radius:6px;background:#0A0908}
/* the projection: bars top and bottom, grain over the whole frame */
.bars{background:linear-gradient(180deg,#000 0 5.6%,transparent 5.6% 94.4%,#000 94.4% 100%)}
.grain{opacity:.5;mix-blend-mode:overlay;
 background-image:radial-gradient(rgba(255,255,255,.5) .5px,transparent .5px),
                  radial-gradient(rgba(255,255,255,.35) .5px,transparent .5px);
 background-size:3px 3px,5px 5px;background-position:0 0,2px 2px}
.rail{background:var(--pane);border-right:1px solid var(--hair);padding-top:52px}
.mark{background:none;border:1px solid var(--acc);color:var(--acc);border-radius:50%}
.nav{color:var(--dim);border-radius:8px;letter-spacing:.3px}
.nav.on{background:rgba(217,164,65,.13);color:var(--ink)}
.hero .backdrop{filter:sepia(.42) saturate(1.12) contrast(1.06) brightness(.86)}
.scrim{background:
 linear-gradient(0deg,rgba(10,9,8,.96) 0%,rgba(10,9,8,.7) 30%,rgba(10,9,8,.15) 60%,transparent 80%),
 radial-gradient(115% 88% at 50% 40%,transparent 40%,rgba(0,0,0,.6) 100%)}
.herobody{right:42%;background:rgba(10,9,8,.62);padding:22px 24px;
 border-left:2px solid var(--acc)}
.eyebrow{color:var(--acc);letter-spacing:2.8px}
.title{font-weight:300;letter-spacing:-1.4px}
.title em{font-style:italic;font-weight:300;color:var(--acc)}
.badge{background:none;border:1px solid var(--hair);color:var(--dim);border-radius:2px}
.dot{color:var(--dim2)}
.blurb{color:var(--dim);max-width:480px}
button.pri{background:var(--acc);color:#140E03;border-radius:3px;letter-spacing:.6px}
button.sec{background:none;border:1px solid var(--hair);color:var(--ink);border-radius:3px}
.prog{background:rgba(237,228,216,.14)}
.prog span{background:var(--acc)}
.shelf h2{color:var(--dim);letter-spacing:.4px}
.shelf h2 em{font-style:italic;color:var(--ink)}
.card .art{border-radius:3px;padding:0;background-clip:content-box;
 border:5px solid var(--pane);
 filter:sepia(.4) saturate(1.14) contrast(1.05) brightness(.88)}
.cap b{color:var(--ink)}.cap i{color:var(--dim2)}
.card .bar{background:rgba(237,228,216,.14)}
.card .bar span{background:var(--acc)}
.card.focus{transform:translateY(-8px)}
.card.focus .art{filter:sepia(.24) saturate(1.2) brightness(1.02);border-color:#1B1713}
.card.focus .ring{border:2px solid var(--acc);border-radius:5px;margin:-4px;
 box-shadow:0 20px 50px rgba(0,0,0,.7),0 0 44px rgba(217,164,65,.26)}
.card.sk .art{background:#15120F;filter:none;border-color:var(--pane)}
.card.sk .cap b,.card.sk .cap i{background:#15120F;border-radius:2px}
.legend div{background:var(--pane);border:1px solid var(--hair);border-radius:4px;color:var(--dim)}
.legend b{color:var(--acc)}
a.back{color:var(--dim)}
h3.pt{color:var(--ink)}p.pd{color:var(--dim)}
"""),
]

FONTS = ("<link rel='preconnect' href='https://fonts.googleapis.com'>"
 "<link href='https://fonts.googleapis.com/css2?"
 "family=Inter+Tight:wght@200..800&family=JetBrains+Mono:wght@400..700"
 "&display=swap' rel='stylesheet'>")


def page(l):
    rows = "".join(
        f"<div><b>{k}</b>{v}</div>" for k, v in l["spec"])
    return f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{l['n']} · {l['name']} — Premium Looks</title>
{FONTS}
<style>{BASE}{ART}{l['css']}</style></head>
<body>
<a class="back" href="index.html">← all five</a>
<h3 class="pt">{l['n']} · {l['name']} <span style="opacity:.45">·
  {l['register']}</span></h3>
<p class="pd">{l['tag']} <br><br>{l['why']}</p>
{BODY}
<div class="legend">{rows}
<div><b>on tv</b>{l['tv']}</div></div>
{GLYPHS}
</body></html>
"""


INDEX_CSS = """
*{box-sizing:border-box;margin:0;padding:0}
body{background:#060607;color:#EDEDED;font:14px/1.55 'Inter Tight',sans-serif;
     padding:56px 5vw 110px}
h1{font-size:34px;font-weight:600;letter-spacing:-.6px}
h1 em{font-style:normal;font-weight:200;color:rgba(237,237,237,.5)}
.sub{color:rgba(237,237,237,.62);margin:14px 0 10px;max-width:900px;font-size:14px}
.why{color:rgba(237,237,237,.4);font-size:12.5px;max-width:900px;line-height:1.75;
     margin-bottom:46px}
.why b{color:rgba(237,237,237,.68)}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(330px,1fr));
      gap:20px;max-width:1500px}
a.card{display:block;text-decoration:none;color:#EDEDED;border-radius:14px;
  overflow:hidden;border:1px solid rgba(255,255,255,.1);transition:border-color .18s}
a.card:hover{border-color:rgba(255,255,255,.32)}
.thumb{aspect-ratio:16/9;position:relative;overflow:hidden}
.meta{padding:15px 17px 17px}
.k{font:600 9.5px 'JetBrains Mono',monospace;letter-spacing:2.2px;
   color:rgba(237,237,237,.34);text-transform:uppercase}
.meta h2{font-size:19px;font-weight:600;margin:5px 0 6px;letter-spacing:-.3px}
.meta p{color:rgba(237,237,237,.6);font-size:12.5px;line-height:1.5}
.meta .sp{color:rgba(237,237,237,.34);font-size:11px;margin-top:9px;
  font-family:'JetBrains Mono',monospace}
table{border-collapse:collapse;margin:52px 0 0;font-size:12.5px;max-width:1500px;width:100%}
th,td{text-align:left;padding:9px 14px 9px 0;border-bottom:1px solid rgba(255,255,255,.09);
      vertical-align:top}
th{color:rgba(237,237,237,.4);font-weight:600;font-size:10px;letter-spacing:1.6px;
   text-transform:uppercase}
td b{font-weight:600}
"""

# Miniature of each look for the gallery thumbs — same three-zone silhouette
# (rail · hero · shelf) so the differences read at a glance.
THUMBS = {
 "l1_obsidian_glass": """
  background:linear-gradient(150deg,#12202F,#080C12);
  ::rail:background:rgba(255,255,255,.09);border-right:1px solid rgba(255,255,255,.16)
  ::pane:background:rgba(255,255,255,.13);border:1px solid rgba(255,255,255,.2);border-radius:9px
  ::card:background:rgba(255,255,255,.16);border-radius:6px
  ::acc:#7FD4FF""",
 "l2_deep_field": """
  background:radial-gradient(90% 70% at 60% 26%,rgba(255,150,100,.3),transparent 58%),
             linear-gradient(180deg,#101A26,#000 72%);
  ::rail:background:none
  ::pane:background:none
  ::card:background:rgba(255,255,255,.2);border-radius:2px
  ::acc:#E8503A""",
 "l3_warm_room": """
  background:linear-gradient(160deg,#241D16,#141110);
  ::rail:background:#1D1917
  ::pane:background:#252019;border-radius:8px
  ::card:background:#2C2620;border-radius:6px
  ::acc:#E8A13C""",
 "l4_console": """
  background:#080B09;
  ::rail:background:none;border-right:1px solid rgba(216,224,216,.2)
  ::pane:background:none;border-left:2px solid #8CE0A8
  ::card:background:none;border:1px solid rgba(216,224,216,.24)
  ::acc:#8CE0A8""",
 "l5_midnight_cinema": """
  background:linear-gradient(170deg,#1A140E,#0A0908);
  ::rail:background:#12100E;border-right:1px solid rgba(237,228,216,.12)
  ::pane:background:rgba(10,9,8,.6);border-left:2px solid #D9A441
  ::card:background:#1A1512;border-radius:2px;border:3px solid #12100E
  ::acc:#D9A441""",
}


def thumb_css(key, spec):
    bg, rail, pane, card, acc = "", "", "", "", "#fff"
    for part in spec.strip().split("\n"):
        p = part.strip()
        if p.startswith("::rail:"):
            rail = p[7:]
        elif p.startswith("::pane:"):
            pane = p[7:]
        elif p.startswith("::card:"):
            card = p[7:]
        elif p.startswith("::acc:"):
            acc = p[6:]
        elif p:
            bg += p
    return f"""
.t-{key}{{{bg}}}
.t-{key} .r{{position:absolute;left:0;top:0;bottom:0;width:17%;{rail}}}
.t-{key} .h{{position:absolute;left:23%;top:16%;width:40%;height:34%;{pane}}}
.t-{key} .b{{position:absolute;left:23%;top:24%;width:16%;height:5%;background:{acc};border-radius:2px}}
.t-{key} .c{{position:absolute;bottom:11%;height:30%;width:9%;{card}}}
.t-{key} .c1{{left:23%}}.t-{key} .c2{{left:33.5%}}.t-{key} .c3{{left:44%}}
.t-{key} .c4{{left:54.5%}}.t-{key} .c5{{left:65%}}
.t-{key} .c2{{outline:2px solid {acc};outline-offset:2px}}
"""


def index():
    cards, css = "", ""
    for l in LOOKS:
        css += thumb_css(l["id"], THUMBS[l["id"]])
        cards += f"""
  <a class="card" href="{l['id']}.html">
    <div class="thumb t-{l['id']}"><div class="r"></div><div class="h"></div>
      <div class="b"></div><div class="c c1"></div><div class="c c2"></div>
      <div class="c c3"></div><div class="c c4"></div><div class="c c5"></div></div>
    <div class="meta"><div class="k">look {l['n']} · {l['theme']}</div>
      <h2>{l['name']}</h2><p>{l['tag']}</p>
      <div class="sp">{l['spec'][0][1].split(' · ')[0]} · {l['spec'][3][1].split(' — ')[0].split(' + ')[0]} · {l['spec'][4][1].split(' — ')[0]}</div></div>
  </a>"""
    rows = "".join(
        f"<tr><td><b>{l['name']}</b><br><span style='opacity:.45'>{l['theme']}</span></td>"
        + "".join(f"<td>{v}</td>" for _, v in l["spec"]) + "</tr>"
        for l in LOOKS)
    return f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Premium Looks — five concepts</title>
{FONTS}
<style>{INDEX_CSS}{css}</style></head><body>
<h1>Premium Looks <em>— five designed looks, one DOM</em></h1>
<p class="sub">Every concept below renders the <b>identical markup</b> — same
rail, same hero, same three shelves, same focused card, same skeleton row.
Only the stylesheet changes.</p>
<p class="why">That constraint is the experiment. The twenty themes we ship
today came from a mockup that put twenty <b>palettes</b> on one layout, and
palettes are exactly what we got. This round varies the things a palette
cannot reach — <b>separation</b> (how things are told apart), <b>scrim</b>
(how text sits on artwork), <b>artwork treatment</b> (framing and grading),
<b>focus</b> (what the cursor does), <b>motion</b> and <b>density</b>. If
these five read as five different apps with the DOM held fixed, the
vocabulary in <b>design/plans/PREMIUM_LOOKS_PLAN.md §3</b> is the right one. If they
read as one app in five tints, we learned it in week one.</p>
<div class="grid">{cards}</div>
<table><thead><tr><th>look</th><th>separation</th><th>scrim</th>
<th>artwork</th><th>focus</th><th>motion</th><th>density &amp; extras</th></tr></thead>
<tbody>{rows}</tbody></table>
</body></html>
"""


for l in LOOKS:
    with open(os.path.join(OUT, l["id"] + ".html"), "w") as f:
        f.write(page(l))
with open(os.path.join(OUT, "index.html"), "w") as f:
    f.write(index())
print("wrote", len(LOOKS), "looks + index into", OUT)
