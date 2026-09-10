
const DEFAULT_DATA=window.EQ_RESEARCH_DATA,BASTION_DATA=window.EQ_BASTION_DATA,SPELL_CATALOG=window.EQ_SPELL_CATALOG;
const BUILTIN_BASTION_RECIPES=[...(BASTION_DATA.recipes||[])];
const syncedSpellMetadata=new Map();

const LIVE_COMPANION_ORIGIN="http://127.0.0.1:8765";
function apiUrl(path){
 const onCompanion=location.protocol.startsWith("http")&&location.hostname==="127.0.0.1"&&location.port==="8765";
 return onCompanion?path:`${LIVE_COMPANION_ORIGIN}${path}`;
}

let ACTIVE_DATA=BASTION_DATA,inventory=[],aggregated=[],inventorySources=[],mageloInventory=[],mageloMeta=null,recipeResults=[],selectedKey=null,liveLootCounts=new Map(),liveOwnedCounts=new Map(),sessionLootEvents=[],previousMageloCounts=null,liveLootFeed=[],liveLastEventId=0,liveEnabled=true,liveAudioCtx=null,liveMonitorOnline=false,corpusSyncInProgress=false,livePollInFlight=false,processedLiveEventIds=new Set();
const $=s=>document.querySelector(s),norm=s=>(s||"").toLowerCase().replace(/[’']/g,"`").replace(/\s+/g," ").trim();
const esc=s=>String(s??"").replace(/[&<>"']/g,m=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[m]));
function canonical(s){let n=norm(s);if(n.startsWith("spell: "))n=n.slice(7);return(ACTIVE_DATA.aliases||{})[n]||n}
function catalogSpell(name){
 return (SPELL_CATALOG.spells||[]).find(s=>norm(s.name)===norm(name))||null;
}
const VERIFIED_SPELL_METADATA={
 "divine intervention":{classes:["CLR"],levelByClass:{CLR:60},source:"verified"}
};
function verifiedSpellMetadata(name){return VERIFIED_SPELL_METADATA[norm(name)]||null;}
function syncedMetadataSpell(name){return syncedSpellMetadata.get(norm(name))||null;}
function mergeSpellMetadata(payload){
 syncedSpellMetadata.clear();
 for(const s of (payload?.spells||[])){
  if(!s?.name||!(s.classes||[]).length)continue;
  syncedSpellMetadata.set(norm(s.name),s);
 }
 evaluate();renderSummary();renderList();renderDetail();
 return metadataCoverage();
}
function metadataCoverage(){
 const rows=(ACTIVE_DATA.recipes||[]).filter(r=>r.isSpellRecipe!==false&&String(r.recipeName||"").match(/^Spell:/i));
 const unique=new Map();
 for(const r of rows)unique.set(norm(r.spell),r.spell);
 let mapped=0,withLevels=0;
 for(const name of unique.values()){
  const s=syncedMetadataSpell(name)||verifiedSpellMetadata(name)||catalogSpell(name);
  if((s?.classes||[]).length)mapped++;
  if((s?.classes||[]).length&&(s.classes||[]).every(c=>s.levelByClass?.[c]!=null))withLevels++;
 }
 return {total:unique.size,mapped,withLevels,unmapped:unique.size-mapped};
}
function enrichSpellMetadata(r){
 const c=catalogSpell(r.spell),b=syncedMetadataSpell(r.spell),v=verifiedSpellMetadata(r.spell);
 const existingClasses=(r.classes||[]).filter(Boolean);
 const verifiedClasses=(v?.classes||[]).filter(Boolean);
 const bastionClasses=(b?.classes||[]).filter(Boolean);
 const catalogClasses=(c?.classes||[]).filter(Boolean);
 const fallbackClasses=verifiedClasses.length?verifiedClasses:(bastionClasses.length?bastionClasses:catalogClasses);
 const classes=existingClasses.length?existingClasses:(r.class&&r.class!=="ALL"&&r.class!=="UNKNOWN"?[r.class]:fallbackClasses);
 const levelByClass={...(c?.levelByClass||{}),...(b?.levelByClass||{}),...(v?.levelByClass||{}),...(r.levelByClass||{})};
 if(r.class&&r.class!=="ALL"&&r.class!=="UNKNOWN"&&r.level!=null&&!levelByClass[r.class])levelByClass[r.class]=r.level;
 let level=r.level??null;
 if(level==null&&classes.length===1&&levelByClass[classes[0]]!=null)level=levelByClass[classes[0]];
 const resolvedClass=classes.length===1?classes[0]:(r.class&&r.class!=="ALL"?r.class:"UNKNOWN");
 return {...r,class:resolvedClass,classes,level,levelByClass,_classLevelMapped:classes.length>0};
}
function spellUsageLabel(r){
 const classes=(r.classes||[]).filter(Boolean);
 const lb=r.levelByClass||{};
 if(classes.length){
  const parts=classes.map(cls=>lb[cls]!=null?`${cls} Level ${lb[cls]}`:cls);
  return parts.join(" • ");
 }
 if(r.class&&r.class!=="ALL"&&r.class!=="UNKNOWN")return `${r.class}${r.level!=null?` • Level ${r.level}`:""}`;
 return "Class/level not yet mapped";
}
function filenameCharacter(n){return n.replace(/\.(txt|tsv|csv)$/i,"").replace(/[-_ ]?(inventory|inv|dump)$/i,"").trim()||n}
function rkey(r){return r.recipeKey||((r.recipeId!=null)?`bastion:${r.recipeId}`:`${r.class||"ALL"}:${r.spell}:${r.trivial??"?"}`)}
function parseInventory(text,source){const lines=text.replace(/\r/g,"").split("\n").filter(x=>x.trim());if(!lines.length)throw Error("Empty file.");const d=lines[0].includes("\t")?"\t":",",h=lines[0].split(d).map(x=>x.trim().toLowerCase()),i=k=>h.indexOf(k);if(i("name")<0||i("id")<0||i("count")<0)throw Error("Could not find Name, ID and Count columns.");return lines.slice(1).map(l=>{const c=l.split(d);return{source,name:(c[i("name")]||"").trim(),id:Number(c[i("id")]||0),count:Number(c[i("count")]||0)}}).filter(x=>x.name&&x.name!=="Empty"&&x.id&&x.count>0)}
function aggregate(items){const m=new Map();for(const x of items){const k=`id:${x.id}`;if(!m.has(k))m.set(k,{name:x.name,id:x.id,count:0});m.get(k).count+=x.count}return[...m.values()]}
function rebuildAggregated(){aggregated=aggregate([...inventory,...mageloInventory]);}
function vendor(c){return $("#vendorBasics").checked&&c.vendorBasic}
function knownIdsForName(name){
 const ids=new Set();
 for(const r of (ACTIVE_DATA.recipes||[]))for(const c of (r.components||[])){const x=typeof c==="string"?{name:c}:c;if(x.id&&canonical(x.name)===canonical(name))ids.add(Number(x.id))}
 for(const s of (ACTIVE_DATA.subcombines||[]))for(const c of (s.components||[])){const x=typeof c==="string"?{name:c}:c;if(x.id&&canonical(x.name)===canonical(name))ids.add(Number(x.id))}
 for(const [id,e] of Object.entries(ACTIVE_DATA.ownedComponentEvidence||{}))if(canonical(e.name)===canonical(name))ids.add(Number(id));
 return [...ids];
}
function liveCountForComponent(c){
 const qty=liveOwnedCounts.get(canonical(c.name))||0;
 if(!qty)return 0;
 if(!c.id)return qty;
 const ids=knownIdsForName(c.name);
 return ids.length===1&&ids[0]===Number(c.id)?qty:0;
}
function mageloCountMap(items){
 const m=new Map();
 for(const x of items||[])m.set(Number(x.id),(m.get(Number(x.id))||0)+Number(x.count||1));
 return m;
}
function canonicalNameForExactId(id){
 const names=[];
 for(const r of (ACTIVE_DATA.recipes||[]))for(const c0 of (r.components||[])){
  const c=typeof c0==="string"?{name:c0}:c0;
  if(Number(c.id)===Number(id)&&c.name)names.push(c.name);
 }
 for(const s of (ACTIVE_DATA.subcombines||[]))for(const c0 of (s.components||[])){
  const c=typeof c0==="string"?{name:c0}:c0;
  if(Number(c.id)===Number(id)&&c.name)names.push(c.name);
 }
 return names[0]||null;
}
function reconcileOwnedLootWithMagelo(oldCounts,newCounts){
 if(!oldCounts)return [];
 const reconciled=[];
 for(const [id,newQty] of newCounts){
  const oldQty=oldCounts.get(id)||0,delta=newQty-oldQty;
  if(delta<=0)continue;
  const name=canonicalNameForExactId(id);
  if(!name)continue;
  const ids=knownIdsForName(name);
  if(ids.length!==1||Number(ids[0])!==Number(id))continue;
  const key=canonical(name),pending=liveOwnedCounts.get(key)||0;
  if(!pending)continue;
  const used=Math.min(delta,pending),left=pending-used;
  if(left)liveOwnedCounts.set(key,left);else liveOwnedCounts.delete(key);
  reconciled.push({id,name,qty:used});
 }
 return reconciled;
}
function count(c){
 if(vendor(c))return 999999;
 if(c.id)return (aggregated.find(x=>x.id===Number(c.id))?.count||0)+liveCountForComponent(c);
 const t=canonical(c.name);
 return aggregated.filter(x=>canonical(x.name)===t).reduce((a,x)=>a+x.count,0)+liveCountForComponent(c);
}
function evaluate(){recipeResults=(ACTIVE_DATA.recipes||[]).filter(r=>r.complete!==false).map(raw=>{const r=enrichSpellMetadata(raw);const comps=(r.components||[]).map(x=>{const c=typeof x==="string"?{name:x}:x,need=c.count||1,have=count(c),assumed=vendor(c);return{...c,need,have,assumed,ok:assumed||have>=need}}),missing=comps.filter(c=>!c.ok);return{...r,_key:rkey(r),comps,missingCount:missing.length,maxCombines:missing.length?0:Math.min(...comps.filter(c=>!c.assumed).map(c=>Math.floor(c.have/c.need)).concat([999]))}})}
function status(r){return r.missingCount===0?"READY":r.missingCount===1?"ONE_SHORT":r.missingCount===2?"TWO_SHORT":"MISSING"}
function statusText(r){return r.missingCount===0?`READY${r.maxCombines<999?` ×${r.maxCombines}`:""}`:`MISSING ${r.missingCount}`}
function catalogPendingRows(){if(ACTIVE_DATA!==BASTION_DATA)return[];const mapped=new Set(recipeResults.map(r=>norm(r.spell)));return(SPELL_CATALOG.spells||[]).filter(s=>s.researchStatus==="CONFIRMED_UNRESOLVED"&&(s.acquisition||[]).includes("Research")&&!mapped.has(norm(s.name))).map(s=>({_pending:true,_key:`pending:${norm(s.name)}`,spell:s.name,class:(s.classes||[]).length===1?s.classes[0]:"UNKNOWN",classes:s.classes||[],level:s.levelByClass&&Object.values(s.levelByClass)[0]||null,levelByClass:s.levelByClass||{},researchEvidence:s.researchEvidence||[],notes:s.notes||"",bastionUrl:s.bastionUrl||null}))}
function classMatches(r,cls){if(cls==="ALL")return true;if((r.classes||[]).includes(cls))return true;return r.class===cls}
function rows(){const cls=$("#classFilter").value,st=$("#statusFilter").value,q=norm($("#spellSearch").value),lvl=Number($("#characterLevel").value||0),order={READY:0,ONE_SHORT:1,TWO_SHORT:2,MISSING:3,PENDING:4};let a=[...recipeResults,...catalogPendingRows()].filter(r=>classMatches(r,cls)&&(!lvl||!r.level||r.level<=lvl));if(st!=="ALL")a=a.filter(r=>(r._pending?"PENDING":status(r))===st);if(q)a=a.filter(r=>norm(r.spell).includes(q));return a.sort((x,y)=>order[x._pending?"PENDING":status(x)]-order[y._pending?"PENDING":status(y)]||(x.level||999)-(y.level||999)||x.spell.localeCompare(y.spell)||(x.recipeId||0)-(y.recipeId||0))}
function skill(r){const s=Number($("#researchSkill").value||0);return !s||r.trivial==null?"":s>=r.trivial?" • trivial to you":` • ${r.trivial-s} skill to trivial`}
function renderSummary(){const a=rows();$("#sumReady").textContent=a.filter(r=>!r._pending&&r.missingCount===0).length;$("#sumOne").textContent=a.filter(r=>!r._pending&&r.missingCount===1).length;$("#sumPending").textContent=a.filter(r=>r._pending).length;$("#sumShown").textContent=a.length}
function renderList(){const a=rows();$("#spellList").innerHTML=a.length?a.map(r=>{if(r._pending)return`<div class="spell-row pending-row ${selectedKey===r._key?"selected":""}" data-key="${esc(r._key)}"><div><div class="spell-name">${esc(r.spell)}</div><div class="spell-meta">${r.class||"ALL"}${r.level?` • Level ${r.level}`:""} • Bastion Research confirmed</div></div><span class="status-pill pending">RECIPE PENDING</span></div>`;const st=status(r),css=st==="READY"?"ready":st==="ONE_SHORT"?"one":st==="TWO_SHORT"?"two":"missing";return`<div class="spell-row ${css} ${selectedKey===r._key?"selected":""}" data-key="${esc(r._key)}"><div><div class="spell-name">${esc(r.spell)}${r.recipeId?` <small>#${r.recipeId}</small>`:""}</div><div class="spell-meta">${spellUsageLabel(r)} • Research ${r.trivial??"?"}${skill(r)}</div></div><span class="status-pill ${css}">${statusText(r)}</span></div>`}).join(""):'<div class="detail-empty"><p>No Research spells match these filters.</p></div>';document.querySelectorAll(".spell-row").forEach(e=>e.onclick=()=>{selectedKey=e.dataset.key;renderList();renderDetail()})}
function renderDetail(){const pending=catalogPendingRows().find(x=>x._key===selectedKey);if(pending){$("#spellDetail").innerHTML=`<div class="detail-head"><h2>${esc(pending.spell)}</h2><p>${spellUsageLabel(pending)} • Bastion Research confirmed</p></div><div class="pending-box"><h3>Exact recipe still awaiting verification</h3><p>This spell is no longer hidden. Bastion evidence confirms it is researchable, but the app will not invent missing ingredients or a trivial.</p></div>${pending.notes?`<div class="recipe-info">${esc(pending.notes)}</div>`:""}${pending.researchEvidence.length?`<div class="recipe-info"><strong>Verified research evidence</strong>${pending.researchEvidence.map(e=>`<div class="evidence-line">${e.itemId?`Item #${e.itemId} — `:""}${esc(e.itemName||e.label||"Bastion source")}${e.url?` — <a href="${esc(e.url)}" target="_blank">open source ↗</a>`:""}</div>`).join("")}</div>`:""}`;return}const r=recipeResults.find(x=>x._key===selectedKey);if(!r){$("#spellDetail").innerHTML='<div class="detail-empty"><h2>Select a spell</h2><p>Choose a spell to see what you have and what you need.</p></div>';return}const miss=r.comps.filter(c=>!c.ok);$("#spellDetail").innerHTML=`<div class="detail-head"><h2>${esc(r.spell)}</h2><p>${spellUsageLabel(r)} • Research trivial ${r.trivial??"?"}${r.recipeId?` • Bastion recipe #${r.recipeId}`:""}</p></div><table class="ingredient-table"><thead><tr><th>Ingredient</th><th>Need</th><th>You have</th><th>Status</th></tr></thead><tbody>${r.comps.map(c=>`<tr><td>${esc(c.name)}${c.id?` <small>#${c.id}</small>`:""}</td><td>${c.need}</td><td class="${c.assumed?"vendor":c.ok?"have":"need"}">${c.assumed?"Vendor":c.have}</td><td class="${c.ok?"have":"need"}">${c.assumed?"◎ assumed available":c.ok?"✓ have":"✕ missing"}</td></tr>`).join("")}</tbody></table>${miss.length?`<div class="missing-box"><h3>You still need</h3>${miss.map(c=>`<div>${Math.max(c.need-c.have,1)} × ${esc(c.name)}${c.id?` <small>#${c.id}</small>`:""}</div>`).join("")}</div>`:`<div class="ready-box"><h3>You can make this now.</h3><p>${r.maxCombines<999?`Current inventory supports ${r.maxCombines} combine(s).`:"Vendor-only basics assumed."}</p></div>`}<div class="recipe-info">${r.containers?.length?`Containers: ${esc(r.containers.join(", "))}<br>`:""}${r.sourceUrl?`<a href="${esc(r.sourceUrl)}" target="_blank">Open Bastion recipe ↗</a>`:""}</div>`}

function evaluateLevelingRecipe(r){
 const comps=(r.components||[]).map(x=>{const c=typeof x==="string"?{name:x}:x,need=c.count||1,have=count(c),assumed=vendor(c);return{...c,need,have,assumed,ok:assumed||have>=need}});
 const missing=comps.filter(c=>!c.ok);
 return {...r,_levelingOnly:true,_key:rkey(r),comps,missingCount:missing.length,maxCombines:missing.length?0:Math.min(...comps.filter(c=>!c.assumed).map(c=>Math.floor(c.have/c.need)).concat([999]))};
}
function allLevelingRecipes(){
 const exact=[...recipeResults];
 const subs=(ACTIVE_DATA.subcombines||[]).filter(s=>s.complete!==false&&s.trivial!=null).map((s,i)=>evaluateLevelingRecipe({
   recipeKey:`subcombine:${norm(s.name)}:${s.trivial}`,
   recipeId:s.recipeId||null,class:s.class||"ALL",spell:s.name,trivial:s.trivial,
   components:s.components||[],containers:s.containers||[],sourceUrl:s.sourceUrl||s.url||null,
   verification:s.verification||"bastion-recipe-page",complete:true,isSubcombine:true
 }));
 const seen=new Set(),out=[];
 for(const r of [...exact,...subs]){const k=`${norm(r.spell)}|${r.trivial}|${r.recipeId||""}`;if(!seen.has(k)){seen.add(k);out.push(r)}}
 return out;
}
function componentLeverage(c){const ev=ACTIVE_DATA.ownedComponentEvidence||{};if(c.id&&ev[String(c.id)])return(ev[String(c.id)].researchUses||[]).length;for(const x of Object.values(ev))if(norm(x.name)===norm(c.name))return(x.researchUses||[]).length;return 0}
function levelingCandidates(){
 const curRaw=$("#levelCurrent").value, cur=curRaw===""?null:Number(curRaw);
 if(cur===null||Number.isNaN(cur))return[];
 const targetRaw=$("#levelTarget").value, target=targetRaw===""?Math.min(cur+50,300):Number(targetRaw);
 const strategy=$("#levelStrategy").value,onlyClass=$("#levelClassOnly").checked,cls=$("#classFilter").value;
 if(target<=cur)return[];
 return allLevelingRecipes().filter(r=>r.trivial!=null&&r.trivial>cur&&r.trivial<=Math.max(target+35,cur+75)&&(!onlyClass||cls==="ALL"||r.class==="ALL"||r.class===cls)).map(r=>{
   const nonVendor=r.comps.filter(c=>!c.assumed),available=r.missingCount===0?r.maxCombines:0,
   leverages=nonVendor.map(componentLeverage),rare=leverages.reduce((a,v)=>a+Math.max(0,v-1),0),
   vendorCount=r.comps.filter(c=>c.assumed).length,delta=r.trivial-cur;
   let score;
   if(strategy==="inventory")score=available*15-r.missingCount*12-Math.max(0,delta-40)*.2-rare*.5+(r.isSubcombine?8:0);
   else score=available*6+vendorCount*8-r.missingCount*14-rare*2.2-Math.abs(delta-15)*.35+(r.isSubcombine?12:0);
   const valuable=nonVendor.filter(c=>componentLeverage(c)>=4).map(c=>`${c.name} (${componentLeverage(c)} spell uses)`);
   return{r,score,available,delta,valuable,target};
 }).sort((a,b)=>b.score-a.score||a.r.trivial-b.r.trivial);
}
function renderLeveling(){
 const curRaw=$("#levelCurrent").value, cur=curRaw===""?null:Number(curRaw);
 if(cur===null||Number.isNaN(cur)){ $("#levelingSummary").textContent="Enter your current Research skill to build a path. Target is optional.";$("#levelingList").innerHTML="";return}
 const targetRaw=$("#levelTarget").value,target=targetRaw===""?Math.min(cur+50,300):Number(targetRaw);
 if(target<=cur){$("#levelingSummary").textContent="Target must be higher than current Research skill.";$("#levelingList").innerHTML="";return}
 const a=levelingCandidates();
 $("#levelingSummary").textContent=a.length?`Showing ${Math.min(a.length,16)} verified leveling candidates from skill ${cur} toward ${target}. Subcombines are included when verified. Scoring is a planning heuristic, not an official skill-up probability formula.`:`No verified recipe candidates were found in this range. Try a higher target or turn off Selected class only.`;
 $("#levelingList").innerHTML=a.slice(0,16).map((x,i)=>`<div class="level-card ${i===0?"best":""}"><div class="level-head"><strong>${i===0?"★ ":""}${esc(x.r.spell)}</strong><span class="level-score">Trivial ${x.r.trivial}</span></div><div class="level-meta">${x.r.isSubcombine?"Research subcombine":(x.r.class||"ALL")} • ${x.delta} points above current • ${x.available&&x.available<999?`${x.available} combine(s) available`:x.available>=999?"vendor-only/assumed available":`missing ${x.r.missingCount} component type(s)`}</div><div class="level-reason">${x.available?`You can attempt this now with your current inventory/settings.`:`Not craftable now, but useful as a near-term skill-up target.`}</div>${x.valuable.length?`<div class="level-warn">Conserve if possible: ${esc(x.valuable.join(", "))}</div>`:""}${x.r.sourceUrl?`<div class="recipe-info"><a href="${esc(x.r.sourceUrl)}" target="_blank">Open verified recipe ↗</a></div>`:""}</div>`).join("");
}


function componentMatchesItem(c,item){
 if(c.id&&item.id)return Number(c.id)===Number(item.id);
 if(c.id)return false;
 return canonical(c.name)===canonical(item.name);
}
function evaluatedSubcombine(s){
 const comps=(s.components||[]).map(x=>{const c=typeof x==="string"?{name:x}:x,need=c.count||1,have=count(c),assumed=vendor(c);return{...c,need,have,assumed,ok:assumed||have>=need}});
 const missing=comps.filter(c=>!c.ok);
 return {...s,spell:s.name,_isSubcombine:true,_key:`sub:${s.recipeId||norm(s.name)}`,comps,missingCount:missing.length,maxCombines:missing.length?0:Math.min(...comps.filter(c=>!c.assumed).map(c=>Math.floor(c.have/c.need)).concat([999]))};
}
function allReverseRecipes(){return [...recipeResults,...(ACTIVE_DATA.subcombines||[]).filter(s=>s.complete!==false).map(evaluatedSubcombine)]}
function evidenceForItem(item){
 const ev=ACTIVE_DATA.ownedComponentEvidence||{};
 if(item.id&&ev[String(item.id)])return ev[String(item.id)];
 const matches=Object.entries(ev).filter(([,x])=>norm(x.name)===norm(item.name));
 if(matches.length===1)return matches[0][1];
 const ne=ACTIVE_DATA.nameEvidence||{};
 return ne[canonical(item.name)]||ne[norm(item.name)]||null;
}
function reverseUsesForItem(item){
 const mapped=allReverseRecipes().filter(r=>r.comps.some(c=>componentMatchesItem(c,item))).map(r=>{
  const matched=r.comps.filter(c=>componentMatchesItem(c,item)),otherMissing=r.comps.filter(c=>!componentMatchesItem(c,item)&&!c.ok).length;
  return {...r,matched,otherMissing,canMake:r.missingCount===0,_evidenceOnly:false};
 });
 const ev=evidenceForItem(item),extra=[],seen=new Set(mapped.map(r=>`${r._isSubcombine?"sub":"spell"}:${r.recipeId||norm(r.spell)}`));
 for(const u of ev?.exactItemUses||[]){const k=`${u.type==="subcombine"?"sub":"spell"}:${u.recipeId||norm(u.name)}`;if(!seen.has(k))extra.push({spell:u.name,recipeId:u.recipeId||null,sourceUrl:u.url||null,_isSubcombine:u.type==="subcombine",_evidenceOnly:true,otherMissing:null,canMake:false,matched:[item],class:"ALL",classes:[],trivial:null})}
 return [...mapped,...extra];
}
function reverseValueLabel(n){if(n>=5)return{text:"KEEP — HIGH VALUE",cls:"value-high"};if(n>=1)return{text:"KEEP",cls:"value-mid"};return{text:"NO VERIFIED RESEARCH USE FOUND",cls:"value-unknown"}}
function renderInventoryBrowser(){
 const el=$("#inventoryBrowser");if(!el)return;if(!aggregated.length){el.innerHTML="";return}
 const researchy=aggregated.filter(a=>/^words? of |^rune of |grimoire|compendium|memoir|writ|tome|signet|emblem|bolts|card of |staff shard|sliver|mist of |flame of |scales of |primordial substance/i.test(a.name));
 el.innerHTML=researchy.slice(0,100).map(a=>{const uses=reverseUsesForItem(a),v=reverseValueLabel(uses.length);return`<div class="inventory-item"><div class="inventory-item-head"><strong>${esc(a.name)}</strong><small>#${a.id} ×${a.count}</small></div><div class="${v.cls}" style="font-size:11px;margin-top:5px">${v.text}${uses.length?` • ${uses.length} verified use(s)`:""}</div><button class="ghost reverse-from-item" data-id="${a.id}">Show Research Uses</button></div>`}).join("");
 document.querySelectorAll(".reverse-from-item").forEach(btn=>btn.onclick=()=>{$("#reverseSearch").value=btn.dataset.id;renderReverseLookup();$("#reverseSearch").scrollIntoView({behavior:"smooth",block:"center"})});
}
function knownItemByName(q){
 const matches=[];for(const r of allReverseRecipes())for(const c of r.comps)if(norm(c.name)===norm(q))matches.push({id:c.id||null,name:c.name});
 for(const [id,e] of Object.entries(ACTIVE_DATA.ownedComponentEvidence||{}))if(norm(e.name)===norm(q))matches.push({id:Number(id),name:e.name});
 for(const e of Object.values(ACTIVE_DATA.nameEvidence||{}))if(norm(e.name)===norm(q))matches.push({id:null,name:e.name});
 const out=[];for(const m of matches)if(!out.some(x=>x.id===m.id&&norm(x.name)===norm(m.name)))out.push(m);return out;
}
function reverseLookupItems(){
 const q=$("#reverseSearch")?.value.trim()||"";if(!q)return[];
 if(/^\d+$/.test(q)){const id=Number(q),a=aggregated.find(x=>x.id===id);if(a)return[a];const ev=(ACTIVE_DATA.ownedComponentEvidence||{})[String(id)];return ev?[{id,name:ev.name,count:0}]:[{id,name:"Unknown item",count:0}]}
 const inv=aggregated.filter(x=>norm(x.name)===norm(q));if(inv.length)return inv;
 const known=knownItemByName(q);if(known.length)return known.map(x=>({...x,count:x.id?(aggregated.find(a=>a.id===x.id)?.count||0):0}));
 return[{id:null,name:q,count:0}];
}
function renderReverseLookup(){
 const out=$("#reverseResults"),sum=$("#reverseSummary"),items=reverseLookupItems();if(!out||!sum)return;
 if(!items.length||!$("#reverseSearch").value.trim()){out.innerHTML="";sum.textContent='Search by item name or ID, or click “Show Research Uses” on an inventory item.';return}
 const cls=$("#reverseClassFilter").value,st=$("#reverseStatusFilter").value;let total=0,blocks=[];
 for(const item of items){
  let uses=reverseUsesForItem(item);if(cls!=="ALL")uses=uses.filter(r=>r._isSubcombine||r._evidenceOnly||classMatches(r,cls));if(st==="READY")uses=uses.filter(r=>r.canMake);if(st==="ONE_SHORT")uses=uses.filter(r=>r.otherMissing===1);
  uses.sort((a,b)=>(a._evidenceOnly?1:0)-(b._evidenceOnly?1:0)||((a.otherMissing??99)-(b.otherMissing??99))||(a.spell||"").localeCompare(b.spell||""));total+=uses.length;const value=reverseValueLabel(uses.length);
  blocks.push(`<div class="reverse-item-header"><strong>${esc(item.name)}</strong>${item.id?` <small>#${item.id}</small>`:""}${item.count?` <small>×${item.count} owned</small>`:""}<div class="${value.cls}" style="margin-top:4px">${value.text}</div></div>`+
  (uses.length?uses.map(r=>`<div class="reverse-card ${r._evidenceOnly?"evidence-only":""}"><h3><span class="use-type ${r._isSubcombine?"subcombine":""}">${r._isSubcombine?"SUBCOMBINE":"SPELL"}</span>${esc(r.spell)}${r.recipeId?` <small>#${r.recipeId}</small>`:""}</h3><div class="reverse-card-meta">${r.trivial!=null?`Research ${r.trivial}`:"Bastion item-use evidence"}${!r._isSubcombine&&((r.classes||[]).length||r.class)?` • ${(r.classes||[]).length?r.classes.join(", "):(r.class||"ALL")}`:""}</div><div class="recipe-info">${r.sourceUrl?`<a href="${esc(r.sourceUrl)}" target="_blank">Open Bastion source ↗</a>`:""}</div></div>`).join(""):`<div class="reverse-card"><p>No verified Research use is currently indexed for this exact item. This is a coverage gap, not proof the item is useless.</p></div>`));
 }
 sum.textContent=`${items.length>1?`${items.length} exact item IDs share this name • `:""}${total} verified Research use(s) shown.`;out.innerHTML=blocks.join("");
}
function runQuickLookup(){
 const q=$("#quickLootSearch").value.trim();if(!q){$("#quickLootResult").textContent="Type an item name or ID.";return}
 $("#reverseSearch").value=q;renderReverseLookup();const items=reverseLookupItems(),uses=items.flatMap(reverseUsesForItem);
 $("#quickLootResult").textContent=uses.length?`${items.length>1?`${items.length} same-name IDs • `:""}${uses.length} verified Research use(s). Full results shown below.`:"No indexed use yet — full results below indicate a coverage gap.";
 document.querySelector("#reverseResults").scrollIntoView({behavior:"smooth",block:"start"});
}

function liveSettings(){
 return {
  includeOthers:$("#liveIncludeOthers")?.checked??false,
  classOnly:$("#liveClassOnly")?.checked??false,
  soundHigh:$("#soundHighValue")?.checked??true,
  soundAny:$("#soundAnyResearch")?.checked??false,
  soundCraftable:$("#soundCraftable")?.checked??true,
  threshold:Math.max(1,Number($("#highValueThreshold")?.value||5)),
  volume:Math.max(0,Math.min(1,Number($("#liveVolume")?.value||65)/100)),
  ownershipMode:$("#lootOwnershipMode")?.value||"COUNT"
 };
}
function saveLiveSettings(){
 const s=liveSettings();
 try{localStorage.setItem("eqResearchLiveSettings",JSON.stringify(s))}catch{}
}
function loadLiveSettings(){
 try{
  const s=JSON.parse(localStorage.getItem("eqResearchLiveSettings")||"null");if(!s)return;
  if($("#liveIncludeOthers"))$("#liveIncludeOthers").checked=!!s.includeOthers;
  if($("#liveClassOnly"))$("#liveClassOnly").checked=!!s.classOnly;
  if($("#soundHighValue"))$("#soundHighValue").checked=s.soundHigh!==false;
  if($("#soundAnyResearch"))$("#soundAnyResearch").checked=!!s.soundAny;
  if($("#soundCraftable"))$("#soundCraftable").checked=s.soundCraftable!==false;
  if($("#highValueThreshold")&&s.threshold)$("#highValueThreshold").value=s.threshold;
  if($("#liveVolume")&&s.volume!=null)$("#liveVolume").value=Math.round(s.volume*100);
  if($("#lootOwnershipMode")&&s.ownershipMode)$("#lootOwnershipMode").value=s.ownershipMode;
 }catch{}
}
function ensureAudio(){
 if(!liveAudioCtx){const AC=window.AudioContext||window.webkitAudioContext;if(AC)liveAudioCtx=new AC()}
 if(liveAudioCtx?.state==="suspended")liveAudioCtx.resume();
}
function beep(kind){
 const s=liveSettings();if(!liveAudioCtx||s.volume<=0)return;
 const plans={
  research:[[660,.10]],
  high:[[880,.12],[1175,.16]],
  craftable:[[740,.12],[988,.12],[1318,.22]]
 };
 const plan=plans[kind]||plans.research;let t=liveAudioCtx.currentTime+.02;
 for(const [freq,dur] of plan){
  const o=liveAudioCtx.createOscillator(),g=liveAudioCtx.createGain();
  o.type="sine";o.frequency.value=freq;g.gain.setValueAtTime(0.0001,t);g.gain.exponentialRampToValueAtTime(Math.max(.0001,s.volume*.18),t+.015);g.gain.exponentialRampToValueAtTime(.0001,t+dur);
  o.connect(g);g.connect(liveAudioCtx.destination);o.start(t);o.stop(t+dur+.02);t+=dur+.05;
 }
}
function readySpellKeys(){
 return new Set(recipeResults.filter(r=>r.missingCount===0).map(r=>r._key));
}
function researchUsesForLootName(name){
 const items=knownItemByName(name);
 const candidates=items.length?items:[{id:null,name,count:0}];
 const map=new Map();
 for(const item of candidates){
  for(const u of reverseUsesForItem(item)){
   const k=`${u._isSubcombine?"sub":"spell"}:${u.recipeId||norm(u.spell)}`;
   if(!map.has(k))map.set(k,u);
  }
 }
 return {items,candidates,uses:[...map.values()]};
}
function useMatchesSelectedClass(u){
 if(!liveSettings().classOnly)return true;
 const cls=$("#classFilter")?.value||"ALL";if(cls==="ALL")return true;
 if(u._isSubcombine)return true;
 return classMatches(u,cls);
}
function classifyLoot(name){
 const lookup=researchUsesForLootName(name),uses=lookup.uses.filter(useMatchesSelectedClass);
 const spellUses=uses.filter(u=>!u._isSubcombine),subUses=uses.filter(u=>u._isSubcombine);
 const threshold=liveSettings().threshold;
 const ambiguous=lookup.items.filter(x=>x.id).length>1;
 const value=uses.length>=threshold?"HIGH VALUE":uses.length?"KEEP":"UNKNOWN";
 return {name,uses,spellUses,subUses,value,ambiguous,ids:lookup.items.filter(x=>x.id).map(x=>x.id)};
}
function openLootUseModal(entry){
 if(!entry)return;
 const lookup=researchUsesForLootName(entry.item);let uses=lookup.uses||[];const ids=[...new Set((lookup.items||[]).map(x=>x.id).filter(Boolean))];
 $("#lootUseTitle").textContent=entry.item;$("#lootUseSubtitle").textContent=`Looted by: ${entry.looter||"Unknown"} • ${uses.length} verified Research use${uses.length===1?"":"s"}`;
 let html=ids.length>1?`<div class="loot-ambiguity"><strong>Multiple exact item IDs share this name:</strong> ${ids.join(", ")}. The EQ log does not identify which one dropped, so all verified uses are shown.</div>`:"";
 if(!uses.length)html+=`<div class="loot-ambiguity">No verified use is indexed yet. Treat this as a coverage gap, not proof the item is useless.</div>`;
 else html+=`<div class="loot-use-grid">`+uses.map(u=>{const other=u.otherMissing;const readiness=u._evidenceOnly?"Verified use — recipe details incomplete":u.canMake?"READY NOW":other===1?"Missing 1 other component":other!=null?`Missing ${other} other components`:"Verified use";const rc=u.canMake?"ready":other===1?"one":"missing";const cls=(u.classes||[]).length?u.classes.join(", "):(u.class&&u.class!=="ALL"?u.class:"");return `<div class="loot-use-card"><h3><span class="use-type ${u._isSubcombine?"subcombine":""}">${u._isSubcombine?"SUBCOMBINE":"SPELL"}</span>${esc(u.spell||u.name||"Unknown")}</h3><div class="meta">${cls?`${esc(cls)} • `:""}${u.trivial!=null?`Research ${u.trivial}`:"Research use verified"}${u.recipeId?` • Recipe #${u.recipeId}`:""}</div><div class="readiness ${rc}">${esc(readiness)}</div>${u.sourceUrl?`<div class="recipe-info"><a href="${esc(u.sourceUrl)}" target="_blank">Open Bastion source ↗</a></div>`:""}</div>`}).join("")+`</div>`;
 $("#lootUseBody").innerHTML=html;$("#lootUseModal").classList.remove("hidden");document.body.style.overflow="hidden";
}
function closeLootUseModal(){$("#lootUseModal")?.classList.add("hidden");document.body.style.overflow="";}
function renderLiveFeed(){
 const el=$("#liveLootFeed");if(!el)return;if(!liveLootFeed.length){el.innerHTML='<p class="muted">No live Research loot yet.</p>';return}
 el.innerHTML=liveLootFeed.slice(0,30).map((x,i)=>{const css=x.value==="HIGH VALUE"?"high":x.value==="KEEP"?"keep":"unknown";return `<div class="live-loot-row ${css} clickable" tabindex="0" data-loot-index="${i}" title="Click to see Research uses"><div class="live-loot-head"><strong>${esc(x.item)}</strong><span class="live-value ${css}">${x.value}</span></div><div class="live-loot-looter">Looted by: ${esc(x.looter)}</div><div class="live-loot-meta">${esc(x.timestamp)}${x.uses?` • ${x.uses} verified use(s)`:""}</div>${x.ambiguous?`<div class="live-ambiguous">Multiple exact item IDs share this name; click to see all possibilities.</div>`:""}</div>`}).join("");
 document.querySelectorAll(".live-loot-row.clickable").forEach(row=>{const open=()=>openLootUseModal(liveLootFeed[Number(row.dataset.lootIndex)]);row.onclick=open;row.onkeydown=e=>{if(e.key==="Enter"||e.key===" "){e.preventDefault();open()}}});
}
function csvCell(v){const s=String(v??"");return /[",\r\n]/.test(s)?`"${s.replace(/"/g,'""')}"`:s}
function exportSessionLoot(){
 const headers=["Timestamp","Looter","Self","Item","Research Classification","Verified Uses","Ambiguous ID","Candidate Item IDs","Counted As Owned","Ownership Mode"];
 const rows=sessionLootEvents.map(x=>[
  x.timestamp,x.looter,x.self?"Yes":"No",x.item,x.researchValue||"Non-Research/Unmapped",
  x.verifiedUses||0,x.ambiguous?"Yes":"No",x.candidateIds||"",x.countedAsOwned?"Yes":"No",
  x.ownershipMode==="COUNT"?"Count as owned":"Track only"
 ]);
 const csv=[headers,...rows].map(r=>r.map(csvCell).join(",")).join("\r\n");
 const blob=new Blob([csv],{type:"text/csv;charset=utf-8"}),url=URL.createObjectURL(blob),a=document.createElement("a");
 const stamp=new Date().toISOString().replace(/[:.]/g,"-");
 a.href=url;a.download=`eq-research-loot-session-${stamp}.csv`;document.body.appendChild(a);a.click();a.remove();URL.revokeObjectURL(url);
}
function renderLiveSession(){
 const el=$("#liveSessionSummary");if(!el)return;
 const rows=[...liveLootCounts.entries()].sort((a,b)=>b[1]-a[1]||a[0].localeCompare(b[0]));
 if(!rows.length){el.innerHTML='<p class="muted">Nothing tracked this session.</p>';return}
 el.innerHTML=rows.slice(0,40).map(([name,qty])=>{
  const owned=liveOwnedCounts.get(name)||0;
  return `<div class="session-row"><span>${esc(name)}${owned?`<small class="owned-note">${owned} provisional owned</small>`:""}</span><strong>×${qty}</strong></div>`;
 }).join("");
}
function addCraftableAlerts(spells,evt){
 const el=$("#craftableAlerts");if(!el||!spells.length)return;
 const cards=spells.map(r=>`<div class="craftable-now"><strong>SPELL NOW CRAFTABLE</strong><div>${esc(r.spell)}${r.recipeId?` • Bastion #${r.recipeId}`:""}</div><small>${esc(evt.item)} completed the currently tracked requirements.</small></div>`).join("");
 el.innerHTML=cards+el.innerHTML;
 if(liveEnabled&&liveSettings().soundCraftable)beep("craftable");
}
function processLootEvent(evt,{isReplay=false}={}){
 if(!isReplay&&evt?.id!=null){
  const eventId=Number(evt.id);
  if(processedLiveEventIds.has(eventId))return false;
  processedLiveEventIds.add(eventId);
  if(processedLiveEventIds.size>5000){
   const keep=[...processedLiveEventIds].sort((a,b)=>b-a).slice(0,2500);
   processedLiveEventIds=new Set(keep);
  }
 }
 const s=liveSettings();
 const cls=classifyLoot(evt.item);
 if(!isReplay){
  const countedAsOwned=(s.ownershipMode==="COUNT")&&(s.includeOthers||evt.self);
  sessionLootEvents.push({
   id:evt.id??null,timestamp:evt.timestamp||"",looter:evt.looter||"Unknown",self:!!evt.self,
   item:evt.item||"",researchValue:cls.uses.length?cls.value:(/^words? of |^rune of |grimoire|compendium|memoir|writ|tome|signet|emblem|bolts|card of /i.test(evt.item)?"UNKNOWN":""),
   verifiedUses:cls.uses.length,ambiguous:!!cls.ambiguous,candidateIds:(cls.ids||[]).join("|"),
   countedAsOwned,ownershipMode:s.ownershipMode
  });
 }
 if(!s.includeOthers&&!evt.self)return;
 const before=readySpellKeys();

 // Always track session loot. Only COUNT mode adds a provisional owned quantity.
 const key=canonical(evt.item);
 liveLootCounts.set(key,(liveLootCounts.get(key)||0)+1);
 if(!isReplay&&s.ownershipMode==="COUNT")liveOwnedCounts.set(key,(liveOwnedCounts.get(key)||0)+1);
 evaluate();
 const after=readySpellKeys();
 const newly=recipeResults.filter(r=>after.has(r._key)&&!before.has(r._key));

 if(cls.uses.length){
  liveLootFeed.unshift({item:evt.item,looter:evt.looter||"Unknown",timestamp:evt.timestamp||"",value:cls.value,uses:cls.uses.length,ambiguous:cls.ambiguous,ids:cls.ids});
  if(liveEnabled){if(cls.value==="HIGH VALUE"&&s.soundHigh)beep("high");else if(s.soundAny)beep("research");}
 }else if(isReplay){
  // Replay intentionally includes only relevant items in the visible feed.
 } else {
  // Unknown loot is tracked only when it looks like a likely Research item.
  if(/^words? of |^rune of |grimoire|compendium|memoir|writ|tome|signet|emblem|bolts|card of /i.test(evt.item)){
   liveLootFeed.unshift({item:evt.item,looter:evt.looter||"Unknown",timestamp:evt.timestamp||"",value:"UNKNOWN",uses:0,ambiguous:false,ids:[]});
  }
 }
 renderLiveFeed();renderLiveSession();renderSummary();renderList();renderDetail();renderReverseLookup();
 if(newly.length)addCraftableAlerts(newly,evt);
 return true;
}
async function pollLiveMonitor(){
 if(livePollInFlight)return;
 livePollInFlight=true;
 try{
  const status=await fetch(apiUrl("/api/status"),{cache:"no-store"});
  if(!status.ok)throw Error(`status HTTP ${status.status}`);
  const sj=await status.json();
  if(Number(sj.lastEventId||0)<liveLastEventId){
   liveLastEventId=0;
   processedLiveEventIds.clear();
  }
  liveMonitorOnline=true;
  $("#liveStatus").textContent=corpusSyncInProgress?"SYNCING":"ONLINE";
  $("#liveStatus").className="live-status online";
  $("#liveMonitorMessage").textContent=`Watching ${sj.logFile||"EverQuest log"}${sj.character?` for ${sj.character}`:""}. Loot tracking is active.`;

  const requestSince=liveLastEventId;
  const r=await fetch(apiUrl(`/api/events?since=${requestSince}`),{cache:"no-store"});
  if(!r.ok)throw Error(`events HTTP ${r.status}`);
  const j=await r.json();
  const events=j.events||[];

  // Advance the cursor before doing any UI/recipe work so even if another
  // poll is triggered later it cannot request this same event batch again.
  liveLastEventId=Math.max(liveLastEventId,Number(j.lastEventId||0));

  for(const e of events){
   if(e?.id!=null&&Number(e.id)<=requestSince)continue;
   processLootEvent(e);
  }
 }catch(e){
  if(corpusSyncInProgress){
   if($("#liveStatus")){$("#liveStatus").textContent="SYNCING";$("#liveStatus").className="live-status online"}
   return;
  }
  liveMonitorOnline=false;
  if($("#liveStatus")){$("#liveStatus").textContent="OFFLINE";$("#liveStatus").className="live-status offline"}
  if($("#liveMonitorMessage"))$("#liveMonitorMessage").textContent=`Live companion not detected at ${LIVE_COMPANION_ORIGIN}: ${e.message}`;
 }finally{
  livePollInFlight=false;
 }
}
async function replayRecentLoot(){
 if(!liveMonitorOnline){$("#liveMonitorMessage").textContent="Start START-LIVE-MONITOR.bat first.";return}
 try{
  const r=await fetch(apiUrl("/api/replay-test"),{cache:"no-store"});
  const j=await r.json();
  if(!r.ok||j.ok===false)throw Error(j.error||`HTTP ${r.status}`);
  const events=j.events||[];
  let relevant=0,high=0,keep=0,unknownResearchLooking=0;
  const examples=[];
  for(const e of events){
   const c=classifyLoot(e.item);
   if(c.uses.length){
    relevant++;
    if(c.value==="HIGH VALUE")high++;else keep++;
    if(examples.length<8)examples.push(`${e.item} → ${c.value} (${c.uses.length} use${c.uses.length===1?"":"s"})`);
   }else if(/^words? of |^rune of |grimoire|compendium|memoir|writ|tome|signet|emblem|bolts|card of /i.test(e.item)){
    unknownResearchLooking++;
    if(examples.length<8)examples.push(`${e.item} → UNKNOWN`);
   }
  }
  const detail=examples.length?` Examples: ${examples.join(" • ")}`:"";
  $("#liveMonitorMessage").textContent=`Replay diagnostic only — no session counts changed. Scanned ${j.scannedLines??"recent"} lines; ${j.lootEvents??events.length} loot event(s); ${relevant} verified Research item(s) (${high} high value, ${keep} keep); ${unknownResearchLooking} Research-looking unknown.${detail}`;
 }catch(e){
  $("#liveMonitorMessage").textContent=`Recent-loot replay failed: ${e.message}`;
 }
}

function normalizeSyncedRecipe(r){
 const x={...r};
 let raw=(x.recipeName||x.spell||"").trim();
 const m=raw.match(/^\s*-\s*(.*?)\s+Tradeskill\s+-/i);
 if(m)raw=m[1].trim();
 raw=raw.replace(/\s+Tradeskill\s+-.*$/i,"").trim();
 const isSpell=x.isSpellRecipe??/^Spell:\s*/i.test(raw);
 x.recipeName=raw;
 x.isSpellRecipe=!!isSpell;
 x.spell=(isSpell?raw.replace(/^Spell:\s*/i,""):raw).trim();
 return x;
}
function mergeSyncedCorpus(sync){
 const normalized=(sync?.recipes||[]).map(normalizeSyncedRecipe);
 const fullyParsed=normalized.filter(r=>r&&r.recipeId&&r.components?.length&&r.trivial!=null&&r.complete!==false);
 const partial=normalized.filter(r=>r&&r.recipeId&&(!r.components?.length||r.complete===false));
 if(normalized.length){try{localStorage.setItem("eqResearchBastionSyncedCorpus",JSON.stringify(sync))}catch{}}

 const syncedSpells=fullyParsed.filter(r=>r.isSpellRecipe);
 const syncedResearch=fullyParsed.filter(r=>!r.isSpellRecipe);

 const byId=new Map();
 for(const r of BUILTIN_BASTION_RECIPES)byId.set(String(r.recipeId??r.recipeKey),r);
 for(const r of syncedSpells){
  const k=String(r.recipeId??r.recipeKey);
  if(!byId.has(k))byId.set(k,r);
 }
 BASTION_DATA.recipes=[...byId.values()];

 const existingSubs=[...(BASTION_DATA.subcombines||[])];
 const subById=new Map(existingSubs.map(r=>[String(r.recipeId??r.recipeKey??norm(r.name)),r]));
 for(const r of syncedResearch){
  const k=String(r.recipeId??r.recipeKey);
  if(!subById.has(k))subById.set(k,{...r,name:r.spell});
 }
 BASTION_DATA.subcombines=[...subById.values()];
 BASTION_DATA.unresolvedSyncedRecipes=[
   ...(sync?.unresolvedRecipes||[]),
   ...partial.map(r=>({recipeId:r.recipeId,sourceUrl:r.sourceUrl,status:"UNRESOLVED",reason:r.parseWarning||"Ingredient details unresolved"}))
 ];

 if(ACTIVE_DATA===BASTION_DATA){
  evaluate();renderSummary();renderList();renderDetail();renderReverseLookup();renderAudit();
 }
 return{
  totalDiscovered:Number(sync?.recipeIdsFound||normalized.length),
  fullyParsed:fullyParsed.length,
  spellRecipes:syncedSpells.length,
  otherResearch:syncedResearch.length,
  unresolved:BASTION_DATA.unresolvedSyncedRecipes.length,
  total:BASTION_DATA.recipes.length
 };
}
async function loadSyncedCorpus(){
 let loaded=false;
 try{
  const saved=JSON.parse(localStorage.getItem("eqResearchBastionSyncedCorpus")||"null");
  if(saved?.recipes?.length){
   const m=mergeSyncedCorpus(saved);loaded=true;
   $("#corpusSyncStatus").textContent=`Saved corpus restored • ${m.fullyParsed} fully parsed • ${m.spellRecipes} spell recipes • ${m.otherResearch} other Research recipes • ${m.unresolved} unresolved.`;
   $("#corpusSyncStatus").className="sync-good";
  }
 }catch{}
 try{
  const r=await fetch(apiUrl("/api/bastion-data"),{cache:"no-store"});
  if(r.ok){
   const j=await r.json();
   if(j.recipes?.length){
    const m=mergeSyncedCorpus(j);loaded=true;
    $("#corpusSyncStatus").textContent=`Disk corpus loaded • ${m.fullyParsed} fully parsed • ${m.spellRecipes} spell recipes • ${m.otherResearch} other Research recipes • ${m.unresolved} unresolved.`;
    $("#corpusSyncStatus").className="sync-good";
   }
  }
 }catch{}
 return loaded;
}
async function watchBastionSync(){
 const btn=$("#syncBastionCorpus");
 for(let i=0;i<3600;i++){
  try{
   const r=await fetch(apiUrl("/api/bastion-sync-status"),{cache:"no-store"});
   const s=await r.json();
   const extra=` • pages ${s.pagesScanned||0} • IDs ${s.recipeIdsFound||0} • parsed ${s.recipeCount||0} • errors ${s.errors||0}`;
   $("#corpusSyncStatus").textContent=(s.message||s.state)+extra;
   $("#corpusSyncStatus").className=s.state==="error"?"sync-bad":s.state==="complete"?"sync-good":"sync-working";
   if(s.state==="complete"){
    await loadSyncedCorpus();
    btn.disabled=false;btn.textContent="Sync Complete Bastion Research Data";
    return;
   }
   if(s.state==="error"){
    btn.disabled=false;btn.textContent="Sync Complete Bastion Research Data";
    return;
   }
  }catch(e){
   $("#corpusSyncStatus").textContent=`Sync status error: ${e.message}`;
   $("#corpusSyncStatus").className="sync-bad";
  }
  await new Promise(r=>setTimeout(r,1000));
 }
 btn.disabled=false;btn.textContent="Sync Complete Bastion Research Data";
}
async function syncBastionCorpus(){
 if(!liveMonitorOnline){
  $("#corpusSyncStatus").textContent="Start the app with START-LIVE-MONITOR.bat before syncing.";
  $("#corpusSyncStatus").className="sync-bad";
  return;
 }
 const btn=$("#syncBastionCorpus");
 btn.disabled=true;btn.textContent="Starting sync…";
 try{
  const r=await fetch(apiUrl("/api/bastion-sync"),{cache:"no-store"});
  const j=await r.json();
  if(!j.ok)throw Error(j.error||"Could not start sync");
  $("#corpusSyncStatus").textContent=j.alreadyRunning?"Sync is already running.":"Bastion sync started in the background.";
  $("#corpusSyncStatus").className="sync-working";
  await watchBastionSync();
 }catch(e){
  $("#corpusSyncStatus").textContent=`Sync failed to start: ${e.message}`;
  $("#corpusSyncStatus").className="sync-bad";
  btn.disabled=false;btn.textContent="Sync Complete Bastion Research Data";
 }
}
async function loadSpellMetadata(){
 let loaded=false;
 try{
  const saved=JSON.parse(localStorage.getItem("eqResearchBastionSpellMetadata")||"null");
  if(saved?.spells?.length){
   const cov=mergeSpellMetadata(saved);loaded=true;
   $("#spellMetadataStatus").textContent=`Saved Bastion metadata restored • ${cov.mapped}/${cov.total} Research spell names mapped • ${cov.withLevels} with complete class/level data.`;
  }
 }catch{}
 try{
  const r=await fetch(apiUrl("/api/bastion-spell-metadata"),{cache:"no-store"});
  if(r.ok){
   const j=await r.json();
   if(j.spells?.length){
    try{localStorage.setItem("eqResearchBastionSpellMetadata",JSON.stringify(j))}catch{}
    const cov=mergeSpellMetadata(j);loaded=true;
    $("#spellMetadataStatus").textContent=`Bastion spell metadata loaded • ${cov.mapped}/${cov.total} Research spell names mapped • ${cov.withLevels} with complete class/level data • ${(j.unresolved||[]).length} unresolved.`;
   }
  }
 }catch{}
 if(!loaded){
  const cov=metadataCoverage();
  $("#spellMetadataStatus").textContent=`Packaged metadata only • ${cov.mapped}/${cov.total} Research spell names mapped. Run the Bastion spell metadata sync for fuller coverage.`;
 }
 return loaded;
}
async function watchSpellMetadataSync(){
 const btn=$("#syncSpellMetadata");
 let startingTicks=0,lastProgress="";
 for(let i=0;i<3600;i++){
  try{
   const r=await fetch(apiUrl("/api/bastion-spell-metadata-status"),{cache:"no-store"}),s=await r.json();
   const extra=` • searches ${s.pagesScanned||0} • targets ${s.targetSpells||0} • matched ${s.matchedNames||0} • parsed ${s.parsedSpells||0} • errors ${s.errors||0}`;
   const progress=`${s.state}|${s.pagesScanned||0}|${s.targetSpells||0}|${s.matchedNames||0}|${s.parsedSpells||0}|${s.errors||0}`;
   $("#spellMetadataStatus").textContent=(s.message||s.state)+extra;
   if(progress===lastProgress&&(s.state==="starting"||s.state==="idle"))startingTicks++;else startingTicks=0;
   lastProgress=progress;
   if(s.state==="complete"){
    await loadSpellMetadata();btn.disabled=false;btn.textContent="Sync Spell Class / Level Data";return;
   }
   if(s.state==="error"){
    btn.disabled=false;btn.textContent="Retry Spell Class / Level Sync";return;
   }
   if(startingTicks>=15){
    let detail="";
    try{
     const dr=await fetch(apiUrl("/api/bastion-spell-metadata-diagnostics"),{cache:"no-store"});
     if(dr.ok){
      const dj=await dr.json();
      detail=(dj.stderr||dj.stdout||"").trim();
      if(!detail&&dj.jobState)detail=`PowerShell job state: ${dj.jobState}${dj.jobId?` (job ${dj.jobId})`:""}`;
     }
    }catch{}
    $("#spellMetadataStatus").textContent=detail?
      `Metadata sync child process failed: ${detail}`:
      "Metadata sync did not begin within 15 seconds. No child-process diagnostic output was captured.";
    btn.disabled=false;btn.textContent="Retry Spell Class / Level Sync";return;
   }
  }catch(e){
   $("#spellMetadataStatus").textContent=`Spell metadata sync status error: ${e.message}`;
  }
  await new Promise(r=>setTimeout(r,1000));
 }
 btn.disabled=false;btn.textContent="Sync Spell Class / Level Data";
}
async function syncSpellMetadata(){
 if(!liveMonitorOnline){
  $("#spellMetadataStatus").textContent="Start the demo with START-LIVE-MONITOR.bat before syncing.";
  return;
 }
 const btn=$("#syncSpellMetadata");btn.disabled=true;btn.textContent="Starting metadata sync…";
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),10000);
 try{
  const r=await fetch(apiUrl("/api/bastion-spell-metadata-sync"),{cache:"no-store",signal:controller.signal});
  clearTimeout(timer);
  const j=await r.json();
  if(!j.ok)throw Error(j.error||"Could not start spell metadata sync");
  $("#spellMetadataStatus").textContent=j.alreadyRunning?"Spell metadata sync is already running.":`Bastion spell metadata sync started${j.jobId?` (PowerShell job ${j.jobId})`:""}.`;
  await watchSpellMetadataSync();
 }catch(e){
  clearTimeout(timer);
  const msg=e.name==="AbortError"?"the local companion did not answer the start request within 10 seconds":e.message;
  $("#spellMetadataStatus").textContent=`Spell metadata sync failed to start: ${msg}`;
  btn.disabled=false;btn.textContent="Retry Spell Class / Level Sync";
 }
}
async function changeLogFile(){
 if(!liveMonitorOnline){$("#liveMonitorMessage").textContent="Start START-LIVE-MONITOR.bat first.";return}
 try{
  const r=await fetch(apiUrl("/api/change-log"),{cache:"no-store"});
  const j=await r.json();
  if(j.ok)$("#liveMonitorMessage").textContent=`New log saved: ${j.logPath}. Restart START-LIVE-MONITOR.bat to watch it.`;
 }catch(e){
  $("#liveMonitorMessage").textContent=`Could not change log file: ${e.message}`;
 }
}
function setupLiveUI(){
 loadLiveSettings();
 if($("#enableLiveAlerts"))$("#enableLiveAlerts").textContent=liveEnabled?"Mute Sounds / Attention Alerts":"Enable Sounds / Attention Alerts";
 if($("#liveMonitorMessage")&&liveEnabled)$("#liveMonitorMessage").textContent="Sounds/attention alerts are enabled by default. Loot tracking is always active while connected.";
 const unlockAudio=()=>{if(liveEnabled)ensureAudio();document.removeEventListener("pointerdown",unlockAudio);document.removeEventListener("keydown",unlockAudio)};
 document.addEventListener("pointerdown",unlockAudio,{once:true});
 document.addEventListener("keydown",unlockAudio,{once:true});
 ["liveIncludeOthers","liveClassOnly","soundHighValue","soundAnyResearch","soundCraftable","highValueThreshold","liveVolume","lootOwnershipMode"].forEach(id=>$("#"+id)?.addEventListener("input",saveLiveSettings));
 $("#enableLiveAlerts")?.addEventListener("click",()=>{
  ensureAudio();liveEnabled=!liveEnabled;$("#enableLiveAlerts").textContent=liveEnabled?"Mute Sounds / Attention Alerts":"Enable Sounds / Attention Alerts";
  $("#liveMonitorMessage").textContent=liveEnabled?"Sounds/attention alerts enabled. Loot tracking is always active while connected.":"Sounds muted. Loot tracking remains active.";
 });
 $("#testLiveReplay")?.addEventListener("click",()=>{ensureAudio();replayRecentLoot()});
 $("#exportSessionLoot")?.addEventListener("click",exportSessionLoot);
 $("#lootOwnershipMode")?.addEventListener("change",()=>{
  saveLiveSettings();
  const mode=$("#lootOwnershipMode").value;
  $("#ownershipModeStatus").textContent=mode==="COUNT"?
   "New tracked loot will count provisionally toward your inventory until a Magelo refresh confirms it.":
   "New loot will be tracked and classified, but will not count toward recipe readiness.";
 });
 
 
 document.addEventListener("click",e=>{
 if(e.target.closest?.("#closeLootUseModal")){e.preventDefault();e.stopPropagation();closeLootUseModal();return}
 if(e.target.id==="lootUseModal"){e.preventDefault();closeLootUseModal()}
});
document.addEventListener("keydown",e=>{if(e.key==="Escape")closeLootUseModal()});
 $("#changeLogFile")?.addEventListener("click",changeLogFile);
 $("#syncBastionCorpus")?.addEventListener("click",syncBastionCorpus);
 $("#syncSpellMetadata")?.addEventListener("click",syncSpellMetadata);
 pollLiveMonitor();loadSyncedCorpus();loadSpellMetadata();setInterval(pollLiveMonitor,1000);
}

function normalizeMageloInput(v){
 const s=(v||"").trim(),m=s.match(/characters\.bastiongame\.com\/character\/([^/?#]+)/i);
 return (m?m[1]:s).replace(/[^A-Za-z0-9_-]/g,"").toLowerCase();
}
function renderMagelo(){
 const badge=$("#mageloStatusBadge"),status=$("#mageloStatus"),stats=$("#mageloStats");if(!badge||!status||!stats)return;
 if(!mageloMeta){badge.textContent="NOT LOADED";badge.className="live-status offline";stats.innerHTML="";return}
 badge.textContent="LOADED";badge.className="live-status online";
 const c=mageloMeta.counts||{};
 const d=mageloMeta.diagnostics||{};
 status.innerHTML=`Loaded <strong>${esc(mageloMeta.character)}</strong> from Bastion Magelo${mageloMeta.bankHidden?`<div class="magelo-warning">Bank inventory is hidden because this character is Anonymous/Roleplay. The Magelo baseline is incomplete.</div>`:""}${(c.total||0)===0?`<div class="magelo-warning">The Magelo page loaded, but no inventory rows were recognized. Parser strategy: ${d.strategy||"unknown"}; payload found: ${d.payloadFound?"yes":"no"}.</div>`:""}`;
 stats.innerHTML=[["Inventory IDs",c.inventory||0],["Bank IDs",c.bank||0],["Shared Bank IDs",c.sharedBank||0],["Gear IDs",c.gear||0],["Total entries",c.total||0]].map(([a,b])=>`<article><span>${a}</span><strong>${b}</strong></article>`).join("");
}
async function loadMagelo(value=null){
 if(!liveMonitorOnline){$("#mageloStatus").textContent="Start START-LIVE-MONITOR.bat first.";return}
 const input=normalizeMageloInput(value!==null&&value!==undefined?value:$("#mageloCharacter").value);if(!input){$("#mageloStatus").textContent="Enter a character name or Bastion Magelo URL.";return}
 $("#refreshMagelo").disabled=true;$("#refreshMagelo").textContent="Loading Magelo…";
 try{
  const r=await fetch(apiUrl(`/api/magelo?character=${encodeURIComponent(input)}`),{cache:"no-store"}),j=await r.json();
  if(!r.ok||!j.ok)throw Error(j.error||`HTTP ${r.status}`);
  const nextMageloInventory=(j.data.items||[]).map(x=>({source:"Magelo",name:x.name,id:Number(x.id),count:Number(x.count||1),location:x.location,character:x.character}));
  const nextCounts=mageloCountMap(nextMageloInventory);
  const reconciled=reconcileOwnedLootWithMagelo(previousMageloCounts,nextCounts);
  mageloMeta=j.data;mageloInventory=nextMageloInventory;previousMageloCounts=nextCounts;
  $("#mageloCharacter").value=j.data.character;try{localStorage.setItem("eqResearchMageloCharacter",j.data.character)}catch{}
  rebuildAggregated();render();
  if(reconciled.length){
   const n=reconciled.reduce((a,x)=>a+x.qty,0);
   $("#mageloStatus").innerHTML+=`<div class="magelo-reconcile">Reconciled ${n} provisional live-loot item${n===1?"":"s"} now present in Magelo; no duplicate inventory was added.</div>`;
  }
 }catch(e){$("#mageloStatus").textContent=`Magelo load failed: ${e.message}`;$("#mageloStatusBadge").textContent="ERROR";$("#mageloStatusBadge").className="live-status offline"}
 finally{$("#refreshMagelo").disabled=false;$("#refreshMagelo").textContent="Load / Refresh Magelo"}
}
async function restoreMagelo(){
 let saved="";try{saved=localStorage.getItem("eqResearchMageloCharacter")||""}catch{}
 if(saved){$("#mageloCharacter").value=saved;await loadMagelo(saved)}
}
function clearMagelo(){
 mageloInventory=[];mageloMeta=null;previousMageloCounts=null;try{localStorage.removeItem("eqResearchMageloCharacter")}catch{}
 $("#mageloCharacter").value="";rebuildAggregated();render();
}
function renderChars(){const el=$("#characterChips");if(!el)return;el.innerHTML=inventorySources.map(s=>`<div class="character-chip"><strong>${esc(s.character)}</strong><span>${s.rows} rows</span></div>`).join("")}
function renderEvidence(){const el=$("#evidenceQueue");if(!el)return;const ev=ACTIVE_DATA.ownedComponentEvidence||{};if(ACTIVE_DATA!==BASTION_DATA||!aggregated.length){el.innerHTML='<p class="muted">Load Magelo or an inventory file with Bastion rules enabled.</p>';return}const cards=[];for(const[id,x]of Object.entries(ev)){const owned=aggregated.find(a=>a.id===Number(id));if(owned)cards.push({id,x,owned})}el.innerHTML=cards.length?cards.map(o=>`<div><strong>${esc(o.x.name)} #${o.id}</strong> — ${o.owned.count} on hand<br><small>${(o.x.researchUses||[]).join(", ")}</small></div>`).join("<hr>"):'<p class="muted">No matching evidence rows.</p>'}
function renderAudit(){const cardsEl=$("#auditCards"),detailsEl=$("#auditDetails");if(!cardsEl||!detailsEl)return;const r=ACTIVE_DATA.recipes||[];cardsEl.innerHTML=[["Recipe rows",r.length],["Exact mapped",r.filter(x=>x.complete!==false).length],["Confirmed pending",catalogPendingRows().length],["Evidence items",Object.keys(ACTIVE_DATA.ownedComponentEvidence||{}).length]].map(([a,b])=>`<article><span>${a}</span><strong>${b}</strong></article>`).join("");const unresolved=ACTIVE_DATA.unresolvedSyncedRecipes||[];
 detailsEl.innerHTML=`<p class="muted">${esc(ACTIVE_DATA.scope||"")}</p>${unresolved.length?`<details><summary>${unresolved.length} unresolved synced Research recipe(s)</summary><div class="evidence-line">${unresolved.map(u=>`#${u.recipeId} — ${esc(u.reason||"Unresolved")}${u.sourceUrl?` — <a href="${esc(u.sourceUrl)}" target="_blank">Bastion ↗</a>`:""}`).join("<br>")}</div></details>`:""}`}
function render(){evaluate();renderMagelo();renderChars();renderInventoryBrowser();renderSummary();renderList();renderDetail();renderReverseLookup();renderEvidence();renderAudit()}
async function loadFiles(fs){
 const fileStatus=$("#inventoryFileStatus");
 if(fileStatus)fileStatus.textContent="Loading inventory output file…";
 const all=[];
 for(const f of fs){
  const ch=filenameCharacter(f.name),p=parseInventory(await f.text(),ch);
  all.push(...p);
  inventorySources.push({character:ch,rows:p.length});
 }
 inventory.push(...all);
 rebuildAggregated();
 if(fileStatus)fileStatus.textContent=`Inventory file loaded • ${inventorySources.length} file(s) • ${aggregated.length} unique item IDs combined.`;
 render();
}
["classFilter","statusFilter","spellSearch","characterLevel","researchSkill"].forEach(id=>{
 const el=$("#"+id);
 if(el)el.oninput=()=>{renderSummary();renderList();renderDetail()};
});
["reverseSearch","reverseClassFilter","reverseStatusFilter"].forEach(id=>$("#"+id)?.addEventListener("input",renderReverseLookup));

$("#quickLootButton")?.addEventListener("click",runQuickLookup);$("#quickLootSearch")?.addEventListener("keydown",e=>{if(e.key==="Enter")runQuickLookup()});

$("#refreshMagelo")?.addEventListener("click",()=>{$("#mageloStatus").textContent="Contacting Bastion Magelo…";loadMagelo()});
$("#inventoryFileInstead")?.addEventListener("click",()=>$("#inventoryFiles")?.click());
$("#inventoryFiles")?.addEventListener("change",e=>{if(e.target.files&&e.target.files.length)loadFiles([...e.target.files])});

$("#mageloCharacter")?.addEventListener("keydown",e=>{if(e.key==="Enter")loadMagelo()});
$("#clearMagelo")?.addEventListener("click",clearMagelo);

const UPDATE_API="https://api.github.com/repos/jmdeland/eq-spell-research-assistant/releases/latest";
let latestUpdateInfo=null;
let verifiedUpdateInfo=null;
function parseVersionParts(v){
 const clean=String(v||"").replace(/^v/i,"").split("-")[0];
 return clean.split(".").map(x=>Number(x)||0).slice(0,3).concat([0,0,0]).slice(0,3);
}
function compareStableVersions(a,b){
 const aa=parseVersionParts(a),bb=parseVersionParts(b);
 for(let i=0;i<3;i++){if(aa[i]!==bb[i])return aa[i]>bb[i]?1:-1}
 return 0;
}
function updateBadge(text,kind){
 const el=$("#updateStatusBadge");if(!el)return;
 el.textContent=text;el.className=`live-status ${kind||"offline"}`;
}
function setUpdateStatus(html){const el=$("#updateStatus");if(el)el.innerHTML=html}
function renderReleaseNotes(info){
 const box=$("#updateReleaseNotes");if(!box)return;
 const body=String(info?.body||"").trim();
 if(!body){box.classList.add("hidden");box.innerHTML="";return}
 box.innerHTML=`<h3>${esc(info.name||info.tagName||"Release notes")}</h3><pre>${esc(body)}</pre>`;
 box.classList.remove("hidden");
}
async function checkForUpdates(){
 const btn=$("#checkForUpdates"),dl=$("#downloadLatestUpdate"),install=$("#installVerifiedUpdate"),link=$("#openReleasePage");
 verifiedUpdateInfo=null;if(install)install.disabled=true;
 if(btn){btn.disabled=true;btn.textContent="Checking…"}
 if(dl)dl.disabled=true;
 updateBadge("CHECKING","offline");setUpdateStatus("Contacting GitHub stable releases…");
 try{
  if(!liveMonitorOnline)throw Error("Start START-LIVE-MONITOR.bat first. Update checks run through the local companion.");
  const r=await fetch(apiUrl("/api/update-check"),{cache:"no-store"}),j=await r.json();
  if(!r.ok||!j.ok)throw Error(j.error||`HTTP ${r.status}`);
  latestUpdateInfo=j;const cmp=compareStableVersions(j.latestVersion,j.installedStableVersion);
  if(link&&j.releaseUrl){link.href=j.releaseUrl;link.classList.remove("hidden")}
  renderReleaseNotes(j);
  if(j.updateAvailable){
   updateBadge("UPDATE AVAILABLE","online");
   setUpdateStatus(`<strong>${esc(j.latestTag)}</strong> is available. Installed stable baseline: ${esc(j.installedStableVersion)}. Asset: ${esc(j.assetName)}.`);
   if(dl){dl.disabled=false;dl.textContent=`Download & Verify ${j.latestTag}`}
  }else if(j.channel==="demo"&&cmp<0){
   updateBadge("DEMO AHEAD","online");
   setUpdateStatus(`This demo (${esc(j.installedVersion)}) is ahead of the latest stable release (${esc(j.latestTag)}). Use the test download to verify the updater pipeline without installing anything.`);
   if(dl){dl.disabled=false;dl.textContent=`Test Verified Download ${j.latestTag}`}
  }else{
   updateBadge("UP TO DATE","online");
   setUpdateStatus(`You are up to date on the stable channel (${esc(j.latestTag)}). You can still test downloading and verifying the current release asset.`);
   if(dl){dl.disabled=false;dl.textContent=`Test Verified Download ${j.latestTag}`}
  }
 }catch(e){latestUpdateInfo=null;updateBadge("CHECK FAILED","offline");setUpdateStatus(`<span class="update-error">Update check failed: ${esc(e.message)}</span>`)}
 finally{if(btn){btn.disabled=false;btn.textContent="Check for Updates"}}
}
async function downloadLatestUpdate(){
 const dl=$("#downloadLatestUpdate"),barWrap=$("#updateProgress"),bar=$("#updateProgressBar");
 if(dl){dl.disabled=true;dl.textContent="Downloading…"}
 if(barWrap)barWrap.classList.remove("hidden");if(bar)bar.style.width="35%";
 setUpdateStatus(`Downloading ${esc(latestUpdateInfo?.assetName||"latest stable release")} to the local update staging folder…`);
 try{
  if(!liveMonitorOnline)throw Error("Local companion is offline.");
  const r=await fetch(apiUrl("/api/update-download"),{cache:"no-store"}),j=await r.json();
  if(bar)bar.style.width="85%";
  if(!r.ok||!j.ok)throw Error(j.error||`HTTP ${r.status}`);
  if(bar)bar.style.width="100%";
  verifiedUpdateInfo=j;
  const install=$("#installVerifiedUpdate");if(install){install.disabled=false;install.textContent=`Install Verified ${j.latestTag||latestUpdateInfo?.latestTag||"Update"}`}
  updateBadge("VERIFIED","online");
  setUpdateStatus(`<strong>Verified download complete.</strong> ${esc(j.fileName)} • ${esc(j.sizeText)}<br><span class="muted">SHA-256: ${esc(j.sha256)}</span><br><span class="muted">Staged at: ${esc(j.path)}</span><div class="update-warning"><strong>Safe-install test:</strong> installing will close this demo, rename the entire current folder to a timestamped backup, install ${esc(j.latestTag||latestUpdateInfo?.latestTag||"the verified release")} into this folder path, preserve monitor-config.json, and restart the app.</div>`);
 }catch(e){updateBadge("DOWNLOAD FAILED","offline");setUpdateStatus(`<span class="update-error">Verified download failed: ${esc(e.message)}</span>`);if(bar)bar.style.width="0%"}
 finally{setTimeout(()=>barWrap?.classList.add("hidden"),1200);if(dl){dl.disabled=false;dl.textContent=latestUpdateInfo?`Test Verified Download ${latestUpdateInfo.latestTag}`:"Test Verified Download"}}
}
async function installVerifiedUpdate(){
 const install=$("#installVerifiedUpdate");
 if(!verifiedUpdateInfo){setUpdateStatus('<span class="update-error">Download and verify the release first.</span>');return}
 const tag=verifiedUpdateInfo.latestTag||latestUpdateInfo?.latestTag||"the verified release";
 const isDemo=String(latestUpdateInfo?.channel||"").toLowerCase()==="demo";
 const warning=isDemo
   ? `TEST INSTALL: This will replace this demo folder with stable ${tag}. The complete current demo folder will be renamed as a timestamped backup beside it. Continue?`
   : `Install ${tag}? The complete current application folder will be backed up before replacement. Continue?`;
 if(!confirm(warning))return;
 if(install){install.disabled=true;install.textContent="Preparing safe install…"}
 updateBadge("INSTALLING","offline");
 setUpdateStatus(`Preparing safe install of <strong>${esc(tag)}</strong>… The companion will close, the current folder will be backed up, and the application should restart automatically.`);
 try{
  const r=await fetch(apiUrl("/api/update-install"),{cache:"no-store"}),j=await r.json();
  if(!r.ok||!j.ok)throw Error(j.error||`HTTP ${r.status}`);
  setUpdateStatus(`<strong>Updater launched.</strong> ${esc(j.latestTag||tag)}<br><span class="muted">Backup will be created at: ${esc(j.backupPath)}</span><br><span class="muted">This page will disconnect while files are replaced. The application should reopen automatically.</span>`);
  updateBadge("RESTARTING","offline");
 }catch(e){
  updateBadge("INSTALL FAILED","offline");
  setUpdateStatus(`<span class="update-error">Safe install could not start: ${esc(e.message)}</span>`);
  if(install){install.disabled=false;install.textContent=`Install Verified ${tag}`}
 }
}
function setupUpdaterUI(){
 $("#checkForUpdates")?.addEventListener("click",checkForUpdates);
 $("#downloadLatestUpdate")?.addEventListener("click",downloadLatestUpdate);
 $("#installVerifiedUpdate")?.addEventListener("click",installVerifiedUpdate);
}

setupUpdaterUI();
setupLiveUI();
setTimeout(restoreMagelo,700);
render();
