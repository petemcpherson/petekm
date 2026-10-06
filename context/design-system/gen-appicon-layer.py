import json,os,sys
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),"..",".."))
G=json.load(open(os.path.join(ROOT,"context/design-system/assets/robopete.grid.json")))
rows=[y for y,r in enumerate(G) if any(c in "#B" for c in r)]
cols=[x for x in range(len(G[0])) if any(r[x] in "#B" for r in G)]
Y0,Y1=min(rows),max(rows); X0,X1=min(cols),max(cols)
# target: at a 256px icon render, cell = 6px on an integer origin.
# system draws the 1024 layer canvas into the 824/1024 content box.
K = 512/103.0          # source px per output px at S=256
CELL_OUT = 6
OX_OUT, OY_OUT = 25, 16
u  = CELL_OUT*K
ox = OX_OUT*K
oy = OY_OUT*K
parts=[f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024" shape-rendering="crispEdges">']
# merge horizontal runs to keep the file small and seam-free
for gy in range(Y0,Y1+1):
    row=G[gy]; gx=X0
    while gx<=X1:
        if row[gx] in "#B":
            st=gx
            while gx<=X1 and row[gx] in "#B": gx+=1
            x=ox+(st-X0)*u; y=oy+(gy-Y0)*u; w=(gx-st)*u
            parts.append(f'<rect x="{x:.4f}" y="{y:.4f}" width="{w:.4f}" height="{u:.4f}" fill="#0A5CFF"/>')
        else: gx+=1
parts.append('</svg>')
open(sys.argv[1],'w').write(''.join(parts))
print('svg art box', 26*u, 29*u, 'origin', ox, oy)
