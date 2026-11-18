(() => {
'use strict';
const SUPABASE_URL='https://druugcvqxxanhtdkqnjd.supabase.co';
const SUPABASE_KEY='sb_publishable_M6W3DMCqPcH92cT96ioP5A_wi64QmcA';
const $=id=>document.getElementById(id);
if(!window.supabase?.createClient){$('login-message').textContent='No se pudo cargar el servicio de acceso DEMO.';return;}
const db=window.supabase.createClient(SUPABASE_URL,SUPABASE_KEY);
let user=null,profile=null,companies=[],activeCompany=null,isGlobal=false,items=[],clients=[],sellerRows=[],cart=[],orders=[],tier=1,estado='pendiente',condicion='Contado',pendingImport=null;
const money=n=>'Gs. '+Math.round(Number(n||0)).toLocaleString('es-PY');
const safe=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const timeout=(p,label)=>Promise.race([p,new Promise((_,rej)=>setTimeout(()=>rej(new Error(label+' no respondió.')),12000))]);
function gate(msg){$('login').hidden=false;$('app').hidden=true;$('login-message').textContent=msg||'Acceso protegido';}
function showPanel(id){document.querySelectorAll('main .panel').forEach(p=>p.classList.toggle('active',p.id===id));document.querySelectorAll('.tabs [data-panel]').forEach(b=>b.classList.toggle('active',b.dataset.panel===id));}
async function loadCompanyContext(u){
 const {data:gr,error:ge}=await timeout(db.rpc('ab_is_global_superadmin'),'La consulta de permisos globales');
 if(ge)throw ge;
 isGlobal=gr===true;
 let memberships=[];
 if(isGlobal){
  const {data,error}=await timeout(db.from('companies').select('id,code,name,status').eq('status','active').order('name'),'La lista de empresas');
  if(error)throw error;companies=data||[];
 }else{
  const {data,error}=await timeout(db.from('company_memberships').select('company_id,role').eq('user_id',u.id).eq('status','active'),'Las empresas asignadas');
  if(error)throw error;memberships=data||[];
  if(!memberships.length)throw new Error('Tu usuario no tiene una membresía activa en ninguna empresa.');
  const ids=[...new Set(memberships.map(m=>m.company_id))];
  const {data:rows,error:ce}=await timeout(db.from('companies').select('id,code,name,status').in('id',ids).eq('status','active').order('name'),'Los datos de las empresas');
  if(ce)throw ce;
  companies=(rows||[]).map(c=>({...c,memberRole:memberships.find(m=>m.company_id===c.id)?.role||'seller'}));
 }
 if(!companies.length)throw new Error('No hay empresas activas disponibles para esta cuenta.');
 const saved=companies.find(c=>c.id===activeCompany?.id);
 activeCompany=saved||companies[0];
 profile={role:isGlobal?'company_admin':(activeCompany.memberRole||'seller')};
 const select=$('company-select');
 select.innerHTML=companies.map(c=>'<option value="'+safe(c.id)+'">'+safe(c.name)+'</option>').join('');
 select.value=activeCompany.id;
 select.hidden=companies.length<2;
 $('company-role').textContent=isGlobal?'Superadministrador global':(profile.role==='company_admin'?'Administrador de empresa':'Vendedor');
 $('dashboard-date').textContent='Actividad de hoy · '+activeCompany.name;
 $('dashboard-scope').textContent='Información de '+activeCompany.name+'.';
}
async function switchCompany(companyId){
 const next=companies.find(c=>c.id===companyId);if(!next||next.id===activeCompany?.id)return;
 const previous=activeCompany,select=$('company-select');
 select.disabled=true;
 activeCompany=next;profile={role:isGlobal?'company_admin':(next.memberRole||'seller')};
 cart=[];orders=[];items=[];clients=[];sellerRows=[];
 $('cliente-input').value='';$('cliente-input').dataset.code='';$('cliente-suggestions').classList.remove('open');$('vendedor-input').value='';
 $('order-message').textContent='';$('discount-input').value='0';
 $('company-role').textContent=isGlobal?'Superadministrador global':(profile.role==='company_admin'?'Administrador de empresa':'Vendedor');
 $('dashboard-date').textContent='Actividad de hoy · '+activeCompany.name;
 $('dashboard-scope').textContent='Información de '+activeCompany.name+'.';
 try{
  await loadData();
  $('cloud-status-slot').textContent='Conectado · '+activeCompany.name;
 }catch(e){
  activeCompany=previous;profile={role:isGlobal?'company_admin':(previous.memberRole||'seller')};select.value=previous.id;
  cart=[];orders=[];items=[];clients=[];sellerRows=[];
  $('company-role').textContent=isGlobal?'Superadministrador global':(profile.role==='company_admin'?'Administrador de empresa':'Vendedor');
  $('dashboard-date').textContent='Actividad de hoy · '+previous.name;
  $('dashboard-scope').textContent='Información de '+previous.name+'.';
  $('cloud-status-slot').textContent='No se pudo cambiar de empresa: '+e.message;
  try{await loadData();}catch(reloadError){$('cloud-status-slot').textContent='Error al recuperar '+previous.name+': '+reloadError.message;}
 }finally{select.disabled=false;}
}
function total(){return cart.reduce((s,x)=>s+x['p'+tier]*x.qty,0);}
function render(){
 const q=$('search-input').value.trim().toLowerCase(),filtered=items.filter(x=>[x.c,x.b,x.d].some(v=>String(v||'').toLowerCase().includes(q)));
 $('result-count').textContent=filtered.length+' productos · mostrando '+Math.min(filtered.length,100)+' · '+(activeCompany?.name||'empresa');
 $('item-list').innerHTML=filtered.slice(0,100).map(x=>'<article class="item-card"><div class="item-top"><span class="item-code">'+safe(x.c)+'</span><span class="item-stock">CENTRAL '+Number(x.sc||0)+' · CDE '+Number(x.sd||0)+'</span></div><div class="item-desc">'+safe(x.d)+'</div><div class="item-bottom"><strong class="item-price">'+money(x['p'+tier])+'</strong><div class="item-actions"><input class="qty-input" type="number" min="1" value="1" aria-label="Cantidad" data-qty="'+safe(x.c)+'"><button class="add-btn" data-add="'+safe(x.c)+'">Agregar</button></div></div></article>').join('')||'<div class="empty-state">No se encontraron productos.</div>';
 $('item-list').querySelectorAll('[data-add]').forEach(b=>b.onclick=()=>{const code=b.dataset.add,qty=Math.max(1,Number($('item-list').querySelector('[data-qty="'+CSS.escape(code)+'"]').value)||1);add(code,qty);});
 $('order-list').innerHTML=cart.map((x,i)=>'<article class="order-card"><div class="order-top"><div class="order-code-desc"><strong>'+safe(x.d)+'</strong><small>'+safe(x.c)+' · '+x.qty+' unidad(es) · Disponible: '+(Number(x.sc||0)+Number(x.sd||0))+' (CENTRAL '+Number(x.sc||0)+' / CDE '+Number(x.sd||0)+')</small></div><button class="order-remove" data-remove="'+i+'" aria-label="Quitar">×</button></div><div class="order-bottom"><span>'+money(x['p'+tier])+' c/u</span><strong class="line-subtotal">'+money(x['p'+tier]*x.qty)+'</strong></div></article>').join('');
 $('order-list').querySelectorAll('[data-remove]').forEach(b=>b.onclick=()=>{cart.splice(Number(b.dataset.remove),1);render();});
 const sub=total(),discount=Math.min(100,Math.max(0,Number($('discount-input').value)||0)),off=sub*discount/100,grand=sub-off;
 $('total-value').textContent=money(grand);$('discount-total').textContent='Subtotal: '+money(sub);$('discount-value').textContent='Descuento: '+money(off);
 $('order-empty').hidden=cart.length>0;$('tab-order-count').textContent=cart.reduce((s,x)=>s+x.qty,0);
 $('dashboard-units').textContent=items.length;$('dashboard-sales').textContent=clients.length;
 $('dashboard-orders').textContent=orders.length;$('dashboard-pending').textContent=orders.filter(o=>o.payload?.estado!=='confirmado').length;
 $('archive-summary-count').textContent=orders.length+' pedidos';$('archive-summary-value').textContent=money(orders.reduce((sum,o)=>sum+Number(o.payload?.total||0),0));$('tab-archive-count').textContent=orders.length;
 $('archive-list').innerHTML=orders.map(o=>'<article class="order-card"><div class="order-top"><div><strong>'+safe(o.payload?.cliente||'Pedido DEMO')+'</strong><small>'+safe(o.payload?.vendedor||'')+' · '+new Date(o.updated_at).toLocaleString('es-PY')+'</small></div><strong>'+money(o.payload?.total)+'</strong></div></article>').join('');
 $('archive-empty').hidden=orders.length>0;
 renderStock();
}
function add(code,qty){const item=items.find(x=>String(x.c)===String(code));if(!item)return;const row=cart.find(x=>x.c===item.c);if(row)row.qty+=qty;else cart.push({...item,qty});render();}
async function fetchAllRows(makeQuery,label){
 const all=[];const pageSize=1000;
 for(let from=0;;from+=pageSize){
  const {data,error}=await timeout(makeQuery().range(from,from+pageSize-1), 'Carga de '+label);
  if(error)throw error;
  const page=data||[];all.push(...page);
  if(page.length<pageSize)break;
 }
 return all;
}
function renderStock(){
 const q=$('stock-search').value.trim().toLowerCase();
 const filtered=items.filter(x=>[x.c,x.d].some(v=>String(v||'').toLowerCase().includes(q)));
 const canAdjust=isGlobal||profile?.role==='company_admin';
 $('stock-list').innerHTML=filtered.slice(0,100).map(x=>{
  const code=safe(x.c),central=Number(x.sc||0),cde=Number(x.sd||0);
  const controls=canAdjust?'<div class="stock-edit-grid"><label>CENTRAL<input type="number" min="0" step="0.001" inputmode="decimal" data-stock-qty="'+code+'" data-location="CENTRAL" value="'+central+'"></label><button type="button" class="stock-save-btn" data-stock-set="'+code+'" data-location="CENTRAL">Actualizar CENTRAL</button><label>CDE<input type="number" min="0" step="0.001" inputmode="decimal" data-stock-qty="'+code+'" data-location="CDE" value="'+cde+'"></label><button type="button" class="stock-save-btn" data-stock-set="'+code+'" data-location="CDE">Actualizar CDE</button><label class="stock-reason-label">Motivo del ajuste<input type="text" maxlength="180" placeholder="Ej.: conteo físico" data-stock-reason="'+code+'"></label><p class="stock-edit-message" data-stock-message="'+code+'" role="status"></p></div>':'';
  return '<article class="order-card stock-item-card"><strong>'+safe(x.d)+'</strong><small>'+code+' · CENTRAL: '+central+' · CDE: '+cde+' · Total: '+(central+cde)+'</small>'+controls+'</article>';
 }).join('')||'<div class="empty-state">No se encontraron artículos.</div>';
 $('stock-list').querySelectorAll('[data-stock-set]').forEach(b=>b.onclick=()=>saveStockBalance(b.dataset.stockSet,b.dataset.location,b));
}
async function saveStockBalance(code,location,button){
 const item=items.find(x=>String(x.c)===String(code));
 const qtyInput=$('stock-list').querySelector('[data-stock-qty="'+CSS.escape(code)+'"][data-location="'+location+'"]');
 const reasonInput=$('stock-list').querySelector('[data-stock-reason="'+CSS.escape(code)+'"]');
 const message=$('stock-list').querySelector('[data-stock-message="'+CSS.escape(code)+'"]');
 const raw=qtyInput?.value,quantity=Number(raw),reason=reasonInput?.value.trim()||'';
 if(raw===''||!Number.isFinite(quantity)||quantity<0||!/^\\d+(\\.\\d{1,3})?$/.test(raw.trim())){message.textContent='Ingresá una cantidad válida (máximo 3 decimales).';return;}
 if(!reason){message.textContent='Indicá el motivo del ajuste.';reasonInput?.focus();return;}
 if(!item||!(isGlobal||profile?.role==='company_admin')){message.textContent='No tienes permiso para ajustar este stock.';return;}
 button.disabled=true;message.textContent='Guardando ajuste…';
 try{
  const result=await timeout(db.rpc('ab_set_inventory_location_balance',{p_company_id:activeCompany.id,p_product_code:String(code),p_location_code:location,p_quantity:quantity,p_movement_type:'adjustment',p_reason:reason,p_source_ref:'manual-'+crypto.randomUUID()}),'La actualización de stock');
  if(result.error)throw result.error;
  if(location==='CENTRAL')item.sc=quantity;else item.sd=quantity;
  render();
  const refreshedMessage=$('stock-list').querySelector('[data-stock-message="'+CSS.escape(code)+'"]');
  if(refreshedMessage)refreshedMessage.textContent='Stock '+location+' actualizado. Movimiento registrado.';
 }catch(e){message.textContent='No se pudo actualizar: '+(e.message||'Error desconocido');button.disabled=false;}
}
async function loadData(){
 if(!activeCompany?.id)throw new Error('No hay una empresa activa.');
 const [catalogRows,clientRows,balanceRows]=await Promise.all([
  fetchAllRows(()=>db.from('catalog_items').select('code,payload').eq('company_id',activeCompany.id).order('code'),'El catálogo'),
  fetchAllRows(()=>db.from('catalog_clients').select('code,payload').eq('company_id',activeCompany.id).order('code'),'Los clientes'),
  fetchAllRows(()=>db.from('inventory_location_balances').select('product_code,location_code,quantity').eq('company_id',activeCompany.id).order('product_code').order('location_code'),'Los saldos CENTRAL/CDE')
 ]);
 const stockByCode=new Map();
 balanceRows.forEach(x=>{const k=String(x.product_code),v=stockByCode.get(k)||{central:0,cde:0};if(x.location_code==='CENTRAL')v.central=Number(x.quantity)||0;if(x.location_code==='CDE')v.cde=Number(x.quantity)||0;stockByCode.set(k,v);});
 items=catalogRows.map(x=>{const stock=stockByCode.get(String(x.code))||{central:0,cde:0};return {...x.payload,c:x.payload?.c??x.code,sc:stock.central,sd:stock.cde};});
 clients=clientRows.map(x=>x.payload);
 if(String(activeCompany.code||'').toUpperCase()==='DEMO'){
  if(!items.length)items=[...window.DEMO_ITEMS];
  if(!clients.length)clients=[...window.DEMO_CLIENTS];
 }
 const {data:members,error:me}=await timeout(
  db.from('company_memberships').select('user_id').eq('company_id',activeCompany.id).eq('role','seller').eq('status','active'),
  'Las membresías de vendedores'
 );
 if(me)throw me;
 const memberIds=(members||[]).map(x=>x.user_id);
 let assignmentsQuery=db.from('seller_assignments').select('user_id,seller_label').eq('company_id',activeCompany.id);
 if(profile.role==='seller'&&!isGlobal)assignmentsQuery=assignmentsQuery.eq('user_id',user.id);
 else if(memberIds.length)assignmentsQuery=assignmentsQuery.in('user_id',memberIds);
 else assignmentsQuery=assignmentsQuery.eq('user_id','00000000-0000-0000-0000-000000000000');
 const {data:as,error:ae}=await timeout(assignmentsQuery,'Las asignaciones de vendedores');if(ae)throw ae;
 sellerRows=as||[];
 const sellers=sellerRows.map(x=>x.seller_label);
 if(profile.role==='seller'&&!sellers.length)throw new Error('Tu cuenta no tiene un vendedor activo asignado en esta empresa.');
 $('vendedor-input').innerHTML='<option value="">Vendedor</option>'+[...new Set(sellers)].map(x=>'<option value="'+safe(x)+'">'+safe(x)+'</option>').join('');
 $('save-order').textContent='Guardar pedido · '+activeCompany.name;
 $('stock-list').setAttribute('aria-label','Stock de '+activeCompany.name);
 $('excel-import-confirm').disabled=!(isGlobal||profile.role==='company_admin');
 $('excel-import-file').disabled=!(isGlobal||profile.role==='company_admin');
 $('excel-import-preview').textContent=(isGlobal||profile.role==='company_admin')?'La importación está disponible para administradores.':'Solo un administrador de empresa puede importar catálogo y stock.';
 render();await loadOrders();
}
async function loadOrders(){
 const {data,error}=await timeout(db.from('orders').select('id,company_id,legacy_id,legacy_source,payload,updated_at').eq('company_id',activeCompany.id).order('updated_at',{ascending:false}).limit(50),'La carga de pedidos');
 if(error)throw error;orders=data||[];render();
}
async function activate(u){
 user=u;await loadCompanyContext(u);await loadData();
 $('login').hidden=true;$('app').hidden=false;$('cloud-status-slot').textContent='Conectado · '+activeCompany.name;
 $('admin-menu-tab').hidden=!(isGlobal||profile.role==='company_admin');showPanel('panel-search');
}
$('login-form').addEventListener('submit',async e=>{e.preventDefault();const b=$('login-form').querySelector('button');b.disabled=true;gate('Conectando con Supabase DEMO…');try{const r=await timeout(db.auth.signInWithPassword({email:$('email').value.trim(),password:$('password').value}),'El acceso');if(r.error)throw r.error;await activate(r.data.user);}catch(err){await db.auth.signOut();gate('No se pudo ingresar: '+(err.message||'Error desconocido'));}finally{b.disabled=false;}});
$('logout').onclick=async()=>{await db.auth.signOut();user=null;profile=null;activeCompany=null;companies=[];isGlobal=false;items=[];clients=[];sellerRows=[];orders=[];cart=[];gate('Sesión cerrada.');};
document.querySelectorAll('.tabs [data-panel]').forEach(b=>b.addEventListener('click',()=>showPanel(b.dataset.panel)));
$('company-select').addEventListener('change',e=>switchCompany(e.target.value));
$('search-input').addEventListener('input',render);$('discount-input').addEventListener('input',render);
document.querySelectorAll('[data-tier]').forEach(b=>b.onclick=()=>{tier=Number(b.dataset.tier);document.querySelectorAll('[data-tier]').forEach(x=>x.classList.toggle('active',x===b));render();});
document.querySelectorAll('[data-estado]').forEach(b=>b.onclick=()=>{estado=b.dataset.estado;document.querySelectorAll('[data-estado]').forEach(x=>x.classList.toggle('active',x===b));});
document.querySelectorAll('[data-condicion]').forEach(b=>b.onclick=()=>{condicion=b.dataset.condicion;$('condicion-input').value=condicion;document.querySelectorAll('[data-condicion]').forEach(x=>x.classList.toggle('active',x===b));});
$('nuevo-cliente-toggle').onclick=()=>{$('nuevo-cliente-panel').hidden=!$('nuevo-cliente-panel').hidden;};
$('cliente-input').addEventListener('input',()=>{const q=$('cliente-input').value.toLowerCase();const matches=clients.filter(c=>[c.c,c.n].some(v=>String(v||'').toLowerCase().includes(q))).slice(0,8);$('cliente-suggestions').innerHTML=matches.map(c=>'<button type="button" class="cliente-suggestion" data-client="'+safe(c.c)+'"><span class="cs-text"><span class="cs-name">'+safe(c.n)+'</span><span class="cs-meta">'+safe(c.c)+'</span></span></button>').join('');$('cliente-suggestions').classList.toggle('open',matches.length>0);$('cliente-suggestions').querySelectorAll('[data-client]').forEach(b=>b.onclick=()=>{const c=clients.find(x=>String(x.c)===b.dataset.client);$('cliente-input').value=c.n;$('cliente-input').dataset.code=c.c;$('cliente-suggestions').classList.remove('open');});});
$('save-order').onclick=async()=>{
 const saveButton=$('save-order');if(saveButton.disabled)return;
 saveButton.disabled=true;
 const msg=$('order-message');const seller=$('vendedor-input').value,clientCode=$('cliente-input').dataset.code;
 try{
 if(!cart.length){msg.textContent='Agregá al menos un artículo.';return;}
 if(!seller||!clientCode){msg.textContent='Seleccioná vendedor y cliente de la lista.';return;}
 const sellerMatches=sellerRows.filter(x=>x.seller_label===seller);
 if(sellerMatches.length!==1){msg.textContent='No se pudo identificar de forma única al vendedor seleccionado. Revisá sus asignaciones.';return;}
 const ownerId=sellerMatches[0].user_id;
 const client=clients.find(c=>String(c.c)===String(clientCode));if(!client){msg.textContent='Seleccioná un cliente válido.';return;}
 const sub=total(),discount=Math.min(100,Math.max(0,Number($('discount-input').value)||0)),grand=sub-(sub*discount/100),now=new Date().toISOString(),id=activeCompany.code.toLowerCase()+'_'+crypto.randomUUID();
 const payload={id,vendedor:seller,cliente:client.n,clienteCodigo:client.c,estado,condicion:$('condicion-input').value||condicion,lines:cart.map(x=>({code:x.c,description:x.d,qty:x.qty,tier,price:x['p'+tier]})),subtotal:sub,discount,total:grand,createdAt:now,updatedAt:now,companyCode:activeCompany.code};
 const {error}=await db.from('orders').insert({company_id:activeCompany.id,owner_id:ownerId,created_by:user.id,legacy_id:id,legacy_source:'archive',payload,updated_at:now});
 if(error){msg.textContent='No se pudo guardar el pedido: '+error.message;return;}
 cart=[];$('discount-input').value='0';showPanel('panel-archive');
 try{await loadOrders();msg.textContent='Pedido guardado correctamente en '+activeCompany.name+'.';}
 catch(refreshError){msg.textContent='El pedido se guardó, pero no se pudo actualizar el archivo: '+refreshError.message;}
 }catch(e){msg.textContent='No se pudo completar el guardado: '+(e.message||'Error desconocido');}
 finally{saveButton.disabled=false;}
};
$('btn-clear').onclick=()=>{cart=[];$('discount-input').value='0';$('cliente-input').value='';$('cliente-input').dataset.code='';render();showPanel('panel-search');};
$('btn-pdf').onclick=()=>{if(!cart.length){alert('Agregá artículos al pedido antes de generar el comprobante.');return;}const lines=cart.map(x=>'<tr><td>'+safe(x.c)+'</td><td>'+safe(x.d)+'</td><td>'+x.qty+'</td><td>'+money(x['p'+tier])+'</td><td>'+money(x.qty*x['p'+tier])+'</td></tr>').join('');const sub=total(),discount=Math.min(100,Math.max(0,Number($('discount-input').value)||0)),grand=sub-sub*discount/100;const w=window.open('','_blank');if(!w){alert('El navegador bloqueó la ventana. Permití ventanas emergentes para generar el PDF.');return;}w.onload=()=>w.print();w.document.write('<!doctype html><html lang="es"><meta charset="utf-8"><title>Pedido AB SYSTEM</title><style>body{font:14px Arial;padding:28px;color:#17212b}table{width:100%;border-collapse:collapse}th,td{padding:9px;border-bottom:1px solid #ddd;text-align:left}</style><h1>AB SYSTEM · Pedido</h1><p>Empresa: '+safe(activeCompany.name)+'</p><p>Cliente: '+safe($('cliente-input').value)+'</p><p>Vendedor: '+safe($('vendedor-input').value)+'</p><table><thead><tr><th>Código</th><th>Descripción</th><th>Cantidad</th><th>Precio</th><th>Subtotal</th></tr></thead><tbody>'+lines+'</tbody></table><h2>Total: '+money(grand)+'</h2></html>');w.document.close();};
$('btn-scan-barcode').onclick=()=>alert('El escáner se integrará después de validar el flujo de búsqueda DEMO.');
$('dashboard-refresh').onclick=()=>loadOrders().catch(e=>$('cloud-status-slot').textContent=e.message);
function normalizeHeader(v){return String(v??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toUpperCase().replace(/[^A-Z0-9]/g,'');}
function excelNumber(v,label,row){if(v===null||v===undefined||String(v).trim()==='')throw new Error('Fila '+row+': falta '+label+'.');let n;if(typeof v==='number')n=v;else{let t=String(v).trim().replace(/\s/g,'');if(t.includes(',')&&t.includes('.'))t=t.replace(/\./g,'').replace(',','.');else if(t.includes(','))t=t.replace(',','.');n=Number(t);}if(!Number.isFinite(n)||n<0)throw new Error('Fila '+row+': '+label+' debe ser un número no negativo.');return n;}
function readExcelRows(workbook){const sheetName=workbook.SheetNames[0];if(!sheetName)throw new Error('El libro no contiene hojas.');const matrix=window.XLSX.utils.sheet_to_json(workbook.Sheets[sheetName],{header:1,defval:null,raw:true});const headerIndex=matrix.findIndex(r=>r.some(v=>normalizeHeader(v)==='CODARTICULO'));if(headerIndex<0)throw new Error('No se encontró Cód.Artículo.');const headers=matrix[headerIndex].map(normalizeHeader);const aliases={code:['CODARTICULO','CODIGOARTICULO'],factory:['CODFABRICA'],barcode:['CODBARRA'],g1:['AGRUP1'],g2:['AGRUP2'],g3:['AGRUP3'],description:['DESCRIPCION'],packages:['ENVASES'],master:['MASTER'],inner:['INNER'],central:['CENTRAL','STOCKCENTRAL'],cde:['CDE','STOCKCDE'],p1:['1','PRECIO1'],p2:['2','PRECIO2'],p3:['3','PRECIO3']};const col={};for(const [k,ns] of Object.entries(aliases)){const ix=ns.map(n=>headers.indexOf(n)).filter(i=>i>=0);if(ix.length>1)throw new Error('Columnas duplicadas para '+k+'.');if(ix.length)col[k]=ix[0];}for(const k of ['code','description','central','cde','p1','p2','p3'])if(col[k]===undefined)throw new Error('Falta columna obligatoria: '+k+'.');const seen=new Map(),rows=[];for(let i=headerIndex+1;i<matrix.length;i++){const r=matrix[i];if(!r||r.every(v=>v===null||String(v).trim()===''))continue;const line=i+1,code=String(r[col.code]??'').trim(),desc=String(r[col.description]??'').trim();if(!code||!desc)throw new Error('Fila '+line+': código y descripción son obligatorios.');if(seen.has(code))throw new Error('Código duplicado '+code+' en filas '+seen.get(code)+' y '+line+'.');seen.set(code,line);const central=excelNumber(r[col.central],'CENTRAL',line),cde=excelNumber(r[col.cde],'CDE',line),p1=excelNumber(r[col.p1],'precio 1',line),p2=excelNumber(r[col.p2],'precio 2',line),p3=excelNumber(r[col.p3],'precio 3',line);const payload={c:code,d:desc,p1:p1,p2:p2,p3:p3,sc:central,sd:cde};for(const [k,f] of [['factory','factoryCode'],['barcode','b'],['g1','g1'],['g2','g2'],['g3','g3'],['packages','envases'],['master','master'],['inner','inner']])if(col[k]!==undefined&&r[col[k]]!==null&&String(r[col[k]]).trim()!=='')payload[f]=String(r[col[k]]).trim();rows.push({code:code,payload:payload,stock_central:central,stock_cde:cde});}if(!rows.length)throw new Error('No se encontraron artículos.');return {rows:rows,sheetName:sheetName,headerRow:headerIndex+1};}
$('excel-import-file').addEventListener('change',async e=>{const file=e.target.files&&e.target.files[0];pendingImport=null;$('excel-import-confirm').disabled=true;if(!file)return;if(!(isGlobal||profile?.role==='company_admin'))return;try{if(!window.XLSX)throw new Error('No se cargó el lector Excel.');const wb=window.XLSX.read(await file.arrayBuffer(),{type:'array',cellDates:false}),parsed=readExcelRows(wb),existing=new Set(items.map(x=>String(x.c))),fresh=parsed.rows.filter(x=>!existing.has(x.code)).length;pendingImport={rows:parsed.rows,fileName:file.name};$('excel-import-preview').textContent='Archivo: '+file.name+' · Hoja: '+parsed.sheetName+' · Fila encabezado: '+parsed.headerRow+' · Artículos: '+parsed.rows.length+' · Nuevos: '+fresh+' · Actualizar: '+(parsed.rows.length-fresh)+'. Los ausentes se conservan.';$('excel-import-confirm').disabled=false;}catch(err){$('excel-import-preview').textContent='No se puede importar: '+err.message;}});
$('excel-import-confirm').addEventListener('click',async()=>{if(!pendingImport||!(isGlobal||profile?.role==='company_admin'))return;const b=$('excel-import-confirm');b.disabled=true;b.textContent='Importando…';try{
 const rows=pendingImport.rows,batchSize=250,totalBatches=Math.ceil(rows.length/batchSize),runId=crypto.randomUUID();let processed=0;
 for(let offset=0,batch=1;offset<rows.length;offset+=batchSize,batch++){
  const batchRows=rows.slice(offset,offset+batchSize),importId=runId+'-'+String(batch).padStart(3,'0');
  $('excel-import-preview').textContent='Importando lote '+batch+' de '+totalBatches+' · '+processed+' de '+rows.length+' artículos procesados…';
  const result=await timeout(db.rpc('ab_import_company_catalog_v2',{p_company_id:activeCompany.id,p_import_id:importId,p_rows:batchRows}),'El lote '+batch+' de importación');
  if(result.error)throw new Error('Lote '+batch+'/'+totalBatches+': '+result.error.message+' · Procesados antes del error: '+processed+'.');
  processed+=Number(result.data||0);
 }
 await loadData();$('excel-import-preview').textContent='Importación completada: '+processed+' artículos procesados en '+totalBatches+' lotes. Los artículos ausentes se conservaron y los stocks CENTRAL/CDE se actualizaron por separado.';pendingImport=null;$('excel-import-file').value='';
}catch(err){$('excel-import-preview').textContent='Importación detenida: '+(err.message||'Error desconocido')+' Si hubo lotes previos exitosos, sus cambios ya quedaron guardados; puedes volver a ejecutar el mismo archivo para completar/actualizar el catálogo.';}finally{b.textContent='Confirmar importación';b.disabled=!pendingImport;}});
$('stock-search').addEventListener('input',renderStock);
$('archive-search-input').addEventListener('input',()=>{const q=$('archive-search-input').value.toLowerCase();$('archive-list').querySelectorAll('article').forEach(el=>el.hidden=!el.textContent.toLowerCase().includes(q));});
$('vendedor-input').addEventListener('change',()=>{});
gate('Ingresá con tu cuenta de AB SYSTEM.');
})();