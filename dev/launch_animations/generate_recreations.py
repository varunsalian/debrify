"""Recreate Trace, Swiss and Monogram as portable, outlined dotLottie artwork.
Requires fonttools==4.65.0. Uses the repository's bundled variable Inter font.
"""
from pathlib import Path
from math import sin, cos, pi, hypot
import argparse
import base64
import json
import zipfile
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.basePen import BasePen

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
FPS = 60

def clamp(x): return max(0, min(1, x))
def cubic(x): return 1 - (1 - clamp(x)) ** 3
def quint(x): return 1 - (1 - clamp(x)) ** 5
def sine(x): return (1 - cos(pi * clamp(x))) / 2
def lerp(a, b, t): return a + (b - a) * t
def prop(x): return {'a': 0, 'k': x}
def rgb(s): return [int(s[i:i+2], 16) / 255 for i in (0, 2, 4)] + [1]
def fill(c, opacity=100): return {'ty': 'fl', 'c': prop(rgb(c)), 'o': prop(opacity), 'r': 1}
def ellipse(r): return {'ty': 'el', 'd': 1, 'p': prop([0, 0]), 's': prop([r*2, r*2])}
def rect(w, h, center=(0, 0)): return {'ty': 'rc', 'd': 1, 'p': prop(list(center)), 's': prop([w, h]), 'r': prop(0)}

class OutlinePen(BasePen):
    def __init__(self, glyphs=None, scale=1):
        super().__init__(glyphs)
        self.scale = scale
        self.paths = []
    def point(self, p): return [round(p[0]*self.scale, 4), round(-p[1]*self.scale, 4)]
    def _moveTo(self, p):
        self.v, self.ins, self.outs = [self.point(p)], [[0, 0]], [[0, 0]]
    def _lineTo(self, p):
        self.v.append(self.point(p)); self.ins.append([0, 0]); self.outs.append([0, 0])
    def _curveToOne(self, a, b, end):
        a, b, end = self.point(a), self.point(b), self.point(end)
        self.outs[-1] = [a[i]-self.v[-1][i] for i in (0, 1)]
        self.v.append(end); self.ins.append([b[i]-end[i] for i in (0, 1)]); self.outs.append([0, 0])
    def _qCurveToOne(self, control, end):
        start = self._getCurrentPoint()
        a = tuple(start[i]+(control[i]-start[i])*2/3 for i in (0, 1))
        b = tuple(end[i]+(control[i]-end[i])*2/3 for i in (0, 1))
        self._curveToOne(a, b, end)
    def _closePath(self):
        if len(self.v)>1 and self.v[-1] == self.v[0]:
            self.ins[0] = self.ins.pop(); self.v.pop(); self.outs.pop()
        self.paths.append({'ty': 'sh', 'ks': prop({'v': self.v, 'i': self.ins, 'o': self.outs, 'c': True})})
    def _endPath(self): self._closePath()

class Artwork:
    def __init__(self, name, w, h, duration, background, text):
        self.name, self.w, self.h, self.text = name, w, h, text
        self.frames = round(duration*FPS)
        self.background = background
        self.layers, self.assets = [], []
        self.index = 0
    def track(self, fn):
        values = []
        for i in range(self.frames):
            value = fn(i/(self.frames-1))
            if not isinstance(value, list): value = [value]
            values.append([round(v, 4) for v in value])
        if all(v == values[0] for v in values):
            return prop(values[0][0] if len(values[0]) == 1 else values[0])
        indices = [i for i in range(self.frames) if i in (0, self.frames-1)
                   or values[i] != values[i-1] or values[i] != values[i+1]]
        keys = []
        for j, i in enumerate(indices):
            key = {'t': i, 's': values[i]}
            if j < len(indices)-1:
                key.update({'e': values[indices[j+1]], 'o': {'x': .333, 'y': .333}, 'i': {'x': .667, 'y': .667}})
            keys.append(key)
        return {'a': 1, 'k': keys}
    def layer(self, label, shapes, position=(0, 0), opacity=100, scale=100):
        self.index += 1
        pos = self.track(position) if callable(position) else prop([*position, 0])
        op = self.track(opacity) if callable(opacity) else prop(opacity)
        sc = self.track(lambda t: [scale(t), scale(t), 100]) if callable(scale) else prop([scale, scale, 100])
        return {'ddd': 0, 'ind': self.index, 'ty': 4, 'nm': label, 'sr': 1,
                'ks': {'o': op, 'r': prop(0), 'p': pos, 'a': prop([0, 0, 0]), 's': sc},
                'ao': 0, 'shapes': shapes, 'ip': 0, 'op': self.frames, 'st': 0, 'bm': 0}
    def json(self):
        return {'v': '5.7.4', 'fr': FPS, 'ip': 0, 'op': self.frames, 'w': self.w, 'h': self.h,
                'nm': self.name, 'ddd': 0, 'assets': self.assets, 'layers': self.layers}

