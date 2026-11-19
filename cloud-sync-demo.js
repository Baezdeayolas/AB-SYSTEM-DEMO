(() => {
'use strict';
const SUPABASE_URL='https://druugcvqxxanhtdkqnjd.supabase.co';
const SUPABASE_KEY='sb_publishable_M6W3DMCqPcH92cT96ioP5A_wi64QmcA';
const $=id=>document.getElementById(id);
if(!window.supabase?.createClient){$('login-message').textContent='No se pudo cargar el servicio de acceso DEMO.';return;}
const db=window.supabase.createClient(SUPABASE_URL,SUPABASE_KEY);
let user=null,profile=null,companies=[],activeCompany=null,isGlobal=false,isPublicDemo=false,items=[],clients=[],sellerRows=[],cart=[],orders=[],tier=1,estado='pendiente',condicion='Contado',pendingImport=null,pendingClientImport=null;
const money=n=>'Gs. '+Math.round(Number(n||0)).toLocaleString('es-PY');
const safe=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const timeout=(p,label,ms=12000)=>Promise.race([p,new Promise((_,rej)=>setTimeout(()=>rej(new Error(label+' no respondió dentro del tiempo permitido.')),ms))]);
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
 select.hidden=!(isGlobal||companies.length>1);
 $('company-role').textContent=isGlobal?'Superadministrador global':(profile.role==='company_admin'?'Administrador de empresa':'Vendedor');
 $('dashboard-date').textContent='Actividad de hoy · '+activeCompany.name;
 $('dashboard-scope').textContent='Información de '+activeCompany.name+'.';
}
async function switchCompany(companyId){
 const next=companies.find(c=>c.id===companyId);if(!next||next.id===activeCompany?.id)return;
 const previous=activeCompany,select=$('company-select');
 select.disabled=true;
 activeCompany=next;profile={role:isGlobal?'company_admin':(next.memberRole||'seller')};
 cart=[];orders=[];items=[];clients=[];sellerRows=[];pendingClientImport=null;
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
 const q=$('search-input').value.trim().toLowerCase(),filtered=q?items.filter(x=>[x.c,x.b,x.d].some(v=>String(v||'').toLowerCase().includes(q))):[];
 $('result-count').textContent=q?(filtered.length+' productos · mostrando '+Math.min(filtered.length,100)+' · '+(activeCompany?.name||'empresa')):'';
 $('item-list').innerHTML=q?(filtered.slice(0,100).map(x=>'<article class="item-card"><div class="item-top"><span class="item-code">'+safe(x.c)+'</span><span class="item-stock">CENTRAL '+Number(x.sc||0)+' · CDE '+Number(x.sd||0)+'</span></div><div class="item-desc">'+safe(x.d)+'</div><div class="item-bottom"><strong class="item-price">'+money(x['p'+tier])+'</strong><div class="item-actions"><input class="qty-input" type="number" min="1" value="1" aria-label="Cantidad" data-qty="'+safe(x.c)+'"><button class="add-btn" data-add="'+safe(x.c)+'"'+(isPublicDemo?' disabled':'')+'>Agregar</button></div></div></article>').join('')||'<div class="empty-state">No se encontraron productos.</div>'):'';
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
 const filtered=q?items.filter(x=>[x.c,x.d].some(v=>String(v||'').toLowerCase().includes(q))):[];
 const canAdjust=!isPublicDemo&&(isGlobal||profile?.role==='company_admin');
 $('stock-list').innerHTML=filtered.length?filtered.slice(0,100).map(x=>{
  const code=safe(x.c),central=Number(x.sc||0),cde=Number(x.sd||0);
  const controls=canAdjust?'<div class="stock-edit-grid"><label>CENTRAL<input type="number" min="0" step="0.001" inputmode="decimal" data-stock-qty="'+code+'" data-location="CENTRAL" value="'+central+'"></label><button type="button" class="stock-save-btn" data-stock-set="'+code+'" data-location="CENTRAL">Actualizar CENTRAL</button><label>CDE<input type="number" min="0" step="0.001" inputmode="decimal" data-stock-qty="'+code+'" data-location="CDE" value="'+cde+'"></label><button type="button" class="stock-save-btn" data-stock-set="'+code+'" data-location="CDE">Actualizar CDE</button><label class="stock-reason-label">Motivo del ajuste<input type="text" maxlength="180" placeholder="Ej.: conteo físico" data-stock-reason="'+code+'"></label><p class="stock-edit-message" data-stock-message="'+code+'" role="status"></p></div>':'';
  return '<article class="order-card stock-item-card"><strong>'+safe(x.d)+'</strong><small>'+code+' · CENTRAL: '+central+' · CDE: '+cde+' · Total: '+(central+cde)+'</small>'+controls+'</article>';
 }).join(''):(q?'<div class="empty-state">No se encontraron artículos.</div>':'<div class="empty-state">Ingresá un código o descripción para consultar el stock.</div>');
 $('stock-list').querySelectorAll('[data-stock-set]').forEach(b=>b.onclick=()=>saveStockBalance(b.dataset.stockSet,b.dataset.location,b));
}
async function saveStockBalance(code,location,button){
 const item=items.find(x=>String(x.c)===String(code));
 const qtyInput=$('stock-list').querySelector('[data-stock-qty="'+CSS.escape(code)+'"][data-location="'+location+'"]');
 const reasonInput=$('stock-list').querySelector('[data-stock-reason="'+CSS.escape(code)+'"]');
 const message=$('stock-list').querySelector('[data-stock-message="'+CSS.escape(code)+'"]');
 const raw=qtyInput?.value,quantity=Number(raw),reason=reasonInput?.value.trim()||'';
 if(raw===''||!Number.isFinite(quantity)||quantity<0||!/^\d+(\.\d{1,3})?$/.test(raw.trim())){message.textContent='Ingresá una cantidad válida (máximo 3 decimales).';return;}
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
 const canManageCatalog=(isGlobal||profile.role==='company_admin');
 $('excel-import-confirm').disabled=!canManageCatalog;
 $('excel-import-file').disabled=!canManageCatalog;
 $('excel-import-preview').textContent=canManageCatalog?'La importación está disponible para administradores.':'Solo un administrador de empresa puede importar catálogo y stock.';
 $('client-excel-import-file').disabled=!canManageCatalog;
 $('client-excel-import-confirm').disabled=true;
 $('client-excel-import-preview').textContent=canManageCatalog?'La carga de clientes está disponible para administradores de esta empresa.':'Solo un administrador de empresa puede importar clientes.';
 render();await loadOrders();
}
async function loadOrders(){
 const {data,error}=await timeout(db.from('orders').select('id,company_id,legacy_id,legacy_source,payload,updated_at').eq('company_id',activeCompany.id).order('updated_at',{ascending:false}).limit(50),'La carga de pedidos');
 if(error)throw error;orders=data||[];render();
}
async function finishCompanyLogin(){
 $('company-gate').hidden=true;
 try{
  await loadData();
  $('login').hidden=true;$('app').hidden=false;
  $('cloud-status-slot').textContent='Conectado · '+activeCompany.name;
  $('company-select').hidden=!(isGlobal||companies.length>1);
  $('admin-menu-tab').hidden=!(isGlobal||profile.role==='company_admin');
  $('global-admin-tools').hidden=!isGlobal;
  if(isGlobal){try{await loadGlobalAdminData();}catch(adminError){$('global-members-list').textContent='La gestión de usuarios requiere habilitar la función segura admin-users en Supabase DEMO.';}}
  showPanel('panel-search');
 }catch(err){$('company-gate').hidden=false;$('company-gate-message').textContent='No se pudo cargar la empresa: '+(err.message||'Error desconocido');}
}
async function activate(u){
 user=u;await loadCompanyContext(u);
 if(isGlobal||companies.length>1){
  const pick=$('company-gate-select');
  pick.innerHTML=companies.map(c=>'<option value="'+safe(c.id)+'">'+safe(c.name)+'</option>').join('');
  pick.value=activeCompany.id;
  $('login').hidden=true;$('company-gate').hidden=false;
  $('company-gate-message').textContent=isGlobal?'Acceso global validado. Elegí la empresa que querés administrar.':'Acceso validado. Elegí una de tus empresas.';
  return;
 }
 await finishCompanyLogin();
}
async function enterPublicDemo(){
 await db.auth.signOut().catch(()=>{});
 isPublicDemo=true;user=null;isGlobal=false;profile={role:'demo'};
 activeCompany={id:'public-demo',code:'DEMO',name:'Demostración AB SYSTEM'};
 companies=[];items=(window.DEMO_ITEMS||[]).map(x=>({...x}));clients=(window.DEMO_CLIENTS||[]).map(x=>({...x}));
 sellerRows=[];cart=[];orders=[];pendingImport=null;
 $('login').hidden=true;$('company-gate').hidden=true;$('app').hidden=false;
 $('company-select').hidden=true;$('company-role').textContent='Modo demostración · solo lectura';
 $('cloud-status-slot').textContent='Demostración pública · solo lectura';
 $('admin-menu-tab').hidden=true;$('global-admin-tools').hidden=true;
 document.querySelector('.meta-fields').hidden=true;
 document.querySelector('.precio-estado-row').hidden=true;
 document.querySelector('.condicion-row').hidden=true;
 $('nuevo-cliente-toggle').hidden=true;
 document.querySelector('.footer').hidden=true;
 document.querySelectorAll('.tabs [data-panel="panel-order"],.tabs [data-panel="panel-archive"],.tabs [data-panel="panel-admin"]').forEach(x=>x.hidden=true);
 $('logout').textContent='Salir demo';
 $('dashboard-date').textContent='Datos ficticios · demostración';
 $('dashboard-scope').textContent='Entorno de muestra. No se guardan cambios ni se consulta información de clientes reales.';
 $('search-input').value='';$('stock-search').value='';
 render();showPanel('panel-search');
}
async function callGlobalAdmin(action,payload={}){
 const {data,error}=await timeout(db.functions.invoke('admin-users',{body:{action,...payload}}),'La administración global');
 if(error){
  let message=error.message||'Error desconocido';
  const context=error.context;
  if(context&&typeof context.json==='function'){
   try{
    const response=typeof context.clone==='function'?context.clone():context;
    const body=await response.json();
    if(typeof body?.error==='string'&&body.error.trim())message=body.error.trim();
    else if(typeof body?.message==='string'&&body.message.trim())message=body.message.trim();
   }catch(_){}
  }
  throw new Error(message);
 }
 if(data?.error)throw new Error(data.error);
 return data||{};
}
async function loadGlobalAdminData(){
 if(!isGlobal)return;
 const {data:allCompanies,error}=await timeout(db.from('companies').select('id,code,name,status').order('name'),'La lista global de empresas');
 if(error)throw error;
 $('global-company-list').innerHTML=(allCompanies||[]).map(c=>'<article class="global-admin-row"><div><strong>'+safe(c.name)+'</strong><small>'+safe(c.code)+' · '+safe(c.status)+'</small></div><button type="button" class="btn-outline btn-sm" data-company-status="'+safe(c.id)+'" data-status="'+safe(c.status)+'">'+(c.status==='active'?'Suspender':'Activar')+'</button></article>').join('')||'<p>No hay empresas registradas.</p>';
 $('invite-company').innerHTML=(allCompanies||[]).filter(c=>c.status==='active').map(c=>'<option value="'+safe(c.id)+'">'+safe(c.name)+'</option>').join('');
 const result=await callGlobalAdmin('list');
 $('global-members-list').innerHTML=(result.memberships||[]).map(m=>'<article class="global-admin-row member-admin-row"><div><strong>'+safe(m.display_name||m.email||'Usuario sin correo')+'</strong><small>'+safe(m.email||'')+' · '+safe(m.company_name||'')+'</small></div><div class="member-admin-controls"><select aria-label="Rol" data-member-role="'+safe(m.company_id)+'|'+safe(m.user_id)+'"><option value="seller" '+(m.role==='seller'?'selected':'')+'>Vendedor</option><option value="company_admin" '+(m.role==='company_admin'?'selected':'')+'>Administrador</option></select><select aria-label="Estado" data-member-status="'+safe(m.company_id)+'|'+safe(m.user_id)+'"><option value="active" '+(m.status==='active'?'selected':'')+'>Activo</option><option value="suspended" '+(m.status==='suspended'?'selected':'')+'>Suspendido</option></select><button type="button" class="btn-outline btn-sm" data-member-save="'+safe(m.company_id)+'|'+safe(m.user_id)+'">Guardar</button><button type="button" class="btn-outline btn-sm" data-member-remove="'+safe(m.company_id)+'|'+safe(m.user_id)+'">Quitar</button></div></article>').join('')||'<p>Todavía no hay usuarios asignados.</p>';
 $('global-members-list').querySelectorAll('[data-member-remove]').forEach(b=>b.onclick=async()=>{
  const [companyId,userId]=b.dataset.memberRemove.split('|');
  if(!confirm('¿Quitar este usuario de la empresa? Su cuenta de acceso se conservará y podrá seguir perteneciendo a otras empresas.'))return;
  b.disabled=true;try{await callGlobalAdmin('remove-membership',{companyId,userId});await loadGlobalAdminData();if(activeCompany?.id===companyId)await loadData();}catch(e){alert('No se pudo quitar la membresía: '+e.message);}finally{b.disabled=false;}
 });
 $('global-members-list').querySelectorAll('[data-member-save]').forEach(b=>b.onclick=async()=>{
  const [companyId,userId]=b.dataset.memberSave.split('|');
  const key=b.dataset.memberSave;
  const role=$('global-members-list').querySelector('[data-member-role="'+key+'"]').value;
  const status=$('global-members-list').querySelector('[data-member-status="'+key+'"]').value;
  b.disabled=true;try{await callGlobalAdmin('update-membership',{companyId,userId,role,status});await loadGlobalAdminData();if(activeCompany?.id===companyId)await loadData();}catch(e){alert('No se pudo actualizar la membresía: '+e.message);}finally{b.disabled=false;}
 });
 $('global-company-list').querySelectorAll('[data-company-status]').forEach(b=>b.onclick=async()=>{
  const status=b.dataset.status==='active'?'suspended':'active';b.disabled=true;
  try{const previousCompanyId=activeCompany?.id;await callGlobalAdmin('set-company-status',{companyId:b.dataset.companyStatus,status});await loadGlobalAdminData();await loadCompanyContext(user);if(activeCompany?.id!==previousCompanyId){cart=[];orders=[];items=[];clients=[];sellerRows=[];await loadData();}}catch(e){alert('No se pudo cambiar el estado: '+e.message);}finally{b.disabled=false;}
 });
}
$('company-create-form').addEventListener('submit',async e=>{
 e.preventDefault();if(!isGlobal)return;
 const name=$('new-company-name').value.trim(),code=$('new-company-code').value.trim().toUpperCase().replace(/[^A-Z0-9_-]/g,'');
 const msg=$('company-create-message');if(!name||!code){msg.textContent='Completá el nombre y un código válido.';return;}
 const b=$('company-create-form').querySelector('button');b.disabled=true;
 try{await callGlobalAdmin('create-company',{name,code});msg.textContent='Empresa creada correctamente.';$('company-create-form').reset();await loadCompanyContext(user);await loadGlobalAdminData();}
 catch(err){msg.textContent='No se pudo crear la empresa: '+err.message;}finally{b.disabled=false;}
});
$('member-invite-form').addEventListener('submit',async e=>{
 e.preventDefault();if(!isGlobal)return;
 const msg=$('member-invite-message'),b=$('member-invite-form').querySelector('button');b.disabled=true;
 try{const data=await callGlobalAdmin('invite',{companyId:$('invite-company').value,email:$('invite-email').value.trim(),displayName:$('invite-name').value.trim(),role:$('invite-role').value});msg.textContent=data.invited?'Invitación enviada por correo.':'Usuario existente asignado a la empresa.';$('member-invite-form').reset();await loadGlobalAdminData();}
 catch(err){msg.textContent='No se pudo invitar al usuario: '+err.message;}finally{b.disabled=false;}
});
$('global-admin-refresh').onclick=()=>loadGlobalAdminData().catch(e=>alert(e.message));
$('company-gate-form').addEventListener('submit',async e=>{e.preventDefault();const chosen=companies.find(c=>c.id===$('company-gate-select').value);if(!chosen)return;activeCompany=chosen;profile={role:isGlobal?'company_admin':(chosen.memberRole||'seller')};await finishCompanyLogin();});
$('demo-access').onclick=()=>enterPublicDemo();
$('login-form').addEventListener('submit',async e=>{e.preventDefault();const b=$('login-form').querySelector('button[type="submit"]');b.disabled=true;gate('Conectando con Supabase DEMO…');try{const r=await timeout(db.auth.signInWithPassword({email:$('email').value.trim(),password:$('password').value}),'El acceso');if(r.error)throw r.error;await activate(r.data.user);}catch(err){await db.auth.signOut();gate('No se pudo ingresar: '+(err.message||'Error desconocido'));}finally{b.disabled=false;}});
$('logout').onclick=async()=>{if(isPublicDemo){window.location.reload();return;}await db.auth.signOut();user=null;profile=null;activeCompany=null;companies=[];isGlobal=false;isPublicDemo=false;items=[];clients=[];sellerRows=[];orders=[];cart=[];$('company-gate').hidden=true;gate('Sesión cerrada.');};
document.querySelectorAll('.tabs [data-panel]').forEach(b=>b.addEventListener('click',()=>showPanel(b.dataset.panel)));
$('company-select').addEventListener('change',e=>switchCompany(e.target.value));
$('search-input').addEventListener('input',render);$('discount-input').addEventListener('input',render);
document.querySelectorAll('[data-tier]').forEach(b=>b.onclick=()=>{tier=Number(b.dataset.tier);document.querySelectorAll('[data-tier]').forEach(x=>x.classList.toggle('active',x===b));render();});
document.querySelectorAll('[data-estado]').forEach(b=>b.onclick=()=>{estado=b.dataset.estado;document.querySelectorAll('[data-estado]').forEach(x=>x.classList.toggle('active',x===b));});
document.querySelectorAll('[data-condicion]').forEach(b=>b.onclick=()=>{condicion=b.dataset.condicion;$('condicion-input').value=condicion;document.querySelectorAll('[data-condicion]').forEach(x=>x.classList.toggle('active',x===b));});
$('nuevo-cliente-toggle').onclick=()=>{$('nuevo-cliente-panel').hidden=!$('nuevo-cliente-panel').hidden;};
$('cliente-input').addEventListener('input',()=>{const q=$('cliente-input').value.trim().toLowerCase();const matches=q?clients.filter(c=>[c.c,c.n].some(v=>String(v||'').toLowerCase().includes(q))).slice(0,8):[];$('cliente-suggestions').innerHTML=matches.map(c=>'<button type="button" class="cliente-suggestion" data-client="'+safe(c.c)+'"><span class="cs-text"><span class="cs-name">'+safe(c.n)+'</span><span class="cs-meta">'+safe(c.c)+'</span></span></button>').join('');$('cliente-suggestions').classList.toggle('open',q.length>0&&matches.length>0);$('cliente-suggestions').querySelectorAll('[data-client]').forEach(b=>b.onclick=()=>{const c=clients.find(x=>String(x.c)===b.dataset.client);$('cliente-input').value=c.n;$('cliente-input').dataset.code=c.c;$('cliente-suggestions').classList.remove('open');});});
let orderSaveInProgress=false;
async function saveCurrentOrder({startNew=false}={}){
 const saveButton=$('save-order'),msg=$('order-message');
 if(orderSaveInProgress)return false;
 orderSaveInProgress=true;saveButton.disabled=true;
 try{
  if(isPublicDemo){msg.textContent='La demostración es de solo lectura.';return false;}
  if(!cart.length){
   if(startNew){$('discount-input').value='0';$('cliente-input').value='';$('cliente-input').dataset.code='';render();showPanel('panel-search');}
   else msg.textContent='Agregá al menos un artículo.';
   return false;
  }
  const seller=$('vendedor-input').value,clientCode=$('cliente-input').dataset.code;
  if(!seller||!clientCode){msg.textContent='Seleccioná vendedor y cliente de la lista. El pedido sigue en pantalla y no se perdió.';return false;}
  const sellerMatches=sellerRows.filter(x=>x.seller_label===seller);
  if(sellerMatches.length!==1){msg.textContent='No se pudo identificar de forma única al vendedor seleccionado. Revisá sus asignaciones. El pedido sigue en pantalla.';return false;}
  const ownerId=sellerMatches[0].user_id;
  const client=clients.find(c=>String(c.c)===String(clientCode));
  if(!client){msg.textContent='Seleccioná un cliente válido. El pedido sigue en pantalla.';return false;}
  const sub=total(),discount=Math.min(100,Math.max(0,Number($('discount-input').value)||0)),grand=sub-(sub*discount/100),now=new Date().toISOString(),id=activeCompany.code.toLowerCase()+'_'+crypto.randomUUID();
  const payload={id,vendedor:seller,cliente:client.n,clienteCodigo:client.c,estado,condicion:$('condicion-input').value||condicion,lines:cart.map(x=>({code:x.c,description:x.d,qty:x.qty,tier,price:x['p'+tier]})),subtotal:sub,discount,total:grand,createdAt:now,updatedAt:now,companyCode:activeCompany.code};
  const {error}=await db.from('orders').insert({company_id:activeCompany.id,owner_id:ownerId,created_by:user.id,legacy_id:id,legacy_source:'archive',payload,updated_at:now});
  if(error){msg.textContent='No se pudo archivar el pedido: '+error.message+'. Los datos siguen en pantalla; no vuelvas a compartirlo hasta resolver el error.';return false;}
  let refreshError=null;
  try{await loadOrders();}catch(e){refreshError=e;}
  cart=[];$('discount-input').value='0';$('cliente-input').value='';$('cliente-input').dataset.code='';
  render();
  if(startNew){
   showPanel('panel-search');
   msg.textContent=refreshError?'Pedido guardado. No se pudo actualizar la vista de Archivo: '+refreshError.message:'Pedido archivado correctamente. Ya podés preparar uno nuevo.';
  }else{
   showPanel('panel-archive');
   msg.textContent=refreshError?'El pedido se guardó, pero no se pudo actualizar el archivo: '+refreshError.message:'Pedido guardado correctamente en '+activeCompany.name+'.';
  }
  return true;
 }catch(e){
  msg.textContent='No se pudo completar el guardado: '+(e.message||'Error desconocido')+'. El pedido sigue en pantalla.';
  return false;
 }finally{
  orderSaveInProgress=false;saveButton.disabled=false;
 }
}
$('save-order').onclick=()=>saveCurrentOrder();
$('btn-clear').onclick=async()=>{
 const newButton=$('btn-clear');if(newButton.disabled||orderSaveInProgress)return;
 newButton.disabled=true;
 try{await saveCurrentOrder({startNew:true});}
 finally{newButton.disabled=false;}
};
$('btn-pdf').onclick=()=>{if(!cart.length){alert('Agregá artículos al pedido antes de generar el comprobante.');return;}const lines=cart.map(x=>'<tr><td>'+safe(x.c)+'</td><td>'+safe(x.d)+'</td><td>'+x.qty+'</td><td>'+money(x['p'+tier])+'</td><td>'+money(x.qty*x['p'+tier])+'</td></tr>').join('');const sub=total(),discount=Math.min(100,Math.max(0,Number($('discount-input').value)||0)),grand=sub-sub*discount/100;const w=window.open('','_blank');if(!w){alert('El navegador bloqueó la ventana. Permití ventanas emergentes para generar el PDF.');return;}w.onload=()=>w.print();w.document.write('<!doctype html><html lang="es"><meta charset="utf-8"><title>Pedido AB SYSTEM</title><style>body{font:14px Arial;padding:28px;color:#17212b}table{width:100%;border-collapse:collapse}th,td{padding:9px;border-bottom:1px solid #ddd;text-align:left}</style><h1>AB SYSTEM · Pedido</h1><p>Empresa: '+safe(activeCompany.name)+'</p><p>Cliente: '+safe($('cliente-input').value)+'</p><p>Vendedor: '+safe($('vendedor-input').value)+'</p><table><thead><tr><th>Código</th><th>Descripción</th><th>Cantidad</th><th>Precio</th><th>Subtotal</th></tr></thead><tbody>'+lines+'</tbody></table><h2>Total: '+money(grand)+'</h2></html>');w.document.close();};
let barcodeScanner=null,barcodeScannerRunning=false,barcodeLibraryPromise=null;
async function ensureBarcodeLibrary(){
 if(window.Html5Qrcode&&window.Html5QrcodeSupportedFormats)return true;
 if(!barcodeLibraryPromise)barcodeLibraryPromise=new Promise(resolve=>{
  const sources=['https://cdn.jsdelivr.net/npm/html5-qrcode@2.3.8/html5-qrcode.min.js','https://unpkg.com/html5-qrcode@2.3.8/html5-qrcode.min.js'];
  let index=0;
  const next=()=>{
   if(window.Html5Qrcode&&window.Html5QrcodeSupportedFormats){resolve(true);return;}
   if(index>=sources.length){resolve(false);return;}
   const script=document.createElement('script');script.src=sources[index++];script.async=true;
   script.onload=()=>resolve(!!(window.Html5Qrcode&&window.Html5QrcodeSupportedFormats));
   script.onerror=next;document.head.appendChild(script);
  };
  next();
 });
 return barcodeLibraryPromise;
}
async function closeBarcodeScanner(){
 const modal=$('barcode-scanner-modal');
 if(barcodeScanner){try{await barcodeScanner.stop();}catch(e){}try{barcodeScanner.clear();}catch(e){}barcodeScanner=null;}
 barcodeScannerRunning=false;modal.hidden=true;
}
async function openBarcodeScanner(){
 const modal=$('barcode-scanner-modal'),status=$('scanner-status');
 modal.hidden=false;status.textContent='Preparando el lector…';
 const loaded=await ensureBarcodeLibrary();
 if(!loaded){status.textContent='No se pudo descargar el lector. Revisá tu conexión a internet e intentá nuevamente.';return;}
 try{
  barcodeScanner=new Html5Qrcode('barcode-reader',false);
  const formats=[Html5QrcodeSupportedFormats.EAN_13,Html5QrcodeSupportedFormats.EAN_8,Html5QrcodeSupportedFormats.UPC_A,Html5QrcodeSupportedFormats.UPC_E,Html5QrcodeSupportedFormats.CODE_128,Html5QrcodeSupportedFormats.CODE_39,Html5QrcodeSupportedFormats.ITF];
  const config={fps:10,qrbox:(w,h)=>({width:Math.max(180,Math.min(360,Math.floor(w*.82))),height:Math.max(90,Math.min(160,Math.floor(h*.38)))}),aspectRatio:1.777,formatsToSupport:formats,rememberLastUsedCamera:true};
  status.textContent='Solicitando permiso para usar la cámara…';
  barcodeScannerRunning=true;
  let cameras=[];
  try{cameras=await Html5Qrcode.getCameras();}catch(e){}
  const rear=cameras.find(c=>/back|rear|environment|trasera|posterior/i.test(c.label||''))||cameras[cameras.length-1];
  const onSuccess=async(decodedText)=>{
   if(!barcodeScannerRunning)return;
   barcodeScannerRunning=false;
   const code=String(decodedText||'').trim();
   $('search-input').value=code;render();
   const match=items.some(x=>[x.c,x.b].some(v=>String(v??'').trim().toLowerCase()===code.toLowerCase()));
   status.textContent=match?'Código leído: '+code+'. Artículo encontrado.':'Código leído: '+code+'. No se encontró coincidencia en el catálogo.';
   await closeBarcodeScanner();$('search-input').focus();
  };
  try{
   await barcodeScanner.start(rear?.id||{facingMode:{ideal:'environment'}},config,onSuccess,()=>{});
  }catch(firstError){
   if(rear?.id)await barcodeScanner.start({facingMode:{ideal:'environment'}},config,onSuccess,()=>{});
   else throw firstError;
  }
  status.textContent='Cámara activa. Enfocá el código de barras.';
 }catch(e){
  barcodeScannerRunning=false;
  const msg=String(e?.message||e||'Error desconocido');
  status.textContent=/permission|notallowed|denied/i.test(msg)?'El navegador bloqueó el permiso de cámara. Revisá los permisos del sitio.':'No se pudo iniciar la cámara: '+msg;
  if(barcodeScanner){try{barcodeScanner.clear();}catch(err){}barcodeScanner=null;}
 }
}
$('btn-scan-barcode').onclick=openBarcodeScanner;
$('scanner-close').onclick=closeBarcodeScanner;
$('barcode-scanner-modal').addEventListener('click',e=>{if(e.target===$('barcode-scanner-modal'))closeBarcodeScanner();});
document.addEventListener('keydown',e=>{if(e.key==='Escape'&&!$('barcode-scanner-modal').hidden)closeBarcodeScanner();});
$('dashboard-refresh').onclick=()=>{if(isPublicDemo){render();return;}loadOrders().catch(e=>$('cloud-status-slot').textContent=e.message);};
function normalizeHeader(v){return String(v??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toUpperCase().replace(/[^A-Z0-9]/g,'');}
function excelNumber(v,label,row){if(v===null||v===undefined||String(v).trim()==='')throw new Error('Fila '+row+': falta '+label+'.');let n;if(typeof v==='number')n=v;else{let t=String(v).trim().replace(/\s/g,'');if(t.includes(',')&&t.includes('.'))t=t.replace(/\./g,'').replace(',','.');else if(t.includes(','))t=t.replace(',','.');n=Number(t);}if(!Number.isFinite(n)||n<0)throw new Error('Fila '+row+': '+label+' debe ser un número no negativo.');return n;}
function readExcelRows(workbook){const sheetName=workbook.SheetNames[0];if(!sheetName)throw new Error('El libro no contiene hojas.');const matrix=window.XLSX.utils.sheet_to_json(workbook.Sheets[sheetName],{header:1,defval:null,raw:true});const headerIndex=matrix.findIndex(r=>r.some(v=>normalizeHeader(v)==='CODARTICULO'));if(headerIndex<0)throw new Error('No se encontró Cód.Artículo.');const headers=matrix[headerIndex].map(normalizeHeader);const aliases={code:['CODARTICULO','CODIGOARTICULO'],factory:['CODFABRICA'],barcode:['CODBARRA'],g1:['AGRUP1'],g2:['AGRUP2'],g3:['AGRUP3'],description:['DESCRIPCION'],packages:['ENVASES'],master:['MASTER'],inner:['INNER'],central:['CENTRAL','STOCKCENTRAL'],cde:['CDE','STOCKCDE'],p1:['1','PRECIO1'],p2:['2','PRECIO2'],p3:['3','PRECIO3']};const col={};for(const [k,ns] of Object.entries(aliases)){const ix=ns.map(n=>headers.indexOf(n)).filter(i=>i>=0);if(ix.length>1)throw new Error('Columnas duplicadas para '+k+'.');if(ix.length)col[k]=ix[0];}for(const k of ['code','description','central','cde','p1','p2','p3'])if(col[k]===undefined)throw new Error('Falta columna obligatoria: '+k+'.');const seen=new Map(),rows=[];for(let i=headerIndex+1;i<matrix.length;i++){const r=matrix[i];if(!r||r.every(v=>v===null||String(v).trim()===''))continue;const line=i+1,code=String(r[col.code]??'').trim(),desc=String(r[col.description]??'').trim();if(!code||!desc)throw new Error('Fila '+line+': código y descripción son obligatorios.');const codeKey=code.normalize('NFKC').toLocaleUpperCase('en-US');if(seen.has(codeKey))throw new Error('Código duplicado o equivalente '+code+' en filas '+seen.get(codeKey)+' y '+line+'. Revisá espacios y diferencias entre mayúsculas/minúsculas.');seen.set(codeKey,line);const central=excelNumber(r[col.central],'CENTRAL',line),cde=excelNumber(r[col.cde],'CDE',line),p1=excelNumber(r[col.p1],'precio 1',line),p2=excelNumber(r[col.p2],'precio 2',line),p3=excelNumber(r[col.p3],'precio 3',line);const payload={c:code,d:desc,p1:p1,p2:p2,p3:p3,sc:central,sd:cde};for(const [k,f] of [['factory','factoryCode'],['barcode','b'],['g1','g1'],['g2','g2'],['g3','g3'],['packages','envases'],['master','master'],['inner','inner']])if(col[k]!==undefined&&r[col[k]]!==null&&String(r[col[k]]).trim()!=='')payload[f]=String(r[col[k]]).trim();rows.push({code:code,payload:payload,stock_central:central,stock_cde:cde});}if(!rows.length)throw new Error('No se encontraron artículos.');return {rows:rows,sheetName:sheetName,headerRow:headerIndex+1};}
$('excel-import-file').addEventListener('change',async e=>{const file=e.target.files&&e.target.files[0];pendingImport=null;$('excel-import-confirm').disabled=true;if(!file)return;if(!(isGlobal||profile?.role==='company_admin'))return;try{if(!window.XLSX)throw new Error('No se cargó el lector Excel.');const wb=window.XLSX.read(await file.arrayBuffer(),{type:'array',cellDates:false}),parsed=readExcelRows(wb);if(parsed.rows.length>10000)throw new Error('El archivo contiene '+parsed.rows.length+' artículos. Esta versión admite hasta 10.000 filas por operación segura. No se guardó ningún cambio.');const existing=new Set(items.map(x=>String(x.c))),fresh=parsed.rows.filter(x=>!existing.has(x.code)).length;pendingImport={rows:parsed.rows,fileName:file.name};$('excel-import-preview').textContent='Archivo: '+file.name+' · Hoja: '+parsed.sheetName+' · Fila encabezado: '+parsed.headerRow+' · Artículos: '+parsed.rows.length+' · Nuevos: '+fresh+' · Actualizar: '+(parsed.rows.length-fresh)+'. Los ausentes se conservan.';$('excel-import-confirm').disabled=false;}catch(err){$('excel-import-preview').textContent='No se puede importar: '+err.message;}});
$('excel-import-confirm').addEventListener('click',async()=>{if(!pendingImport||!(isGlobal||profile?.role==='company_admin'))return;const b=$('excel-import-confirm');b.disabled=true;b.textContent='Importando…';let rpcCommitted=false;try{
 const rows=pendingImport.rows,importId=crypto.randomUUID();
 $('excel-import-preview').textContent='Enviando '+rows.length+' artículos en una única operación atómica. No cierres esta pantalla…';
 const result=await timeout(db.rpc('ab_import_company_catalog_v2',{p_company_id:activeCompany.id,p_import_id:importId,p_rows:rows}),'La importación completa',120000);
 if(result.error)throw new Error(result.error.message||'La base de datos rechazó la importación.');
 rpcCommitted=true;const processed=Number(result.data||0);
 await loadData();$('excel-import-preview').textContent='Importación completada: '+processed+' artículos procesados en una sola operación. Los artículos ausentes se conservaron y los stocks CENTRAL/CDE se actualizaron por separado.';pendingImport=null;$('excel-import-file').value='';
}catch(err){$('excel-import-preview').textContent=rpcCommitted?'La importación quedó guardada, pero no se pudo actualizar la pantalla: '+(err.message||'Error desconocido')+'. Usá Actualizar para recargar los datos.':'La operación no confirmó un resultado: '+(err.message||'Error desconocido')+'. La RPC es transaccional; si hubo un corte o tiempo agotado, verificá el catálogo antes de volver a intentar.';}finally{b.textContent='Confirmar importación';b.disabled=!pendingImport;}});

 function readClientExcelRows(workbook){
  const sheetName=workbook.SheetNames[0];if(!sheetName)throw new Error('El libro no contiene hojas.');
  const matrix=window.XLSX.utils.sheet_to_json(workbook.Sheets[sheetName],{header:1,defval:null,raw:false});
  const aliases={
   code:['CODIGO','CODIGOCLIENTE','CODCLIENTE','CODCLI','COD'],
   name:['NOMBRE','NOMBRECLIENTE','CLIENTE','RAZONSOCIAL','RAZONSOCIALCLIENTE','DESCRIPCION'],
   city:['CIUDAD','LOCALIDAD'],department:['DEPARTAMENTO','DPTO'],district:['DISTRITO'],
   phone:['TELEFONO','TELEFONOS','TEL','CELULAR','MOVIL','TELEFONOMOVIL'],
   docType:['TIPODOCUMENTO','TIPODOC','TIPOIDENTIFICACION','DOCUMENTO','TIPIDENT'],
   ident:['IDENTIFICACION','NUMEROIDENTIFICACION','NUMERODOCUMENTO','NRODOCUMENTO','NROIDENTIFICACION','RUC','CEDULA','CI'],
   balanceGs:['SALDOACTGS','SALDOACTUALGS'],balanceExt:['SALDOACTEXT','SALDOACTUALEXT'],
   debtAccount:['CTACBLEDEUDA','CUENTACONTABLEDEUDA']
  };
  let headerIndex=-1,col={};
  for(let i=0;i<matrix.length;i++){
   const headers=(matrix[i]||[]).map(normalizeHeader),candidate={};
   for(const [key,names] of Object.entries(aliases)){const found=names.map(n=>headers.indexOf(n)).filter(n=>n>=0);if(found.length>1)throw new Error('Hay encabezados duplicados para '+key+'.');if(found.length)candidate[key]=found[0];}
   if(candidate.code!==undefined&&candidate.name!==undefined){headerIndex=i;col=candidate;break;}
  }
  if(headerIndex<0)throw new Error('No se identificaron juntos los encabezados de código y nombre del cliente. La planilla original se debe validar para ajustar sus títulos exactos.');
  const seen=new Map(),rows=[],skippedRows=[];
  for(let i=headerIndex+1;i<matrix.length;i++){
   const r=matrix[i];if(!r||r.every(v=>v===null||String(v).trim()===''))continue;
   const line=i+1,code=String(r[col.code]??'').trim(),name=String(r[col.name]??'').trim();
   if(!code&&!name)continue;
   if(!code||!name){skippedRows.push({line,code,name});continue;}
   const codeKey=code.normalize('NFKC').toLocaleUpperCase('en-US');
   if(seen.has(codeKey))throw new Error('Código de cliente duplicado o equivalente '+code+' en filas '+seen.get(codeKey)+' y '+line+'. Revisá espacios y diferencias entre mayúsculas/minúsculas.');
   seen.set(codeKey,line);
   const payload={c:code,n:name};
   for(const [key,field] of [['city','ciu'],['department','dep'],['district','dst'],['phone','tel'],['docType','tip'],['ident','ident'],['balanceGs','saldoActGs'],['balanceExt','saldoActExt'],['debtAccount','ctaCbleDeuda']]){
    if(col[key]!==undefined&&r[col[key]]!==null&&String(r[col[key]]).trim()!=='')payload[field]=String(r[col[key]]).trim();
   }
   rows.push({code,payload});
  }
  if(!rows.length)throw new Error('No se encontraron clientes completos para importar. Filas incompletas omitidas: '+skippedRows.length+'.');
  return {rows,skippedRows,sheetName,headerRow:headerIndex+1};
 }
 $('client-excel-import-file').addEventListener('change',async e=>{
  const file=e.target.files&&e.target.files[0];pendingClientImport=null;$('client-excel-import-confirm').disabled=true;
  if(!file)return;
  if(isPublicDemo||!(isGlobal||profile?.role==='company_admin'))return;
  try{
   if(!window.XLSX)throw new Error('No se cargó el lector Excel.');
   const wb=window.XLSX.read(await file.arrayBuffer(),{type:'array',cellDates:false}),parsed=readClientExcelRows(wb);
   const existing=new Set(clients.map(x=>String(x.c))),fresh=parsed.rows.filter(x=>!existing.has(x.code)).length;
   pendingClientImport={rows:parsed.rows,skippedRows:parsed.skippedRows,fileName:file.name};
   const skippedInfo=parsed.skippedRows.length?' · Filas incompletas omitidas: '+parsed.skippedRows.length+' (ej.: '+parsed.skippedRows.slice(0,8).map(x=>x.line).join(', ')+(parsed.skippedRows.length>8?'…':'')+')':'';
   $('client-excel-import-preview').textContent='Archivo: '+file.name+' · Hoja: '+parsed.sheetName+' · Encabezados en fila: '+parsed.headerRow+' · Clientes válidos: '+parsed.rows.length+' · Nuevos: '+fresh+' · Actualizar: '+(parsed.rows.length-fresh)+skippedInfo+'. Los clientes ausentes se conservarán y los campos vacíos no borrarán datos existentes.';
   $('client-excel-import-confirm').disabled=false;
  }catch(err){$('client-excel-import-preview').textContent='No se puede importar: '+err.message;}
 });
 $('client-excel-import-confirm').addEventListener('click',async()=>{
  if(!pendingClientImport||isPublicDemo||!(isGlobal||profile?.role==='company_admin'))return;
  const b=$('client-excel-import-confirm');b.disabled=true;b.textContent='Importando…';
  try{
   const rows=pendingClientImport.rows;
   if(rows.length>10000)throw new Error('El archivo contiene '+rows.length+' clientes. Esta versión admite hasta 10.000 filas por operación segura.');
   const batchRows=rows.map(row=>{
    const previous=clients.find(c=>String(c.c)===String(row.code))||{};
    return {company_id:activeCompany.id,code:row.code,payload:{...previous,...row.payload}};
   });
   $('client-excel-import-preview').textContent='Guardando '+batchRows.length+' clientes en una única operación. No cierres esta pantalla…';
   const result=await timeout(db.from('catalog_clients').upsert(batchRows,{onConflict:'company_id,code'}),'La importación completa de clientes',120000);
   if(result.error)throw new Error(result.error.message||'La base de datos rechazó la importación.');
   await loadData();
   const skipped=pendingClientImport.skippedRows||[];
   $('client-excel-import-preview').textContent='Importación completada: '+batchRows.length+' clientes en una única operación. '+(skipped.length?'Se omitieron '+skipped.length+' filas incompletas (ej.: '+skipped.slice(0,8).map(x=>x.line).join(', ')+(skipped.length>8?'…':'')+'). ':'')+'Los clientes ausentes se conservaron.';
   pendingClientImport=null;$('client-excel-import-file').value='';
  }catch(err){$('client-excel-import-preview').textContent='La operación no confirmó un resultado: '+(err.message||'Error desconocido')+'. Si hubo un corte o tiempo agotado, verificá el listado antes de volver a intentar.';}
  finally{b.textContent='Importar clientes';b.disabled=!pendingClientImport;}
 });

 $('stock-search').addEventListener('input',renderStock);
$('archive-search-input').addEventListener('input',()=>{const q=$('archive-search-input').value.toLowerCase();$('archive-list').querySelectorAll('article').forEach(el=>el.hidden=!el.textContent.toLowerCase().includes(q));});
$('vendedor-input').addEventListener('change',()=>{});
gate('Ingresá con tu cuenta de AB SYSTEM.');
})();