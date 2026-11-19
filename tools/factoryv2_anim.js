// ---------------------------------------------------------------- movement: packages on the chains, ore on the belts, drones in the air
const BG=document.createElement("canvas"),T0=performance.now();
function snap(){BG.width=cv.width;BG.height=cv.height;BG.getContext("2d").drawImage(cv,0,0)}
const MV=(D.movers||[]).map(m=>{const P=m.p.map(q=>q.slice());if(m.loop)P.push(P[0]);const L=[0];
  for(let i=1;i<P.length;i++){const a=P[i-1],b=P[i];L.push(L[i-1]+Math.hypot(b[0]-a[0],b[1]-a[1],b[2]-a[2]))}
  return Object.assign({},m,{P,L,len:L[L.length-1]||1})});
function mvAt(m,d){d=((d%m.len)+m.len)%m.len;let i=1;while(i<m.L.length-1&&m.L[i]<d)i++;
  const a=m.P[i-1],b=m.P[i],t=(d-m.L[i-1])/((m.L[i]-m.L[i-1])||1);return[a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t]}
function movers(){if(!MV.length||!BG.width)return;const g=cv.getContext("2d");
  g.setTransform(1,0,0,1,0,0);g.globalAlpha=1;g.drawImage(BG,0,0);g.imageSmoothingEnabled=false;
  const dpr=Math.min(2,window.devicePixelRatio||1),W=cv.clientWidth,H=cv.clientHeight,z=V.zoom*dpr,ox=W*dpr/2+V.px*dpr,oy=H*dpr/2+V.py*dpr,r=V.rot;
  const Pj=(x,y,zz)=>[(x-zz)*HW,(x+zz)*HH-y*BH];
  const fq=(img,o,pu,pv)=>{g.setTransform(z*(pu[0]-o[0])/16,z*(pu[1]-o[1])/16,z*(pv[0]-o[0])/16,z*(pv[1]-o[1])/16,ox+z*o[0],oy+z*o[1]);g.drawImage(img,0,0,16,16,-.05,-.05,16.1,16.1)};
  const t=(performance.now()-T0)/1000,top=[6,15,99][O.lvl|0],items=[];
  for(const m of MV){if(O.out!==!!m.out)continue;
    for(let k=0;k<m.n;k++){const p=mvAt(m,t*m.v+k*m.len/m.n);if(!O.out){const L=O.lvl|0;if(p[1]>=top||(L==2&&p[1]<15)||(L==1&&p[1]<6&&p[0]<27))continue}
      if(TY[m.t].k=="drone")p[1]+=Math.sin(t*3+k*2)*.15;
      const[xv,zv]=rotXZ(p[0]+.5-V.cx,p[2]+.5-V.cz,r);items.push([xv,zv,p[1],m])}}
  items.sort((a,b)=>(a[0]+a[1])-(b[0]+b[1])||a[2]-b[2]);
  for(const[xv,zv,y,m]of items){const s=m.s,x0=xv-s/2,x1=xv+s/2,z0=zv-s/2,z1=zv+s/2,y0=y,y1=y+s,tx=TX[m.t],d=TY[m.t].k=="drone";
    if(d){g.setTransform(1,0,0,1,0,0);const c=Pj(xv,y0-.05,zv);g.fillStyle="rgba(120,220,255,.55)";g.beginPath();g.ellipse(ox+z*c[0],oy+z*c[1],z*HW*.28,z*HH*.28,0,0,7);g.fill()}
    fq(tx.side.l,Pj(x0,y1,z1),Pj(x1,y1,z1),Pj(x0,y0,z1));
    fq((d?tx.front:tx.side).r,Pj(x1,y1,z1),Pj(x1,y1,z0),Pj(x1,y0,z1));
    fq(tx.top.top,Pj(x0,y1,z0),Pj(x1,y1,z0),Pj(x0,y1,z1))}
  g.setTransform(1,0,0,1,0,0)}
setInterval(()=>{if(!raf&&!document.hidden)movers()},66);