FONTS = {}
def word(text, weight, size, tracking, maximum):
    if weight not in FONTS:
        FONTS[weight] = instantiateVariableFont(TTFont(REPO/'assets/fonts/Inter-Regular.ttf'), {'wght': weight}, inplace=True)
    font = FONTS[weight]
    glyphs, cmap = font.getGlyphSet(), font.getBestCmap()
    units = font['head'].unitsPerEm
    missing = [ch for ch in text if ord(ch) not in cmap]
    if missing: raise ValueError(f'Font does not contain {missing}')
    widths = [glyphs[cmap[ord(ch)]].width / units * size for ch in text]
    width = sum(widths) + max(0, len(text)-1)*size*tracking
    factor = min(1, maximum/width)
    size *= factor; widths = [v*factor for v in widths]; width *= factor
    letters, left = [], 0
    for ch, advance in zip(text, widths):
        pen = OutlinePen(glyphs, size/units)
        glyphs[cmap[ord(ch)]].draw(pen)
        letters.append((left, advance, pen.paths))
        left += advance + size*tracking
    return letters, width, size

def play(size):
    pts = [(-.30*size, -.40*size), (-.30*size, .40*size), (.43*size, 0)]
    # Use the same rounded triangle construction as identPlayPath.
    pen = OutlinePen()
    for i in range(3):
        a, b, c = pts[i], pts[(i+1)%3], pts[(i+2)%3]
        d1, d2 = hypot(a[0]-b[0], a[1]-b[1]), hypot(c[0]-b[0], c[1]-b[1])
        t1 = tuple(b[j]+(a[j]-b[j])*.14*size/d1 for j in (0, 1))
        t2 = tuple(b[j]+(c[j]-b[j])*.14*size/d2 for j in (0, 1))
        # OutlinePen flips Y; invert input to retain the source geometry.
        flip = lambda p: (p[0], -p[1])
        if i == 0: pen.moveTo(flip(t1))
        else: pen.lineTo(flip(t1))
        pen.qCurveTo(flip(b), flip(t2))
    pen.closePath()
    return pen.paths

