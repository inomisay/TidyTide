from PIL import Image, ImageDraw, ImageFilter
import math
S=1024
img=Image.new("RGBA",(S,S),(0,0,0,0))
# diagonal gradient
grad=Image.new("RGBA",(S,S))
a=(10,77,124); b=(79,195,232)
px=grad.load()
for y in range(S):
    for x in range(S):
        t=(x+y)/(2*S)
        px[x,y]=tuple(int(a[i]+(b[i]-a[i])*(1-t)) for i in range(3))+(255,)
mask=Image.new("L",(S,S),0)
ImageDraw.Draw(mask).rounded_rectangle((40,40,S-40,S-40),radius=230,fill=255)
img.paste(grad,(0,0),mask)
d=ImageDraw.Draw(img)
def wave(y,amp,width,alpha):
    pts=[(x, y+amp*math.sin((x-80)/S*2*math.pi*1.3)) for x in range(110,S-110,4)]
    top=[(x,y0-width/2) for x,y0 in pts]; bot=[(x,y0+width/2) for x,y0 in reversed(pts)]
    d.polygon(top+bot,fill=(255,255,255,alpha))
    for p in (pts[0],pts[-1]):
        r=width/2; d.ellipse((p[0]-r,p[1]-r,p[0]+r,p[1]+r),fill=(255,255,255,alpha))
wave(560,60,70,255)
wave(720,50,56,150)
for (cx,cy,r) in [(700,300,62),(820,210,34),(560,230,26)]:
    d.ellipse((cx-r,cy-r,cx+r,cy+r),outline=(255,255,255,230),width=18)
img=img.filter(ImageFilter.SMOOTH)
img=img.resize((256,256),Image.LANCZOS)
img.save("../app/TidyTide.ico",sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])
img.save("../assets/icon.png")
