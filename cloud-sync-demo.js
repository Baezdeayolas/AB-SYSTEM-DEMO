(() => {
'use strict';
const SUPABASE_URL='https://druugcvqxxanhtdkqnjd.supabase.co';
const SUPABASE_KEY='sb_publishable_M6W3DMCqPcH92cT96ioP5A_wi64QmcA';
const $=id=>document.getElementById(id);
if(!window.supabase?.createClient){$('login-message').textContent='No se pudo cargar el servicio de acceso DEMO.';return;}
const db=window.supabase.createClient(SUPABASE_URL,SUPABASE_KEY);
let user=null,profile=null,items=[...window.DEMO_ITEMS],clients=[...window.DEMO_CLIENTS],cart=[],orders=[],tier=1,estado='pendiente',condicion='Contado';
const money=n=>'Gs. '+Math.round(Number(n||0)).toLocaleString('es-PY');
const safe=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const timeout=(p,label)=>Promise.race([p,new Promise((_,rej)=>setTimeout(()=>rej(new Error(label+' no respondió.')),12000))]);
function gate(msg){$('login').hidden=false;$('app').hidden=true;$('login-message').textContent=msg||'Acceso protegido';}
function showPanel(id){document.querySelectorAll('main .panel').forEach(p=>p.classList.toggle('active',p.id===id));document.querySelectorAll('.tabs [data-panel]').forEach(b=>b.classList.toggle('active',b.dataset.panel===id));}
function total(){return cart.reduce((s,x)=>s+x['p'+tier]*x.qty,0);}
function render(){
 const q=$('search-input').value.trim().toLowerCase(),filtered=items.filter(x=>[x.c,x.b,x.d].some(v=>String(v||'').toLowerCase().includes(q)));
 $('result-count').textContent=filtered.length+' productos DEMO';
 $('item-list').innerHTML=filtered.map(x=>'<article class="item-card"><div class="item-top"><span class="item-code">'+safe(x.c)+'</span><span class="item-stock">Stock DEMO '+Number(x.sc||0)+'</span></div><div class="item-desc">'+safe(x.d)+'</div><div class="item-bottom"><strong class="item-price">'+money(x['p'+tier])+'</strong><div class="item-actions"><input class="qty-input" type="number" min="1" value="1" aria-label="Cantidad" data-qty="'+safe(x.c)+'"><button class="add-btn" data-add="'+safe(x.c)+'">Agregar</button></div></div></article>').join('')||'<div class="empty-state">No se encontraron productos.</div>';
 $('item-list').querySelectorAll('[data-add]').forEach(b=>b.onclick=()=>{const code=b.dataset.add,qty=Math.max(1,Number($('item-list').querySelector('[data-qty="'+CSS.escape(code)+'"]').value)||1);add(code,qty);});
 $('order-list').innerHTML=cart.map((x,i)=>'<article class="order-card"><div class="order-top"><div class="order-code-desc"><strong>'+safe(x.d)+'</strong><small>'+safe(x.c)+' · '+x.qty+' unidad(es)</small></div><button class="order-remove" data-remove="'+i+'" aria-label="Quitar">×</button></div><div class="order-bottom"><span>'+money(x['p'+tier])+' c/u</span><strong class="line-subtotal">'+money(x['p'+tier]*x.qty)+'</strong></div></article>').join('');
 $('order-list').querySelectorAll('[data-remove]').forEach(b=>b.onclick=()=>{cart.splice(Number(b.dataset.remove),1);render();});
 const sub=total(),discount=Math.min(100,Math.max(0,Number($('discount-input').value)||0)),off=sub*discount/100,grand=sub-off;
 $('total-value').textContent=money(grand);$('discount-total').textContent='Subtotal: '+money(sub);$('discount-value').textContent='Descuento: '+money(off);
 $('order-empty').hidden=cart.length>0;$('tab-order-count').textContent=cart.reduce((s,x)=>s+x.qty,0);
 $('dashboard-units').textContent=items.length;$('dashboard-sales').textContent=clients.length;
 $('dashboard-orders').textContent=orders.length;$('dashboard-pending').textContent=orders.filter(o=>o.payload?.estado!=='confirmado').length;
 $('archive-summary-count').textContent=orders.length+' pedidos';$('tab-archive-count').textContent=orders.length;
 $('archive-list').innerHTML=orders.map(o=>'<article class="order-card"><div class="order-top"><div><strong>'+safe(o.payload?.cliente||'Pedido DEMO')+'</strong><small>'+safe(o.payload?.vendedor||'')+' · '+new Date(o.updated_at).toLocaleString('es-PY')+'</small></div><strong>'+money(o.payload?.total)+'</strong></div></article>').join('');
 $('archive-empty').hidden=orders.length>0;
 $('stock-list').innerHTML=items.map(x=>'<article class="order-card"><strong>'+safe(x.d)+'</strong><small>'+safe(x.c)+' · Stock ficticio: '+Number(x.sc||0)+'</small></article>').join('');
}
function add(code,qty){const item=items.find(x=>String(x.c)===String(code));if(!item)return;const row=cart.find(x=>x.c===item.c);if(row)row.qty+=qty;else cart.push({...item,qty});render();}
async function loadData(){
 const [ir,cr]=await timeout(Promise.all([db.from('catalog_items').select('code,payload').order('code'),db.from('catalog_clients').select('code,payload').order('code')]),'La carga de catálogo');
 if(ir.error)throw ir.error;if(cr.error)throw cr.error;
 if(ir.data?.length)items=ir.data.map(x=>x.payload);if(cr.data?.length)clients=cr.data.map(x=>x.payload);
 const {data:as,error:ae}=await timeout(db.from('seller_assignments').select('seller_label').eq('user_id',user.id),'Los permisos de vendedor');if(ae)throw ae;
 const sellers=profile.role==='admin'?['VENDEDOR DEMO 1','VENDEDOR DEMO 2','VENDEDOR DEMO 3']:(as||[]).map(x=>x.seller_label);
 if(profile.role==='seller'&&!sellers.length)throw new Error('La cuenta no tiene vendedores DEMO asignados.');
 $('vendedor-input').innerHTML='<option value="">Vendedor</option>'+sellers.map(x=>'<option value="'+safe(x)+'">'+safe(x)+'</option>').join('');
 render();await loadOrders();
}
async function loadOrders(){
 const {data,error}=await timeout(db.from('orders').select('id,legacy_id,legacy_source,payload,updated_at').order('updated_at',{ascending:false}).limit(50),'La carga de pedidos');
 if(error)throw error;orders=data||[];render();
}
async function activate(u){
 user=u;const {data:p,error}=await timeout(db.from('profiles').select('role,seller_label').eq('id',u.id).single(),'La consulta del perfil');if(error)throw error;
 profile=p;if(!['admin','seller'].includes(profile.role))throw new Error('Perfil sin permisos DEMO.');
 await loadData();$('login').hidden=true;$('app').hidden=false;$('cloud-status-slot').textContent='Conectado · DEMO';
 $('admin-menu-tab').hidden=profile.role!=='admin';showPanel('panel-search');
}
$('login-form').addEventListener('submit',async e=>{e.preventDefault();const b=$('login-form').querySelector('button');b.disabled=true;gate('Conectando con Supabase DEMO…');try{const r=await timeout(db.auth.signInWithPassword({email:$('email').value.trim(),password:$('password').value}),'El acceso');if(r.error)throw r.error;await activate(r.data.user);}catch(err){await db.auth.signOut();gate('No se pudo ingresar: '+(err.message||'Error desconocido'));}finally{b.disabled=false;}});
$('logout').onclick=async()=>{await db.auth.signOut();user=null;profile=null;cart=[];gate('Sesión cerrada.');};
document.querySelectorAll('.tabs [data-panel]').forEach(b=>b.addEventListener('click',()=>showPanel(b.dataset.panel)));
$('search-input').addEventListener('input',render);$('discount-input').addEventListener('input',render);
document.querySelectorAll('[data-tier]').forEach(b=>b.onclick=()=>{tier=Number(b.dataset.tier);document.querySelectorAll('[data-tier]').forEach(x=>x.classList.toggle('active',x===b));render();});
document.querySelectorAll('[data-estado]').forEach(b=>b.onclick=()=>{estado=b.dataset.estado;document.querySelectorAll('[data-estado]').forEach(x=>x.classList.toggle('active',x===b));});
document.querySelectorAll('[data-condicion]').forEach(b=>b.onclick=()=>{condicion=b.dataset.condicion;$('condicion-input').value=condicion;document.querySelectorAll('[data-condicion]').forEach(x=>x.classList.toggle('active',x===b));});
$('nuevo-cliente-toggle').onclick=()=>{$('nuevo-cliente-panel').hidden=!$('nuevo-cliente-panel').hidden;};
$('cliente-input').addEventListener('input',()=>{const q=$('cliente-input').value.toLowerCase();const matches=clients.filter(c=>[c.c,c.n].some(v=>String(v||'').toLowerCase().includes(q))).slice(0,8);$('cliente-suggestions').innerHTML=matches.map(c=>'<button type="button" class="cliente-suggestion" data-client="'+safe(c.c)+'"><span class="cs-text"><span class="cs-name">'+safe(c.n)+'</span><span class="cs-meta">'+safe(c.c)+'</span></span></button>').join('');$('cliente-suggestions').classList.toggle('open',matches.length>0);$('cliente-suggestions').querySelectorAll('[data-client]').forEach(b=>b.onclick=()=>{const c=clients.find(x=>String(x.c)===b.dataset.client);$('cliente-input').value=c.n;$('cliente-input').dataset.code=c.c;$('cliente-suggestions').classList.remove('open');});});
$('save-order').onclick=async()=>{
 const msg=$('order-message');const seller=$('vendedor-input').value,clientCode=$('cliente-input').dataset.code;
 if(!cart.length){msg.textContent='Agregá al menos un artículo.';return;}
 if(!seller||!clientCode){msg.textContent='Seleccioná vendedor y cliente de la lista.';return;}
 const client=clients.find(c=>String(c.c)===String(clientCode));if(!client){msg.textContent='Seleccioná un cliente válido.';return;}
 const sub=total(),discount=Math.min(100,Math.max(0,Number($('discount-input').value)||0)),grand=sub-(sub*discount/100),now=new Date().toISOString(),id='demo_'+crypto.randomUUID();
 const payload={id,vendedor:seller,cliente:client.n,clienteCodigo:client.c,estado,condicion:$('condicion-input').value||condicion,lines:cart.map(x=>({code:x.c,description:x.d,qty:x.qty,tier,price:x['p'+tier]})),subtotal:sub,discount,total:grand,createdAt:now,updatedAt:now,demo:true};
 const {error}=await db.from('orders').insert({owner_id:user.id,legacy_id:id,legacy_source:'archive',payload,updated_at:now});
 if(error){msg.textContent='No se pudo guardar el pedido: '+error.message;return;}
 cart=[];$('discount-input').value='0';msg.textContent='Pedido DEMO guardado correctamente.';await loadOrders();showPanel('panel-archive');
};
$('btn-clear').onclick=()=>{cart=[];$('discount-input').value='0';$('cliente-input').value='';$('cliente-input').dataset.code='';render();showPanel('panel-search');};
$('btn-pdf').onclick=()=>alert('La generación y el compartir PDF se integrarán en la siguiente etapa de funciones DEMO.');
$('btn-scan-barcode').onclick=()=>alert('El escáner se integrará después de validar el flujo de búsqueda DEMO.');
$('dashboard-refresh').onclick=()=>loadOrders().catch(e=>$('cloud-status-slot').textContent=e.message);
$('stock-search').addEventListener('input',()=>{const q=$('stock-search').value.toLowerCase();$('stock-list').querySelectorAll('article').forEach(el=>el.hidden=!el.textContent.toLowerCase().includes(q));});
$('archive-search-input').addEventListener('input',()=>{const q=$('archive-search-input').value.toLowerCase();$('archive-list').querySelectorAll('article').forEach(el=>el.hidden=!el.textContent.toLowerCase().includes(q));});
$('vendedor-input').addEventListener('change',()=>{});
gate('Ingresá con tu cuenta de AB SYSTEM DEMO.');
})();