def trace(w, h, text):
    a = Artwork('Trace', w, h, 2.4, '06070A', text)
    letters, width, size = word(text, 300, min(h*.105, w*.120), .34, w*(.82 if h>w*1.1 else .72))
    cx, baseline = w/2, h*(.50 if h>w*1.1 else .52)
    rule_y, half = baseline+size*.58, min(width*.58, w*.46)
    left, right, tick = cx-half, cx+half, max(9, width*.045)
    travel = lambda t: sine((t-.02)/.58)
    dot = lambda t: lerp(left, right, travel(t))
    retract = lambda t: quint((t-.66)/.34)
    x0 = lambda t: lerp(left, cx-tick, retract(t))
    x1 = lambda t: lerp(dot(t), cx+tick, retract(t))
    rule = rect(1, max(1, size*.026))
    rule['s'] = a.track(lambda t: [max(.001, x1(t)-x0(t)), max(1, size*.026)])
    a.layers.append(a.layer('Retracting rule', [rule, fill('EFF3FA')],
        lambda t: [(x0(t)+x1(t))/2, rule_y, 0], lambda t: lerp(26,55,retract(t))*clamp(t/.05)))
    for i, (offset, advance, paths) in enumerate(letters):
        centre = cx-width/2+offset+advance/2
        ignition = lambda t, c=centre: clamp((dot(t)-c)/(size*.62))
        a.layers.insert(0, a.layer(f'Letter {i+1}', paths+[fill('EFF3FA')],
            lambda t, x=cx-width/2+offset, k=ignition: [x, baseline+size*.085*(1-cubic(k(t))), 0],
            lambda t, k=ignition: 100*cubic(k(t))))
        a.layers.insert(0, a.layer(f'Ignition flash {i+1}', paths+[fill('FFFFFF')],
            lambda t, x=cx-width/2+offset, k=ignition: [x, baseline+size*.085*(1-cubic(k(t))), 0],
            lambda t, k=ignition: 72*4*k(t)*(1-k(t)) if 4*k(t)*(1-k(t))>.14 else 0))
    for length, opacity in [(1.7,16),(.55,50)]:
        tail_start=lambda t,m=length:max(x0(t),dot(t)-size*m)
        tail=rect(1,max(1,size*.026))
        tail['s']=a.track(lambda t, begin=tail_start:[max(.001,dot(t)-begin(t)),max(1,size*.026)])
        a.layers.insert(0,a.layer('Pulse tail',[tail,fill('FFFFFF')],
            lambda t, begin=tail_start:[(begin(t)+dot(t))/2,rule_y,0],
            lambda t,o=opacity:o*clamp(t/.05) if travel(t)<1 else 0))
    flare = lambda t: clamp((t-.60)/.12)
    radius = lambda t: lerp(max(1.6,size*.048), max(1.6,size*.048)*3.4, cubic(flare(t)))
    for mult, opacity, color in [(3.2,4.5,'9DB2FF'),(2.5,6,'9DB2FF'),(1.9,8.5,'9DB2FF'),(1.45,12,'9DB2FF'),(1.10,18,'9DB2FF'),(.55,100,'FFFFFF')]:
        shape = ellipse(1)
        shape['s'] = a.track(lambda t, m=mult: [radius(t)*m*2]*2)
        a.layers.insert(0, a.layer('Travelling light', [shape,fill(color)], lambda t:[dot(t),rule_y,0],
            lambda t, o=opacity: o*(1-flare(t))*clamp(t/.05)))
    return a

def swiss(w, h, text):
    a = Artwork('Swiss', w, h, 1.8, '000000', text)
    u = min(w/16,h/9); margin=u*1.15
    letters, width, size = word(text,800,u*2.05,-.02,min(w-margin*2-u*2.2,u*11.5))
    sq=u*1.7; sx=w/2-(sq+u*.7+width)/2; start=sx+sq+u*.7
    baseline=h/2+u*.72; ry=h/2+u*.95
    lock=[]
    for i,(offset,advance,paths) in enumerate(letters):
        lock.append(a.layer(f'Rising letter {i+1}',paths+[fill('F2F4F8')],
            lambda t,x=start+offset,j=i:[x,baseline+size*.95*(1-quint((t-(.24+j/max(1,len(letters)-1)*.21))/.34)),0]))
    # Rising block and its black play knockout share the baseline clipping plane.
    pos=lambda t:[sx+sq/2,baseline-sq/2+sq*(1-quint((t-.18)/.32)),0]
    lock += [a.layer('Play knockout',play(sq*.56)+[fill('000000')],pos),a.layer('Vermilion block',[rect(sq,sq),fill('FF3B23')],pos)]
    a.assets.append({'id':'lockup','layers':lock})
    pre=a.layer('Baseline clipping plane',[])
    pre.update({'ty':0,'refId':'lockup','w':w,'h':h})
    del pre['shapes']
    pre['masksProperties']=[{'inv':False,'mode':'a','o':prop(100),'x':prop(0),
        'pt':prop({'v':[[0,0],[w,0],[w,ry],[0,ry]],'i':[[0,0]]*4,'o':[[0,0]]*4,'c':True})}]
    rule=rect(1,max(2,u*.11));rule['s']=a.track(lambda t:[(w-2*margin)*quint(t/.34),max(2,u*.11)])
    a.layers=[a.layer('Vermilion rule',[rule,fill('FF3B23')],lambda t:[margin+(w-2*margin)*quint(t/.34)/2,ry+max(2,u*.11)/2,0]),pre]
    for x in [margin,w-margin]:
        for y in [margin*.55+u*.25,h-margin*.55-u*.25]:
            a.layers.append(a.layer('Registration tick',[rect(1,u*.5),fill('FFFFFF',14)],(x,y)))
    for label, align in [('LAUNCH','left'),('DEBRID · TORRENT · IPTV','right')]:
        glyphs, tw, _ = word(label,600,u*.32,.22,w*.8)
        x=margin+u*.45 if align=='left' else w-margin-u*.45-tw
        y=margin*.55+u*.32 if align=='left' else h-margin*.55
        for off,_,paths in glyphs:
            if paths: a.layers.insert(0,a.layer(label,paths+[fill('F2F4F8',72 if align=='left' else 42)],(x+off,y),lambda t:100 if t>.62 else 0))
    return a

