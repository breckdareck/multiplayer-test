#!/usr/bin/env python
"""Generate a standalone HTML map-blueprint viewer that renders layouts using the
REAL Country-village tileset + props (cropped via <canvas>), so the layouts can be
copied tile-for-tile when painting in Godot.

Run:  python tools/gen_country_blueprints.py
Out:  docs/country_map_blueprints.html
"""
import base64, os, json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACK = os.path.join(ROOT, "assets/sprites/Country-village_asset_pack")
TILESET = os.path.join(PACK, "1_Tileset & props/country village tileset.png")
PROPS   = os.path.join(PACK, "1_Tileset & props/Country_village_props.png")
PARALLAX= os.path.join(PACK, "2_Parallax background/Country.png")
OUT     = os.path.join(ROOT, "docs/country_map_blueprints.html")

def b64(p):
    with open(p, "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()

# --- Atlas tile picks (col,row) in the 30x11 tileset -------------------------
# Solid 3-wide grass-topped platform body lives at cols17-19, rows5-7.
T = {
    "grassL": [17,5], "grassM": [18,5], "grassR": [19,5],
    "dirtL":  [17,6], "dirtM":  [18,6], "dirtR":  [19,6],
    "pillarTop":[21,5], "pillarBody":[21,7],
}
# Multi-tile decorative stamps: (atlas_col, atlas_row, w, h)
STAMPS = {
    "diamond": [1,4,7,7],   # big hollow earth diamond
    "cave":    [9,0,4,4],   # tunnel mouth
    "bblock":  [9,5,3,5],   # thick double-decker floating chunk
}
# Props bounding boxes in px (sx,sy,sw,sh) on the props sheet
PROPS_RECT = {
    "bigtree":  [0,0,112,128],
    "smalltree":[128,16,64,112],
    "cottage":  [208,16,112,112],
    "stall":    [208,144,96,48],
    "bush":     [32,176,64,16],
}

# --- Layout data. Platforms: {x,y,w,depth}; y = row of the GRASS TOP. ---------
# Connectors: {x, y1, y2, kind:"rope"|"jump"}. Props: {kind,x,baseY}.
# Markers: {kind:"spawn"|"portal"|"boss"|"mob", x, y, label?}
LAYOUTS = [
 {
  "name":"1 · Meadow Path",
  "sub":"Beginner lane · lv 1-5 · bot-friendly (no ropes, flat)",
  "W":44,"H":18,
  "platforms":[{"x":0,"y":14,"w":44,"depth":4}],
  "connectors":[],
  "stamps":[],
  "props":[{"kind":"bigtree","x":6,"baseY":14},{"kind":"smalltree","x":22,"baseY":14},
           {"kind":"cottage","x":36,"baseY":14},{"kind":"bush","x":15,"baseY":14},
           {"kind":"bush","x":29,"baseY":14}],
  "markers":[{"kind":"spawn","x":2,"y":13},
             {"kind":"mob","x":10,"y":13},{"kind":"mob","x":18,"y":13},
             {"kind":"mob","x":26,"y":13},{"kind":"mob","x":32,"y":13},
             {"kind":"portal","x":42,"y":12}],
  "notes":"Single flat floor, ~44 tiles. Zero traversal failure — ideal for the guided lv1 journey and for bots to farm. Trees/cottage are pure parallax dressing."
 },
 {
  "name":"2 · Three Terraces",
  "sub":"Classic stacked grind map · lv 5-12 · ROPE-connected (MapleStory style)",
  "W":40,"H":18,
  "platforms":[{"x":0,"y":15,"w":40,"depth":3},
               {"x":5,"y":11,"w":30,"depth":1},
               {"x":10,"y":7,"w":22,"depth":1}],
  "connectors":[{"x":7,"y1":15,"y2":11,"kind":"rope"},
                {"x":31,"y1":15,"y2":11,"kind":"rope"},
                {"x":12,"y1":11,"y2":7,"kind":"rope"},
                {"x":29,"y1":11,"y2":7,"kind":"rope"}],
  "stamps":[],
  "props":[{"kind":"smalltree","x":1,"baseY":15},{"kind":"bush","x":20,"baseY":15},
           {"kind":"bush","x":16,"baseY":11}],
  "markers":[{"kind":"spawn","x":2,"y":14},
             {"kind":"mob","x":12,"y":14},{"kind":"mob","x":24,"y":14},
             {"kind":"mob","x":14,"y":10},{"kind":"mob","x":26,"y":10},
             {"kind":"mob","x":18,"y":6},
             {"kind":"portal","x":37,"y":13}],
  "notes":"Tiers are 4 tiles apart → too high to jump (apex is ~1.8 tiles), so they're linked by ROPES at both ends. Players sweep up-and-over. NOT bot-friendly until rope nav lands — flag it."
 },
 {
  "name":"3 · The Hollow",
  "sub":"Cave-mouth boss arena · lv 12-20 · open center for telegraphs",
  "W":36,"H":18,
  "platforms":[{"x":0,"y":14,"w":36,"depth":4},
               {"x":3,"y":10,"w":7,"depth":1},
               {"x":26,"y":10,"w":7,"depth":1}],
  "connectors":[{"x":5,"y1":14,"y2":10,"kind":"rope"},
                {"x":31,"y1":14,"y2":10,"kind":"rope"}],
  "stamps":[{"kind":"cave","x":1,"y":0},{"kind":"cave","x":31,"y":0}],
  "props":[{"kind":"bush","x":13,"baseY":14},{"kind":"bush","x":21,"baseY":14}],
  "markers":[{"kind":"spawn","x":2,"y":13},
             {"kind":"boss","x":16,"y":13,"label":"BOSS — open lane (slam = jumpable band)"},
             {"kind":"portal","x":34,"y":12}],
  "notes":"Bowl arena: open center floor so the boss slam (a horizontal band) is cleared by jumping. Side shelves give ranged players an angle, reached by ropes. Cave mouths frame the back wall."
 },
 {
  "name":"4 · Hillside Village",
  "sub":"Town hub / safe map · cottages + market stall, low jumpable steps",
  "W":40,"H":18,
  "platforms":[{"x":0,"y":14,"w":40,"depth":4},
               {"x":15,"y":13,"w":9,"depth":1}],
  "connectors":[{"x":15,"y1":14,"y2":13,"kind":"jump"}],
  "stamps":[],
  "props":[{"kind":"cottage","x":3,"baseY":14},{"kind":"cottage","x":31,"baseY":14},
           {"kind":"stall","x":18,"baseY":13},{"kind":"bigtree","x":11,"baseY":14},
           {"kind":"bush","x":25,"baseY":14}],
  "markers":[{"kind":"spawn","x":9,"y":13},
             {"kind":"portal","x":1,"y":12,"label":"→ Meadow"},
             {"kind":"portal","x":20,"y":11,"label":"→ Terraces"},
             {"kind":"portal","x":38,"y":12,"label":"→ Hollow"}],
  "notes":"Pure social hub — every step is 1 tile so it's walkable with no precise jumps. The porch terrace is a single jumpable step. Fan portals out to the hunting maps. No killzone/hazards."
 },
]

html = f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Country Tileset — Map Blueprints</title>
<style>
  :root{{--bg:#11151c;--panel:#1a212c;--ink:#e8eef5;--mut:#8da2b8;--acc:#7bd88f;--line:#2c3848;}}
  *{{box-sizing:border-box}}
  body{{margin:0;background:var(--bg);color:var(--ink);font:14px/1.5 'Segoe UI',system-ui,sans-serif}}
  header{{padding:22px 28px;border-bottom:1px solid var(--line);background:linear-gradient(180deg,#1c2530,#141a22)}}
  h1{{margin:0 0 4px;font-size:22px}}
  header p{{margin:0;color:var(--mut)}}
  .wrap{{padding:20px 28px;max-width:1500px;margin:0 auto}}
  .tabs{{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:16px}}
  .tab{{padding:8px 14px;border:1px solid var(--line);border-radius:8px;background:var(--panel);
        color:var(--ink);cursor:pointer;font-size:13px}}
  .tab.active{{border-color:var(--acc);color:var(--acc);box-shadow:0 0 0 1px var(--acc) inset}}
  .map{{display:none}}
  .map.active{{display:block}}
  .maphead{{margin:0 0 4px;font-size:18px;color:var(--acc)}}
  .mapsub{{margin:0 0 12px;color:var(--mut);font-size:13px}}
  .stage{{position:relative;border:1px solid var(--line);border-radius:10px;overflow:auto;
          background:#0c0f14;padding:0}}
  canvas{{display:block;image-rendering:pixelated}}
  .hud{{position:sticky;left:0;display:inline-block;margin:8px;padding:4px 10px;border-radius:6px;
        background:#0009;color:var(--acc);font:12px/1 ui-monospace,Consolas,monospace}}
  .ctl{{display:flex;gap:14px;align-items:center;margin:10px 0;color:var(--mut);font-size:13px;flex-wrap:wrap}}
  .ctl label{{display:flex;gap:6px;align-items:center;cursor:pointer}}
  .notes{{margin:14px 0;padding:12px 14px;border-left:3px solid var(--acc);background:#161d27;border-radius:0 8px 8px 0}}
  .legend{{display:flex;gap:16px;flex-wrap:wrap;margin-top:10px;color:var(--mut);font-size:12px}}
  .legend span{{display:flex;gap:6px;align-items:center}}
  .sw{{width:14px;height:14px;border-radius:3px;display:inline-block;border:1px solid #0006}}
  .atlas-note{{margin-top:24px;padding:14px;border:1px dashed var(--line);border-radius:8px;color:var(--mut);font-size:12px}}
  code{{background:#0c1118;padding:1px 6px;border-radius:4px;color:var(--acc)}}
</style></head>
<body>
<header>
  <h1>Country Tileset — Map Blueprints</h1>
  <p>Rendered with the real <code>country village tileset.png</code> + props. 16px tiles · jump apex ≈ 1.8 tiles. Hover a cell for its grid + atlas coord.</p>
</header>
<div class="wrap">
  <div class="tabs" id="tabs"></div>
  <div id="maps"></div>

  <div class="atlas-note">
    <b>Tile-painting key (atlas col,row in the single TileSetAtlasSource):</b><br>
    Platform grass top → left <code>(17,5)</code> · mid <code>(18,5)</code> · right <code>(19,5)</code> &nbsp;|&nbsp;
    dirt body below → <code>(17,6)/(18,6)/(19,6)</code> (repeat down).<br>
    Pillar → top <code>(21,5)</code>, body <code>(21,7)</code> &nbsp;|&nbsp;
    Cave mouth → block <code>(9,0)</code> 4×4 &nbsp;|&nbsp;
    Earth diamond → block <code>(1,4)</code> 7×7 &nbsp;|&nbsp;
    Thick floating chunk → block <code>(9,5)</code> 3×5.<br>
    Ropes/ladders aren't in this tileset — use your existing rope scene; markers show where they go.
  </div>
</div>

<script>
const TILE=16, SCALE=3;
const T={json.dumps(T)};
const STAMPS={json.dumps(STAMPS)};
const PROPS_RECT={json.dumps(PROPS_RECT)};
const LAYOUTS={json.dumps(LAYOUTS)};
const tilesetImg=new Image(); tilesetImg.src="{b64(TILESET)}";
const propsImg=new Image();   propsImg.src="{b64(PROPS)}";
const bgImg=new Image();      bgImg.src="{b64(PARALLAX)}";

const MARK={{
  spawn:{{c:'#4ea8ff',t:'P'}}, portal:{{c:'#c08bff',t:'⭿'}},
  boss:{{c:'#ff5d6c',t:'B'}},  mob:{{c:'#ffd34e',t:'m'}}
}};
let showGrid=true, showRuler=true;

function blit(ctx,acx,acy,dcx,dcy){{
  ctx.drawImage(tilesetImg, acx*TILE,acy*TILE,TILE,TILE,
    dcx*TILE*SCALE,dcy*TILE*SCALE,TILE*SCALE,TILE*SCALE);
}}
function stamp(ctx,s,dx,dy){{
  for(let j=0;j<s[3];j++)for(let i=0;i<s[2];i++)
    blit(ctx,s[0]+i,s[1]+j,dx+i,dy+j);
}}
function drawMap(m){{
  const cv=document.getElementById('cv-'+m.id), ctx=cv.getContext('2d');
  cv.width=m.W*TILE*SCALE; cv.height=m.H*TILE*SCALE;
  ctx.imageSmoothingEnabled=false;
  // parallax bg (cover)
  const r=Math.max(cv.width/bgImg.width, cv.height/bgImg.height);
  const bw=bgImg.width*r, bh=bgImg.height*r;
  ctx.drawImage(bgImg,0,cv.height-bh,bw,bh);
  ctx.fillStyle='rgba(12,15,20,.30)'; ctx.fillRect(0,0,cv.width,cv.height);
  // stamps (background mass) first
  (m.stamps||[]).forEach(s=>stamp(ctx,STAMPS[s.kind],s.x,s.y));
  // platforms
  m.platforms.forEach(p=>{{
    for(let c=0;c<p.w;c++){{
      const col=p.x+c;
      const top = c===0?T.grassL : c===p.w-1?T.grassR : T.grassM;
      blit(ctx,top[0],top[1],col,p.y);
      for(let d=1;d<p.depth;d++){{
        const b = c===0?T.dirtL : c===p.w-1?T.dirtR : T.dirtM;
        blit(ctx,b[0],b[1],col,p.y+d);
      }}
    }}
  }});
  // props (bottom sits on baseY top edge)
  (m.props||[]).forEach(pr=>{{
    const r=PROPS_RECT[pr.kind];
    const dx=pr.x*TILE*SCALE, dy=pr.baseY*TILE*SCALE - r[3]*SCALE;
    ctx.drawImage(propsImg,r[0],r[1],r[2],r[3],dx,dy,r[2]*SCALE,r[3]*SCALE);
  }});
  // connectors (ropes / jump arrows)
  (m.connectors||[]).forEach(cn=>{{
    const x=(cn.x+0.5)*TILE*SCALE, y1=cn.y1*TILE*SCALE, y2=cn.y2*TILE*SCALE;
    if(cn.kind==='rope'){{
      ctx.strokeStyle='#caa15a'; ctx.lineWidth=3; ctx.setLineDash([6,5]);
      ctx.beginPath(); ctx.moveTo(x,y2); ctx.lineTo(x,y1); ctx.stroke(); ctx.setLineDash([]);
      ctx.fillStyle='#caa15a'; ctx.font='bold 13px monospace';
      ctx.fillText('rope', x+6, (y1+y2)/2);
    }} else {{ // jump step
      ctx.strokeStyle='#7bd88f'; ctx.lineWidth=2;
      ctx.beginPath(); ctx.moveTo(x,y1); ctx.lineTo(x,y2); ctx.stroke();
      ctx.fillStyle='#7bd88f'; ctx.font='bold 12px monospace'; ctx.fillText('↥jump', x+5,(y1+y2)/2);
    }}
  }});
  // grid + ruler
  if(showGrid){{
    ctx.strokeStyle='rgba(255,255,255,.06)'; ctx.lineWidth=1;
    for(let x=0;x<=m.W;x++){{ctx.beginPath();ctx.moveTo(x*TILE*SCALE,0);ctx.lineTo(x*TILE*SCALE,cv.height);ctx.stroke();}}
    for(let y=0;y<=m.H;y++){{ctx.beginPath();ctx.moveTo(0,y*TILE*SCALE);ctx.lineTo(cv.width,y*TILE*SCALE);ctx.stroke();}}
  }}
  if(showRuler){{
    ctx.fillStyle='rgba(123,216,143,.55)'; ctx.font='10px monospace';
    for(let x=0;x<m.W;x+=5) ctx.fillText(x, x*TILE*SCALE+2, 10);
    for(let y=0;y<m.H;y+=5) ctx.fillText(y, 2, y*TILE*SCALE+10);
  }}
  // markers
  m.markers.forEach(mk=>{{
    const d=MARK[mk.kind], x=mk.x*TILE*SCALE, y=mk.y*TILE*SCALE, s=TILE*SCALE;
    ctx.fillStyle=d.c+'55'; ctx.fillRect(x,y,s,s);
    ctx.strokeStyle=d.c; ctx.lineWidth=2; ctx.strokeRect(x,y,s,s);
    ctx.fillStyle=d.c; ctx.font='bold '+(s*0.6)+'px monospace';
    ctx.textAlign='center'; ctx.textBaseline='middle';
    ctx.fillText(d.t, x+s/2, y+s/2); ctx.textAlign='left'; ctx.textBaseline='alphabetic';
    if(mk.label){{ctx.fillStyle=d.c; ctx.font='12px monospace'; ctx.fillText(mk.label, x+s+4, y+s*0.6);}}
  }});
}}

function build(){{
  const tabs=document.getElementById('tabs'), maps=document.getElementById('maps');
  LAYOUTS.forEach((m,i)=>{{
    m.id=i;
    const tb=document.createElement('div'); tb.className='tab'+(i===0?' active':'');
    tb.textContent=m.name; tb.onclick=()=>select(i); tabs.appendChild(tb);
    const wrap=document.createElement('div'); wrap.className='map'+(i===0?' active':''); wrap.id='map-'+i;
    wrap.innerHTML=`
      <h2 class="maphead">${{m.name}}</h2>
      <p class="mapsub">${{m.sub}} · ${{m.W}}×${{m.H}} tiles</p>
      <div class="ctl">
        <label><input type="checkbox" id="g-${{i}}" checked> grid</label>
        <label><input type="checkbox" id="r-${{i}}" checked> ruler</label>
        <span class="hud" id="hud-${{i}}">cell —</span>
      </div>
      <div class="stage"><canvas id="cv-${{i}}"></canvas></div>
      <div class="notes">${{m.notes}}</div>
      <div class="legend">
        <span><i class="sw" style="background:#4ea8ff"></i>P spawn</span>
        <span><i class="sw" style="background:#c08bff"></i>portal</span>
        <span><i class="sw" style="background:#ff5d6c"></i>boss</span>
        <span><i class="sw" style="background:#ffd34e"></i>mob</span>
        <span><i class="sw" style="background:#caa15a"></i>rope (use rope scene)</span>
        <span><i class="sw" style="background:#7bd88f"></i>jumpable step (≤1.5 tiles)</span>
      </div>`;
    maps.appendChild(wrap);
  }});
}}
function select(i){{
  document.querySelectorAll('.tab').forEach((t,j)=>t.classList.toggle('active',j===i));
  document.querySelectorAll('.map').forEach((t,j)=>t.classList.toggle('active',j===i));
}}
function wire(){{
  LAYOUTS.forEach(m=>{{
    document.getElementById('g-'+m.id).onchange=e=>{{showGrid=e.target.checked;drawMap(m);}};
    document.getElementById('r-'+m.id).onchange=e=>{{showRuler=e.target.checked;drawMap(m);}};
    const cv=document.getElementById('cv-'+m.id), hud=document.getElementById('hud-'+m.id);
    cv.addEventListener('mousemove',e=>{{
      const b=cv.getBoundingClientRect();
      const cx=Math.floor((e.clientX-b.left)/b.width*m.W);
      const cy=Math.floor((e.clientY-b.top)/b.height*m.H);
      hud.textContent=`cell (${{cx}}, ${{cy}})  ·  px (${{cx*16}}, ${{cy*16}})`;
    }});
    cv.addEventListener('mouseleave',()=>hud.textContent='cell —');
  }});
}}
let loaded=0;
function ready(){{ if(++loaded<3) return; build(); LAYOUTS.forEach(drawMap); wire(); }}
tilesetImg.onload=ready; propsImg.onload=ready; bgImg.onload=ready;
</script>
</body></html>
"""

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8") as f:
    f.write(html)
print("wrote", OUT, "(%.0f KB)" % (os.path.getsize(OUT)/1024))
