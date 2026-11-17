(() => {
'use strict';
const SUPABASE_URL='https://druugcvqxxanhtdkqnjd.supabase.co';
const SUPABASE_KEY='sb_publishable_M6W3DMCqPcH92cT96ioP5A_wi64QmcA';
const $=id=>document.getElementById(id);
if(!window.supabase?.createClient){$('login-message').textContent='No se pudo cargar el servicio de acceso DEMO.';return;}
const db=window.supabase.createClient(SUPABASE_URL,SUPABASE_KEY);
let user=null,profile=null,companies=[],activeCompany=null,isGlobal=false,items=[],clients=[],sellerRows=[],cart=[],orders=[],tier=1,estado='pendiente',condicion='Contado';
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
 $('result-count').textContent=filtered.length+' productos · '+(activeCompany?.name||'empresa');
 $('item-list').innerHTML=filtered.map(x=>'<article class="item-card"><div class="item-top"><span class="item-code">'+safe(x.c)+'</span><span class="item-stock">Stock '+Number(x.sc||0)+'</span></div><div class="item-desc">'+safe(x.d)+'</div><div class="item-bottom"><strong class="item-price">'+money(x['p'+tier])+'</strong><div class="item-actions"><input class="qty-input" type="number" min="1" value="1" aria-label="Cantidad" data-qty="'+safe(x.c)+'"><button class="add-btn" data-add="'+safe(x.c)+'">Agregar</button></div></div></article>').join('')||'<div class="empty-state">No se encontraron productos.</div>';
 $('item-list').querySelectorAll('[data-add]').forEach(b=>b.onclick=()=>{const code=b.dataset.add,qty=Math.max(1,Number($('item-list').querySelector('[data-qty="'+CSS.escape(code)+'"]').value)||1);add(code,qty);});
 $('order-list').innerHTML=cart.map((x,i)=>'<article class="order-card"><div class="order-top"><div class="order-code-desc"><strong>'+safe(x.d)+'</strong><small>'+safe(x.c)+' · '+x.qty+' unidad(es)</small></div><button class="order-remove" data-remove="'+i+'" aria-label="Quitar">×</button></div><div class="order-bottom"><span>'+money(x['p'+tier])+' c/u</span><strong class="line-subtotal">'+money(x['p'+tier]*x.qty)+'</strong></div></article>').join('');
 $('order-list').querySelectorAll('[data-remove]').forEach(b=>b.onclick=()=>{cart.splice(Number(b.dataset.remove),1);render();});
 const sub=total(),discount=Math.min(100,Math.max(0,Number($('discount-input').value)||0)),off=sub*discount/100,grand=sub-off;
 $('total-value').textContent=money(grand);$('discount-total').textContent='Subtotal: '+money(sub);$('discount-value').textContent='Descuento: '+money(off);
 $('order-empty').hidden=cart.length>0;$('tab-order-count').textContent=cart.reduce((s,x)=>s+x.qty,0);
 $('dashboard-units').textContent=items.length;$('dashboard-sales').textContent=clients.length;
 $('dashboard-orders').textContent=orders.length;$('dashboard-pending').textContent=orders.filter(o=>o.payload?.estado!=='confirmado').length;
 $('archive-summary-count').textContent=orders.length+' pedidos';$('archive-summary-value').textContent=money(orders.reduce((sum,o)=>sum+Number(o.payload?.total||0),0));$('tab-archive-count').textContent=orders.length;
 $('archive-list').innerHTML=orders.map(o=>'<article class="order-card"><div class="order-top"><div><strong>'+safe(o.payload?.cliente||'Pedido DEMO')+'</strong><small>'+safe(o.payload?.vendedor||'')+' · '+new Date(o.updated_at).toLocaleString('es-PY')+'</small></div><strong>'+money(o.payload?.total)+'</strong></div></article>').join('');
 $('archive-empty').hidden=orders.length>0;
 $('stock-list').innerHTML=items.map(x=>'<article class="order-card"><strong>'+safe(x.d)+'</strong><small>'+safe(x.c)+' · Stock: '+Number(x.sc||0)+'</small></article>').join('');
}
function add(code,qty){const item=items.find(x=>String(x.c)===String(code));if(!item)return;const row=cart.find(x=>x.c===item.c);if(row)row.qty+=qty;else cart.push({...item,qty});render();}
async function loadData(){
 if(!activeCompany?.id)throw new Error('No hay una empresa activa.');
 const [ir,cr,br]=await timeout(Promise.all([
  db.from('catalog_items').select('code,payload').eq('company_id',activeCompany.id).order('code'),
  db.from('catalog_clients').select('code,payload').eq('company_id',activeCompany.id).order('code'),
  db.from('inventory_balances').select('product_code,quantity').eq('company_id',activeCompany.id)
 ]),'La carga de catálogo e inventario');
 if(ir.error)throw ir.error;if(cr.error)throw cr.error;if(br.error)throw br.error;
 const stockByCode=new Map((br.data||[]).map(x=>[String(x.product_code),Number(x.quantity)||0]));
 items=(ir.data||[]).map(x=>({...x.payload,c:x.payload?.c??x.code,sc:stockByCode.get(String(x.code))??0}));
 clients=(cr.data||[]).map(x=>x.payload);
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
$('btn-pdf').onclick=()=>alert('La generación y el compartir PDF se integrarán en la siguiente etapa de funciones DEMO.');
$('btn-scan-barcode').onclick=()=>alert('El escáner se integrará después de validar el flujo de búsqueda DEMO.');
$('dashboard-refresh').onclick=()=>loadOrders().catch(e=>$('cloud-status-slot').textContent=e.message);
$('stock-search').addEventListener('input',()=>{const q=$('stock-search').value.toLowerCase();$('stock-list').querySelectorAll('article').forEach(el=>el.hidden=!el.textContent.toLowerCase().includes(q));});
$('archive-search-input').addEventListener('input',()=>{const q=$('archive-search-input').value.toLowerCase();$('archive-list').querySelectorAll('article').forEach(el=>el.hidden=!el.textContent.toLowerCase().includes(q));});
$('vendedor-input').addEventListener('change',()=>{});
gate('Ingresá con tu cuenta de AB SYSTEM.');
})();