def monogram(w,h,text):
    a=Artwork('Monogram',w,h,2.2,'030309',text)
    cx,cy,r=w/2,h*.42,min(w,h)*.17
    ring=[ellipse(r),{'ty':'st','c':prop(rgb('E9EDFF')),'o':prop(80),'w':prop(1),'lc':2,'lj':2},
          {'ty':'tm','s':prop(0),'e':a.track(lambda t:100*sine(t/.55)),'o':prop(0),'m':1}]
    a.layers.append(a.layer('Drawn ring',ring,(cx,cy)))
    for radius,color,opacity in [(3.4,'818CF8',35),(1.8,'E9EDFF',100)]:
        a.layers.insert(0,a.layer('Ring leading light',[ellipse(radius),fill(color)],
            lambda t:[cx+cos(-pi/2+sine(t/.55)*2*pi)*r,cy+sin(-pi/2+sine(t/.55)*2*pi)*r,0],
            lambda t,o=opacity:o if t<.55 else 0))
    mark=play(r*.74)
    gradient={'ty':'gf','o':prop(100),'r':1,'t':1,'s':prop([-r*.37,0]),'e':prop([r*.37,0]),
              'g':{'p':2,'k':prop([0,*rgb('4F74FF')[:3],1,*rgb('8A5CFF')[:3]])}}
    a.layers.insert(0,a.layer('Breathing play mark',mark+[gradient],(cx,cy),lambda t:100*cubic((t-.34)/.34),lambda t:lerp(92,100,cubic((t-.34)/.34))))
    a.layers.insert(0,a.layer('Mark highlight',play(r*.74*.52)+[fill('DFE6FF',18)],(cx,cy),lambda t:100*cubic((t-.34)/.34),lambda t:lerp(92,100,cubic((t-.34)/.34))))
    letters,width,size=word(text,500,h*.052,1.1,w*.42)
    for i,(off,_,paths) in enumerate(letters):
        a.layers.insert(0,a.layer(f'Caption {i+1}',paths+[fill('AAB1D6',85)],(cx-width/2+off,cy+r+40),lambda t,j=i:100*cubic((t-(.62+j/max(1,len(letters)-1)*.12))/.30)))
    a.layers.insert(0,a.layer('Accent full stop',[ellipse(1.6),fill('818CF8')],(cx,cy+r+62),lambda t:100*clamp((t-.85)/.15)))
    return a

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--text',default='DEBRIFY')
    parser.add_argument('--output',type=Path,default=HERE/'recreations')
    args=parser.parse_args()
    if not args.text.strip() or len(args.text)>24: parser.error('Use 1–24 characters for the main wordmark.')
    args.output.mkdir(parents=True,exist_ok=True)
    for name,make in [('trace',trace),('swiss',swiss),('monogram',monogram)]:
        variants={f'{name}-{orientation}':make(w,h,args.text) for orientation,w,h in [('landscape',960,540),('portrait',540,960)]}
        manifest={'version':'2.0','initial':{'animation':f'{name}-landscape'},'animations':[
            {'id':key,'name':f'{art.name} — {key.split("-")[-1].title()}','background':'#'+art.background} for key,art in variants.items()]}
        target=args.output/f'{name}.lottie'
        with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED) as archive:
            for path,value in [('manifest.json',manifest)]+[(f'a/{key}.json',art.json()) for key,art in variants.items()]:
                info=zipfile.ZipInfo(path,date_time=(2026,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED
                archive.writestr(info,json.dumps(value,separators=(',',':')))
        print(f'{target.name}: {target.stat().st_size:,} bytes')
    # QA-only embedded fixtures, not production assets.
    if args.output.resolve()==(HERE/'recreations').resolve():
        (HERE/'recreation_data.dart').write_text('// Generated by generate_recreations.py. Development only.\nconst recreatedAnimations = <String, String>{\n'+''.join(
            f"  '{p.stem}': '{base64.b64encode(p.read_bytes()).decode()}',\n" for p in sorted(args.output.glob('*.lottie')))+'};\n')

if __name__=='__main__': main()
