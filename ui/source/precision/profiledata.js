// Firmware-accurate pressure profiles, ported from the design handoff
// (shared.jsx PROFILES / PROFILES_REFERENCE). pts = setpoint vertices
// [seconds, bar]; phases carry engineering detail + a [start,end] time band.
.pragma library

var PROFILES = [
  {
    name: "Standard 9-bar", peak: "9 bar", tag: "medium / dark · everyday",
    desc: "Gentle wet, climb to 9 bar, hold",
    aim: "Classic balanced espresso — body, crema, the usual.",
    grind: "Normal espresso grind. ~1:2 in 25–35 s.",
    pts: [[0,0],[0.5,1],[6,1],[16,9],[28,9]],
    phases: [
      { name:"PREINFUSE", target:"1.0 bar", ramp:"2.0 bar/s in", exit:"first drips (≥1 g) — or 10 s cap", band:[0,6] },
      { name:"RAMP", target:"9.0 bar", ramp:"0.8 bar/s", exit:"setpoint reaches 9 bar", band:[6,16] },
      { name:"HOLD", target:"9.0 bar", ramp:"—", exit:"user STOP / pot takeover", band:[16,28] }
    ]
  },
  {
    name: "Gentle & Sweet", peak: "6 bar", tag: "light–medium · sweeter",
    desc: "Same wet, then a flat 6 bar hold",
    aim: "Softer, sweeter, less channeling on fragile pucks.",
    grind: "Coarser than standard — 6 bar flows slower; fine grind will choke it.",
    pts: [[0,0],[0.5,1],[6,1],[12.25,6],[24,6]],
    phases: [
      { name:"PREINFUSE", target:"1.0 bar", ramp:"2.0 bar/s in", exit:"first drips (≥1 g) — or 10 s cap", band:[0,6] },
      { name:"RAMP", target:"6.0 bar", ramp:"0.8 bar/s", exit:"setpoint reaches 6 bar", band:[6,12.25] },
      { name:"HOLD", target:"6.0 bar", ramp:"—", exit:"user STOP / pot takeover", band:[12.25,24] }
    ]
  },
  {
    name: "Blooming Allongé", peak: "≈5 bar", tag: "ultra-light · fruity · max clarity",
    desc: "Fill → bloom soak → push → slow taper",
    aim: "Long, thin, tea-like, super-clean. Pulls fruit & floral from light roasts.",
    grind: "Fine, long ratio (1:3+). Expect a longer, light-bodied shot.",
    pts: [[0,0],[2.25,4.5],[4.58,1.0],[12,1.0],[17,5.0],[29.5,3.5],[40,3.5]],
    phases: [
      { name:"FILL", target:"4.5 bar", ramp:"2.0 bar/s", exit:"pressure ≥ 4 bar — or 4 s cap", band:[0,2.25] },
      { name:"BLOOM", target:"1.0 bar", ramp:"1.5 bar/s down", exit:"≥ 4 g in cup — or 10 s cap", band:[2.25,12] },
      { name:"PERCOLATE", target:"6.0 bar", ramp:"0.8 bar/s", exit:"5 s cap — or ≥ 5.5 bar", band:[12,17] },
      { name:"DECLINE", target:"3.5 bar", ramp:"0.12 bar/s down", exit:"user STOP / pot takeover", band:[17,40] }
    ]
  },
  {
    name: "Blooming Espresso", peak: "9 bar", tag: "light–medium · clarity + body",
    desc: "Bloom for evenness, then full 9 bar",
    aim: "A bloom for evenness, then full pressure for richness.",
    grind: "Medium-fine, ~1:2 to 1:2.5.",
    pts: [[0,0],[3.25,6.5],[6.25,2],[12,2],[20.75,9],[32,9]],
    phases: [
      { name:"FILL", target:"6.5 bar", ramp:"2.0 bar/s", exit:"pressure ≥ 6 bar — or 4 s cap", band:[0,3.25] },
      { name:"BLOOM", target:"2.0 bar", ramp:"1.5 bar/s down", exit:"≥ 4 g in cup — or 8 s cap", band:[3.25,12] },
      { name:"RAMP", target:"9.0 bar", ramp:"0.8 bar/s", exit:"setpoint reaches 9 bar", band:[12,20.75] },
      { name:"HOLD", target:"9.0 bar", ramp:"—", exit:"user STOP / pot takeover", band:[20.75,32] }
    ]
  },
  {
    name: "Allongé", peak: "5 bar", tag: "light · forgiving fallback",
    desc: "Gentle wet, then a flat 5 bar hold",
    aim: "Simple high-clarity long shot — the forgiving fallback.",
    grind: "Coarser, long ratio (1:3–1:5), ~30 s.",
    pts: [[0,0],[0.5,1],[6,1],[11,5],[24,5]],
    phases: [
      { name:"PREINFUSE", target:"1.0 bar", ramp:"2.0 bar/s in", exit:"first drips (≥1 g) — or 10 s cap", band:[0,6] },
      { name:"RAMP", target:"5.0 bar", ramp:"0.8 bar/s", exit:"setpoint reaches 5 bar", band:[6,11] },
      { name:"HOLD", target:"5.0 bar", ramp:"—", exit:"user STOP / pot takeover", band:[11,24] }
    ]
  }
];

function maxT(p) { var m = 0; for (var i=0;i<p.pts.length;i++) if (p.pts[i][0]>m) m=p.pts[i][0]; return m; }
