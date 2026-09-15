#include <flutter/runtime_effect.glsl>
uniform float time;
uniform vec2 resolution;
uniform float aspect;
uniform sampler2D scene;
out vec4 fragColor;
void main(){
 vec2 p=FlutterFragCoord().xy / resolution;float screen=resolution.x/resolution.y;
 vec2 crop=screen>aspect?vec2(1.,aspect/screen):vec2(screen/aspect,1.);
 vec2 q=(p-.5)*crop+.5;float horizon=.471;vec2 st=q;
 float sea=smoothstep(horizon,horizon+.014,q.y);float d=max(0.,(q.y-horizon)/(1.-horizon));
 float swell=sin(d*23.-time*.65+q.x*7.0);float swell2=sin(d*39.-time*.43-q.x*11.);
 st.x+=sea*pow(d,1.1)*(.008*swell+.003*swell2);
 st.y+=sea*pow(d,.85)*(.013*swell+.0045*sin(d*51.-time*.8+q.x*14.));
 // Slow cloud advection, feathered to keep the moon and horizon stationary.
 float sky=1.-smoothstep(horizon-.06,horizon,q.y);
 float moonLock=smoothstep(.045,.15,length((q-vec2(.68,.16))*vec2(1.,.57)));
 st.x+=sky*moonLock*.025*sin(time*.09);
 st.y+=sky*moonLock*.003*sin(q.x*9.+time*.09);
 vec3 color=texture(scene,clamp(st,.001,.999)).rgb;
 float silver=exp(-pow((q.x-.68)/(.035+d*.18),2.));
 float glint=sin(d*170.-time*.8+sin(q.x*80.+time*.13)*2.);
 color*=1.+sea*silver*(.10*glint+.06*sin(time*.48+d*40.));
 fragColor=vec4(color,1.);
}
