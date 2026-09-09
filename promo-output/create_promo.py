import sys, math, subprocess, wave
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'promo-tools'))
import imageio_ffmpeg
OUT=Path(__file__).resolve().parent
W,H,FPS=540,960,24
cream='#F6ECD8'; gold='#D5A564'; dark='#24160F'
fontpath='C:/Windows/Fonts/arial.ttf'
boldpath='C:/Windows/Fonts/arialbd.ttf'
def font(n,b=False): return ImageFont.truetype(boldpath if b else fontpath,n)
photo=Image.open('C:/Users/SLUMDUNK/AppData/Local/Temp/codex-clipboard-dedc0d01-0fd1-4eab-9d3b-fc6fdc9262ec.png').convert('RGB')
def txt(d,y,s,size=40,fill=cream,b=False):
 f=font(size,b); box=d.textbbox((0,0),s,font=f); d.text(((W-(box[2]-box[0]))/2,y),s,font=f,fill=fill)
def cup(d,x,y,scale=1,t=0):
 def box(a,b,c,e):return (x+a*scale,y+b*scale,x+c*scale,y+e*scale)
 d.ellipse(box(-120,100,135,149),fill='#38251B')
 d.ellipse(box(65,-5,145,90),outline=cream,width=12)
 d.rounded_rectangle(box(-105,-20,95,115),radius=int(34*scale),fill=cream)
 d.ellipse(box(-105,-42,95,17),fill='#E6D5B9')
 d.ellipse(box(-93,-33,83,8),fill='#543021')
 d.arc(box(-55,-22,48,2),0,170,fill=gold,width=3)
 for k in range(3):
  pts=[(x+(-48+k*43+9*math.sin(j*.3+t*2+k))*scale,y+(-52-j*3)*scale) for j in range(30)]
  d.line(pts,fill='#AC8C6A',width=3)
def frame(t):
 im=Image.new('RGB',(W,H),dark); d=ImageDraw.Draw(im)
 for j in range(H):
  v=int(8*math.sin(j/H*math.pi)); d.line((0,j,W,j),fill=(36+v,22+v,15+v))
 d.text((35,30),'DAILY BREW',font=font(19,True),fill=gold)
 d.text((405,34),'COFFEE',font=font(13),fill=cream)
 if t<3.5:
  z=1+t*.018; pw=int(490*z); ph=int(pw*photo.height/photo.width)
  p=photo.resize((pw,ph),Image.Resampling.LANCZOS)
  im.paste(p,((W-pw)//2,145-(ph-603)//2)); d=ImageDraw.Draw(im)
  d.rectangle((0,748,W,H),fill=dark)
  txt(d,778,'Antok pa?',57,b=True); txt(d,852,'Kape muna.',28,fill=gold)
 elif t<8:
  txt(d,155,'Good morning.',42,b=True); txt(d,210,'Great coffee.',42,b=True)
  cup(d,268,510+5*math.sin(t),1.4,t)
  txt(d,775,'Simulan ang umaga',29); txt(d,818,'sa sarap ng Daily Brew.',29)
 else:
  txt(d,145,'Sarap sa',47,b=True); txt(d,201,'bawat sip.',47,b=True)
  y=350+int(4*math.sin(t*1.3))
  d.rounded_rectangle((83,y,287,y+305),radius=14,fill='#B67A43')
  d.rectangle((94,y+12,276,y+25),fill='#714727')
  d.rounded_rectangle((106,y+67,264,y+245),radius=4,fill=cream)
  d.text((125,y+92),'DAILY',font=font(30,True),fill=dark)
  d.text((125,y+128),'BREW',font=font(30,True),fill=dark)
  d.text((132,y+190),'COFFEE',font=font(17),fill='#714727')
  cup(d,358,593,.78,t)
  if t<11.5:txt(d,788,'Your daily coffee moment.',25,fill=gold)
  else:
   txt(d,746,'Tara, kape muna!',37,b=True)
   d.rounded_rectangle((110,821,430,885),radius=32,fill=gold)
   txt(d,839,'ORDER YOURS TODAY',19,fill=dark,b=True)
 d.rectangle((35,923,505,926),fill='#624731')
 d.rectangle((35,923,35+int(470*t/15),926),fill=gold)
 d.text((35,937),'CONCEPT AD • FICTIONAL BRAND',font=font(10),fill='#B2987C')
 return im
# Original, synthesized instrumental bed: soft chords and a light melody.
sr=44100; duration=15; a=np.zeros(sr*duration,dtype=np.float64)
for start,notes in [(0,[130.81,164.81,196]),(3.75,[110,130.81,164.81]),(7.5,[87.31,110,130.81]),(11.25,[98,123.47,146.83])]:
 n=int(3.75*sr); q=np.arange(n)/sr; env=np.minimum(q/.15,1)*np.minimum((3.75-q)/.6,1)
 for f in notes:a[int(start*sr):int(start*sr)+n]+=.065*np.sin(2*np.pi*f*q)*env
for i in range(30):
 f=[523.25,659.25,783.99,659.25,587.33,523.25,440,392][i%8]
 n=int(.42*sr); q=np.arange(n)/sr; tone=.07*np.sin(2*np.pi*f*q)*np.exp(-8*q)*np.minimum(q/.012,1)
 a[int(i*.5*sr):int(i*.5*sr)+n]+=tone
a*=np.minimum(np.arange(len(a))/sr,1)*np.minimum((duration-np.arange(len(a))/sr)/1.3,1)
with wave.open(str(OUT/'music.wav'),'wb') as w:
 w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); w.writeframes((a*32767).astype('<i2').tobytes())
ff=imageio_ffmpeg.get_ffmpeg_exe()
p=subprocess.Popen([ff,'-y','-f','rawvideo','-vcodec','rawvideo','-pix_fmt','rgb24','-s','540x960','-r',str(FPS),'-i','-','-i',str(OUT/'music.wav'),'-c:v','libx264','-preset','fast','-crf','20','-pix_fmt','yuv420p','-c:a','aac','-b:a','128k','-shortest','-movflags','+faststart',str(OUT/'daily-brew-promo.mp4')],stdin=subprocess.PIPE,stderr=subprocess.DEVNULL)
for i in range(FPS*duration):p.stdin.write(frame(i/FPS).tobytes())
p.stdin.close(); assert p.wait()==0
frame(12).save(OUT/'preview.jpg')
print(str(OUT/'daily-brew-promo.mp4'))
