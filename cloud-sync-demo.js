(() => {
'use strict';
const SUPABASE_URL='https://druugcvqxxanhtdkqnjd.supabase.co';
const SUPABASE_KEY='sb_publishable_M6W3DMCqPcH92cT96ioP5A_wi64QmcA';
if (!window.supabase || typeof window.supabase.createClient !== 'function') {
  document.getElementById('login-message').textContent = 'No se pudo cargar el servicio de acceso. Verificá tu conexión e intentá nuevamente.';
  return;
}
const db=window.supabase.createClient(SUPABASE_URL,SUPABASE_KEY);
const $=id=>document.getElementById(id);
let user=null,profile=null,items=[...window.DEMO_ITEMS],clients=[...window.DEMO_CLIENTS],cart=[];
const money=n=>'Gs. '+Number(n||0).toLocaleString('es-PY');
const safe=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function showLogin(msg){$('login').hidden=false;$('app').hidden=true;$('login-message').textContent=msg||'Acceso protegido';}
function withTimeout(promise,stage,ms=12000){let timer;const timeout=new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error(stage+' no respondió en 12 segundos.')),ms);});return Promise.race([promise,timeout]).finally(()=>clearTimeout(timer));}
function render(){
 $('metric-products').textContent=items.length;$('metric-clients').textContent=clients.length;
 const q=$('product-search').value.trim().toLowerCase();
 const filtered=items.filter(x=>[x.c,x.b,x.d].some(v=>String(v||'').toLowerCase().includes(q)));
 $('products').innerHTML=filtered.map(x=>'<div class="product"><div><strong>'+safe(x.d)+'</strong><small>'+safe(x.c)+' · Stock demo '+Number(x.sc||0)+'</small><small>'+money(x.p1)+'</small></div><button data-add="'+safe(x.c)+'">Agregar</button></div>').join('')||'<p class="muted">No se encontraron productos.</p>';
 $('products').querySelectorAll('[data-add]').forEach(b=>b.addEventListener('click',()=>add(b.dataset.add)));
 $('cart').innerHTML=cart.length?cart.map((x,i)=>'<div class="cart-row"><span>'+safe(x.d)+' × '+x.qty+'</span><span>'+money(x.p1*x.qty)+' <button data-remove="'+i+'">Quitar</button></span></div>').join(''):'<p class="muted">Todavía no agregaste productos.</p>';
 $('cart').querySelectorAll('[data-remove]').forEach(b=>b.addEventListener('click',()=>{cart.splice(Number(b.dataset.remove),1);renderCartOnly();}));
 $('total').textContent=money(cart.reduce((s,x)=>s+x.p1*x.qty,0));
}
function renderCartOnly(){render();}
function add(code){const x=items.find(i=>String(i.c)===String(code));if(!x)return;const found=cart.find(i=>i.c===x.c);if(found)found.qty++;else cart.push({...x,qty:1});render();}
async function loadData(){
 showLogin('Perfil verificado. Cargando productos y clientes DEMO…');
 const [ir,cr]=await withTimeout(Promise.all([db.from('catalog_items').select('code,payload').order('code'),db.from('catalog_clients').select('code,payload').order('code')]),'La carga de productos y clientes');
 if(ir.error)throw ir.error;if(cr.error)throw cr.error;
 if(ir.data.length)items=ir.data.map(x=>x.payload);if(cr.data.length)clients=cr.data.map(x=>x.payload);
 $('client').innerHTML='<option value="">Seleccionar cliente</option>'+clients.map(x=>'<option value="'+safe(x.c)+'">'+safe(x.n)+'</option>').join('');
 const labels=profile.role==='admin'?['VENDEDOR DEMO 1','VENDEDOR DEMO 2','VENDEDOR DEMO 3']:[];
 showLogin('Catálogo cargado. Verificando permisos de vendedor…');
 const {data:assignments,error}=await withTimeout(db.from('seller_assignments').select('seller_label').eq('user_id',user.id),'La verificación de permisos');
 if(error)throw error;
 const allowed=profile.role==='admin'?labels:(assignments||[]).map(x=>x.seller_label);
 if(profile.role==='seller'&&!allowed.length)throw new Error('La cuenta no tiene vendedores DEMO asignados.');
 $('seller').innerHTML='<option value="">Seleccionar vendedor</option>'+allowed.map(x=>'<option>'+safe(x)+'</option>').join('');
 render();showLogin('Permisos verificados. Cargando pedidos DEMO…');await loadOrders();
}
async function loadOrders(){
 showLogin('DIAGNÓSTICO DEMO: iniciando consulta de pedidos…');
 const watchdog=setTimeout(()=>showLogin('DIAGNÓSTICO DEMO: la consulta sigue pendiente después de 5 segundos.'),5000);
 try{
  showLogin('DIAGNÓSTICO DEMO: enviando consulta a Supabase…');
  const request=db.from('orders').select('id,legacy_id,legacy_source,payload,updated_at').order('updated_at',{ascending:false}).limit(30);
  const result=await withTimeout(request,'La carga de pedidos');
  clearTimeout(watchdog);
  showLogin('DIAGNÓSTICO DEMO: respuesta recibida; procesando pedidos…');
  if(result.error)throw result.error;
  const data=result.data||[];
  $('metric-orders').textContent=data.length;
  $('orders').innerHTML=data.map(x=>'<div class="order-row"><div><strong>'+safe(x.payload?.cliente||'Pedido DEMO')+'</strong><small>'+safe(x.payload?.vendedor||'')+' · '+new Date(x.updated_at).toLocaleString('es-PY')+'</small></div><strong>'+money(x.payload?.total)+'</strong></div>').join('')||'<p class="muted">Todavía no hay pedidos guardados.</p>';
  showLogin('DIAGNÓSTICO DEMO: pedidos procesados; finalizando acceso…');
 }catch(error){clearTimeout(watchdog);throw error;}
}
async function activate(sessionUser){
 user=sessionUser;
 showLogin('Acceso autenticado. Verificando perfil DEMO…');
 const {data:p,error}=await withTimeout(db.from('profiles').select('role,seller_label').eq('id',user.id).single(),'La consulta del perfil');
 if(error)throw error;profile=p;
 if(!['admin','seller'].includes(profile.role))throw new Error('Perfil sin permisos.');
 $('user-label').textContent=profile.role==='admin'?'Administrador DEMO':profile.seller_label||user.email;
 await loadData();$('login').hidden=true;$('app').hidden=false;$('connection').textContent='Conectado a Supabase DEMO';
}
$('login-form').addEventListener('submit',async e=>{
 e.preventDefault();const btn=$('login-form').querySelector('button[type="submit"]');if(btn)btn.disabled=true;showLogin('Conectando con Supabase DEMO…');
 try{
  const result=await withTimeout(db.auth.signInWithPassword({email:$('email').value.trim(),password:$('password').value}),'La autenticación');
  if(result.error)throw result.error;
  await activate(result.data.user);
 }catch(err){
  db.auth.signOut().catch(()=>{});
  showLogin('No se pudo ingresar: '+(err?.message||'Error desconocido'));
 }finally{if(btn)btn.disabled=false;}
});
$('logout').addEventListener('click',async()=>{await db.auth.signOut();user=null;profile=null;cart=[];showLogin('Sesión cerrada.');});
$('product-search').addEventListener('input',render);
$('save-order').addEventListener('click',async()=>{
 const msg=$('order-message');if(!cart.length){msg.textContent='Agregá al menos un producto.';return;}
 const seller=$('seller').value,clientCode=$('client').value;if(!seller||!clientCode){msg.textContent='Seleccioná vendedor y cliente.';return;}
 const clientRow=clients.find(x=>String(x.c)===clientCode),id='demo_'+crypto.randomUUID();
 const total=cart.reduce((s,x)=>s+x.p1*x.qty,0),now=new Date().toISOString();
 const payload={id,vendedor:seller,cliente:clientRow.n,clienteCodigo:clientRow.c,clienteCiudad:clientRow.ciu,estado:'pendiente',condicion:'Contado',lines:cart.map(x=>({code:x.c,description:x.d,qty:x.qty,tier:1,price:x.p1})),total,createdAt:now,updatedAt:now,demo:true};
 const {error}=await db.from('orders').insert({owner_id:user.id,legacy_id:id,legacy_source:'archive',payload,updated_at:now});
 if(error){msg.textContent='No se pudo guardar: '+error.message;return;}
 cart=[];render();msg.textContent='Pedido DEMO guardado correctamente.';await loadOrders();
});
$('refresh').addEventListener('click',()=>loadOrders().catch(e=>$('connection').textContent='Error: '+e.message));
showLogin('Ingresá con tu cuenta de AB SYSTEM DEMO.');
})();