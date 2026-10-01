/* MiEspacioParaCelebrar · Panel de administración */
(function(){
  'use strict';

  const state = { client:null, spaces:[], owners:[], bookings:[], selectedSpace:null };
  const money = n => new Intl.NumberFormat('es-ES',{style:'currency',currency:'EUR'}).format(Number(n||0));
  const date = d => d ? new Intl.DateTimeFormat('es-ES',{day:'2-digit',month:'2-digit',year:'numeric'}).format(new Date(`${d}T12:00:00`)) : '—';
  const esc = v => String(v??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
  const val = (root,id) => root.querySelector(id)?.value?.trim() || '';
  const num = (root,id) => val(root,id)==='' ? null : Number(val(root,id));
  const toast = (root,msg,error=false) => { const el=root.querySelector('.admin-message'); if(el){el.textContent=msg;el.classList.toggle('error',error);} };

  async function client(){
    if(state.client) return state.client;
    if(!window.supabase || !window.MIESPACIO_SUPABASE_ANON_KEY) return null;
    state.client=window.supabase.createClient('https://hvuseljtqdgekotrsiwd.supabase.co',window.MIESPACIO_SUPABASE_ANON_KEY);
    return state.client;
  }

  async function requireAdmin(){
    const c=await client(); if(!c) throw new Error('No se ha podido conectar con Supabase.');
    const {data:{user},error}=await c.auth.getUser(); if(error) throw error;
    if(!user){location.href='acceso.html';return null;}
    const {data:profile,error:pe}=await c.from('profiles').select('id,email,first_name,last_name,role,active').eq('id',user.id).maybeSingle();
    if(pe) throw pe;
    if(!profile || profile.role!=='admin' || profile.active!==true){location.href='area-privada.html';return null;}
    return c;
  }

  async function loadAll(c){
    const [sp,ow,bk]=await Promise.all([
      c.rpc('admin_get_spaces'),
      c.rpc('admin_get_owners'),
      c.rpc('admin_get_bookings')
    ]);
    if(sp.error) throw sp.error; if(ow.error) throw ow.error; if(bk.error) throw bk.error;
    state.spaces=sp.data||[]; state.owners=ow.data||[]; state.bookings=bk.data||[];
  }

  function shell(){
    const root=document.querySelector('#adminArea');
    if(!document.getElementById('mep-admin-responsive-fix')){
      const st=document.createElement('style');st.id='mep-admin-responsive-fix';
      st.textContent=`
/* =========================================================
   MiEspacioParaCelebrar · RESPONSIVE ADMINISTRACIÓN v2
   Objetivo: ningún botón ni contenido queda cortado en escritorio,
   tablet, móvil vertical u horizontal.
========================================================= */

.admin-shell,
.admin-shell *{box-sizing:border-box}
.admin-shell{width:100%;min-width:0;max-width:100%;overflow:hidden}
.admin-main{min-width:0;max-width:100%;width:100%;overflow-x:hidden}
#adminView{width:100%;min-width:0;max-width:100%}

/* Cabecera de cada pantalla */
.admin-view-head,
.admin-card-head,
.section-head{
  min-width:0;
}
.admin-view-head{
  display:flex;
  align-items:flex-end;
  justify-content:space-between;
  gap:18px;
  flex-wrap:wrap;
}
.admin-view-head > *{min-width:0}
.admin-view-head > .btn,
.admin-view-head > button,
.admin-view-head > select{flex:0 1 auto;max-width:100%}

/* Tarjetas y formularios */
.admin-card,
.admin-panel,
.admin-section,
.admin-dashboard-grid > section{
  width:100%;
  min-width:0;
  max-width:100%;
}
.admin-card{overflow:hidden}
.admin-form-grid{
  width:100%;
  min-width:0;
}
.admin-form-grid label,
.admin-form-grid input,
.admin-form-grid select,
.admin-form-grid textarea{
  min-width:0;
  max-width:100%;
}
.admin-form-grid input,
.admin-form-grid select,
.admin-form-grid textarea{width:100%}

/* Botones: nunca desbordan su contenedor */
.admin-shell .btn,
.admin-shell button,
.admin-shell input,
.admin-shell select,
.admin-shell textarea{
  max-width:100%;
}
.admin-shell .btn{
  white-space:normal;
  overflow-wrap:anywhere;
  line-height:1.2;
  min-height:42px;
}
.admin-shell .full{width:100%}

/* TABLAS DESKTOP/TABLET ---------------------------------- */
.admin-table-wrap{
  width:100%;
  max-width:100%;
  min-width:0;
  overflow-x:auto;
  overflow-y:hidden;
  -webkit-overflow-scrolling:touch;
}
.admin-table{
  width:100%;
  min-width:760px;
  max-width:none;
  table-layout:fixed;
}
.admin-table th,
.admin-table td{
  min-width:0;
  overflow-wrap:anywhere;
  word-break:break-word;
  vertical-align:middle;
}
.admin-table td.table-actions,
.admin-table td[data-label="Acciones"]{
  overflow:visible;
}
.admin-table td.table-actions,
.admin-table td[data-label="Acciones"]{
  display:table-cell;
  vertical-align:middle;
  white-space:normal;
}
.admin-table td.table-actions .btn,
.admin-table td[data-label="Acciones"] .btn{
  display:inline-flex;
  align-items:center;
  justify-content:center;
  width:auto;
  min-width:94px;
  max-width:100%;
  margin:4px 2px;
  white-space:normal !important;
  vertical-align:middle;
}
/* El último campo recibe espacio suficiente para acciones */
.admin-table th:last-child,
.admin-table td:last-child{width:23%}
.admin-table th:nth-last-child(2),
.admin-table td:nth-last-child(2){width:14%}

/* Para tablas de datos muy anchas (emails/encuestas), el scroll queda
   dentro de la tarjeta, nunca en toda la página. */
.admin-table-wrap::-webkit-scrollbar{height:8px}

/* Listados y bloques internos */
.admin-list-row,
.block-list > div,
.photo-grid,
.tool-tabs{
  min-width:0;
  max-width:100%;
}
.photo-grid{grid-template-columns:repeat(auto-fit,minmax(180px,1fr))}
.tool-tabs{display:flex;flex-wrap:wrap;gap:8px}
.tool-tabs button{flex:1 1 130px;min-height:42px}
.block-form{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px;align-items:end}
.block-form label{min-width:0}
.block-form input{width:100%;max-width:100%}

/* MODALES */
.modal-backdrop{
  padding:16px;
  overflow:auto;
}
.modal-card,
.admin-modal{
  width:min(920px,100%);
  max-width:100%;
  max-height:calc(100vh - 32px);
  overflow:auto;
  box-sizing:border-box;
}
.modal-title,
.modal-actions{min-width:0}
.modal-title{display:flex;align-items:flex-start;justify-content:space-between;gap:16px}
.modal-title > *{min-width:0}
.modal-x{flex:0 0 auto}

/* TABLET */
@media (max-width:1100px){
  .admin-sidebar{width:250px;flex:0 0 250px}
  .admin-main{padding-left:20px;padding-right:20px}
  .admin-table{min-width:720px}
  .block-form{grid-template-columns:repeat(2,minmax(0,1fr))}
}

/* MÓVIL VERTICAL Y HORIZONTAL */
@media (max-width:760px){
  .admin-shell{overflow:visible}
  .admin-main{
    width:100%;
    max-width:100%;
    padding:0 10px 28px;
    overflow-x:hidden;
  }
  .admin-mobile-top{
    position:sticky;
    top:0;
    z-index:30;
    width:100%;
  }
  .admin-view-head{
    align-items:stretch;
    flex-direction:column;
    gap:12px;
  }
  .admin-view-head > .btn,
  .admin-view-head > button,
  .admin-view-head > select{
    width:100%;
    flex:0 0 auto;
  }
  .admin-kpis{grid-template-columns:1fr 1fr !important}
  .admin-dashboard-grid{grid-template-columns:1fr !important}

  .admin-actions,
  .admin-filters{
    width:100%;
    display:grid;
    grid-template-columns:1fr;
    gap:10px;
  }
  .admin-actions .btn,
  .admin-filters select{width:100%;min-height:44px}

  /* Todas las tablas se convierten en tarjetas */
  .admin-table-wrap{overflow:visible}
  .admin-table{
    display:block;
    width:100%;
    min-width:0;
    table-layout:auto;
  }
  .admin-table thead{display:none}
  .admin-table tbody{display:grid;gap:12px}
  .admin-table tr{
    display:block;
    width:100%;
    min-width:0;
    padding:12px 14px;
    background:#fff;
    border:1px solid #e1e3dc;
    border-radius:16px;
  }
  .admin-table td{
    display:grid;
    grid-template-columns:minmax(78px,30%) minmax(0,1fr);
    gap:10px;
    width:100% !important;
    padding:8px 0;
    border:0;
    min-width:0;
  }
  .admin-table td::before{
    content:attr(data-label);
    font-weight:700;
    color:#596153;
  }
  .admin-table td[colspan]::before{display:none}
  .admin-table td.table-actions,
  .admin-table td[data-label="Acciones"]{
    display:grid;
    grid-template-columns:1fr;
    gap:8px;
    padding-top:12px;
    border-top:1px solid #eceee8;
  }
  .admin-table td.table-actions::before,
  .admin-table td[data-label="Acciones"]::before{display:none}
  .admin-table td.table-actions .btn,
  .admin-table td[data-label="Acciones"] .btn{
    width:100%;
    min-width:0;
    min-height:46px;
    margin:0;
  }

  .admin-form-grid{grid-template-columns:1fr !important}
  .form-wide{grid-column:1/-1}
  .block-form{grid-template-columns:1fr}
  .block-form .btn{width:100%;min-height:46px}
  .modal-backdrop{padding:10px}
  .modal-card,
  .admin-modal{
    width:100%;
    max-width:100%;
    max-height:calc(100vh - 20px);
    overflow:auto;
  }
  .modal-actions{display:grid;grid-template-columns:1fr;gap:8px}
  .modal-actions .btn{width:100%;min-height:46px}
  .photo-grid{grid-template-columns:1fr 1fr}
}

/* MÓVIL HORIZONTAL ESTRECHO */
@media (max-width:760px) and (orientation:landscape){
  .admin-main{padding-left:8px;padding-right:8px}
  .admin-mobile-top{min-height:48px}
  .admin-kpis{grid-template-columns:repeat(4,minmax(0,1fr)) !important}
  .admin-dashboard-grid{grid-template-columns:1fr 1fr !important}
  .photo-grid{grid-template-columns:repeat(3,minmax(0,1fr))}
  .modal-card,.admin-modal{max-height:calc(100vh - 12px)}
}

/* MÓVIL MUY ESTRECHO */
@media (max-width:430px){
  .admin-main{padding-left:6px;padding-right:6px}
  .admin-kpis{grid-template-columns:1fr !important}
  .admin-table tr{padding:10px}
  .admin-table td{grid-template-columns:74px minmax(0,1fr);font-size:.93rem}
  .photo-grid{grid-template-columns:1fr}
}
`;
      document.head.appendChild(st);
    }
    root.innerHTML=`<div class="admin-shell">
      <aside class="admin-sidebar">
        <div class="admin-sidebar-brand"><img src="assets/logo-miespacio-oficial.png" alt="MiEspacioParaCelebrar"><span>Administración</span></div>
        <nav class="admin-side-nav">
          <button data-view="dashboard" class="active">Inicio</button>
          <button data-view="spaces">Espacios</button>
          <button data-view="owners">Propietarios</button>
          <button data-view="bookings">Reservas</button>
          <button data-view="calendar">Calendario</button><button data-view="catalog">Servicios</button><button data-view="emails">Emails</button><button data-view="surveys">Encuestas</button>
        </nav>
        <button id="adminLogout" class="admin-logout">Cerrar sesión</button>
      </aside>
      <section class="admin-main">
        <div class="admin-mobile-top"><button id="adminMenu" aria-label="Abrir menú">☰</button><strong>Administración</strong></div>
        <div id="adminView"></div>
      </section>
    </div>`;
    root.querySelectorAll('[data-view]').forEach(b=>b.addEventListener('click',()=>{root.querySelectorAll('[data-view]').forEach(x=>x.classList.remove('active'));b.classList.add('active');renderView(b.dataset.view);}));
    root.querySelector('#adminLogout').onclick=async()=>{await state.client.auth.signOut();location.href='acceso.html';};
    root.querySelector('#adminMenu').onclick=()=>root.querySelector('.admin-sidebar').classList.toggle('open');
  }

  function renderView(view){
    const root=document.querySelector('#adminView'); if(!root)return;
    document.querySelector('.admin-sidebar')?.classList.remove('open');
    if(view==='spaces') return renderSpaces(root);
    if(view==='owners') return renderOwners(root);
    if(view==='bookings') return renderBookings(root);
    if(view==='calendar') return renderCalendar(root);
    if(view==='catalog') return renderCatalog(root);
    if(view==='emails') return renderEmails(root);
    if(view==='surveys') return renderSurveys(root);
    renderDashboard(root);
  }


  async function renderCatalog(root){
    const r=await state.client.rpc('admin_get_service_catalog');if(r.error){root.innerHTML=header('SERVICIOS','Catálogo')+`<p class="message error">${esc(r.error.message)}</p>`;return;}
    root.innerHTML=header('SERVICIOS','Catálogo',`<button id="newCatalogService" class="btn btn-dark">+ Nuevo servicio</button>`)+`<div class="admin-card"><div class="admin-table-wrap"><table class="admin-table"><thead><tr><th>Servicio</th><th>Descripción</th><th>Estado</th><th></th></tr></thead><tbody>${(r.data||[]).map(x=>`<tr><td><strong>${esc(x.name)}</strong></td><td>${esc(x.description||'')}</td><td>${x.active?'Activo':'Inactivo'}</td><td><button class="btn btn-light" data-cat-edit="${x.id}">Editar</button></td></tr>`).join('')||'<tr><td colspan="4" class="muted">No hay servicios.</td></tr>'}</tbody></table></div></div>`;
    root.querySelector('#newCatalogService').onclick=()=>catalogModal(null);
    root.querySelectorAll('[data-cat-edit]').forEach(b=>b.onclick=()=>catalogModal((r.data||[]).find(x=>x.id===b.dataset.catEdit)));
  }
  function catalogModal(x){
    const m=modal(x?'Editar servicio':'Nuevo servicio',`<form class="admin-form-grid"><label>Nombre<input id="catName" value="${esc(x?.name||'')}" required></label><label>Activo<input id="catActive" type="checkbox" ${x?.active!==false?'checked':''}></label><label class="form-wide">Descripción<textarea id="catDesc">${esc(x?.description||'')}</textarea></label></form><div class="modal-actions"><button id="catSave" class="btn btn-dark">Guardar</button><button class="btn btn-light" data-close>Cerrar</button></div><p class="admin-message"></p>`);m.querySelector('[data-close]').onclick=()=>m.remove();m.querySelector('#catSave').onclick=async()=>{const q=x?await state.client.from('service_catalog').update({name:val(m,'#catName'),description:val(m,'#catDesc')||null,active:m.querySelector('#catActive').checked,updated_at:new Date().toISOString()}).eq('id',x.id):await state.client.from('service_catalog').insert({name:val(m,'#catName'),description:val(m,'#catDesc')||null,active:m.querySelector('#catActive').checked});if(q.error){toast(m,q.error.message,true);return;}m.remove();renderView('catalog');};
  }
  const communicationTypeLabels={
    customer_request_received:'Solicitud recibida por el cliente',
    customer_updated:'Reserva actualizada al cliente',
    customer_confirmed:'Reserva confirmada al cliente',
    customer_cancelled:'Cancelación comunicada al cliente',
    customer_not_processed:'Solicitud no procesada al cliente',
    customer_expired:'Solicitud caducada comunicada al cliente',
    owner_booking_final:'Notificación final al propietario',
    admin_booking_final:'Notificación final al administrador',
    owner_activate:'Propietario: espacio activado',
    owner_deactivate:'Propietario: espacio desactivado',
    admin_enable:'Administrador: espacio habilitado',
    admin_disable:'Administrador: espacio deshabilitado',
    space_enabled:'Espacio habilitado',
    space_disabled:'Espacio deshabilitado',
    survey_created:'Encuesta enviada',
    admin_update:'Cambio realizado por el administrador',
    admin_create:'Creación realizada por el administrador',
    owner_update:'Cambio realizado por el propietario',
    owner_email_changed:'Email del cliente modificado por el propietario',
    admin_owner_email_changed:'Email del cliente modificado por el administrador',
    owner_pending_reminder:'Recordatorio al propietario',
    owner_customer_delivery_failed:'Error de entrega al cliente',
    admin_request_created:'Nueva solicitud de reserva al administrador',
    request_created:'Nueva solicitud de reserva'
  };
  const emailStatusLabels={pending:'Pendiente',processing:'Procesando',sent:'Enviado',failed:'Error'};
  const emailCategoryLabels={espacios:'Espacios',reservas:'Reservas',encuestas:'Encuestas'};
  function communicationTypeLabel(value){return communicationTypeLabels[value]||String(value||'').replaceAll('_',' ');}
  function emailStatusLabel(value){return emailStatusLabels[value]||String(value||'').replaceAll('_',' ');}
  function emailCategoryLabel(value){return emailCategoryLabels[value]||String(value||'').replaceAll('_',' ');}

  async function renderEmails(root){
    root.innerHTML=header('EMAILS','Historial de comunicaciones',`<select id="emailCat"><option value="">Todos</option><option value="espacios">Espacios</option><option value="reservas">Reservas</option><option value="encuestas">Encuestas</option></select>`)+`<div class="admin-card"><div id="emailRows"><p class="muted">Cargando…</p></div></div>`;
    const paint=async()=>{const r=await state.client.rpc('admin_get_email_history',{p_category:root.querySelector('#emailCat').value||null});if(r.error){root.querySelector('#emailRows').innerHTML=`<p class="message error">${esc(r.error.message)}</p>`;return;}root.querySelector('#emailRows').innerHTML=`<div class="admin-table-wrap"><table class="admin-table"><thead><tr><th>Fecha</th><th>Categoría</th><th>Tipo</th><th>Destinatario</th><th>Estado</th><th>Intentos</th><th>Error</th></tr></thead><tbody>${(r.data||[]).map(x=>`<tr><td>${esc(new Date(x.created_at).toLocaleString('es-ES'))}</td><td>${esc(emailCategoryLabel(x.category))}</td><td>${esc(communicationTypeLabel(x.communication_type))}</td><td>${esc(x.recipient_email)}</td><td>${esc(emailStatusLabel(x.status))}</td><td>${x.attempts}</td><td>${esc(x.last_error||'')}</td></tr>`).join('')||'<tr><td colspan="7" class="muted">Sin comunicaciones.</td></tr>'}</tbody></table></div>`;};root.querySelector('#emailCat').onchange=paint;await paint();
  }
  async function renderSurveys(root){const r=await state.client.rpc('admin_get_surveys');root.innerHTML=header('ENCUESTAS','Respuestas')+`<div class="admin-card"><div class="admin-table-wrap"><table class="admin-table"><thead><tr><th>Espacio</th><th>Cliente</th><th>General</th><th>Instalaciones</th><th>Limpieza</th><th>Equipamiento</th><th>Mantenimiento</th><th>Incidencia</th><th>Comentarios</th></tr></thead><tbody>${r.error?`<tr><td colspan="9" class="message error">${esc(r.error.message)}</td></tr>`:(r.data||[]).map(x=>`<tr><td>${esc(x.space_name)}</td><td>${esc(x.customer_name)}</td><td>${x.overall??'—'}</td><td>${x.facilities??'—'}</td><td>${x.cleaning??'—'}</td><td>${x.equipment??'—'}</td><td>${x.maintenance??'—'}</td><td>${x.breakdown?'Sí':'No'}</td><td>${esc(x.comments||'')}</td></tr>`).join('')||'<tr><td colspan="9" class="muted">Sin encuestas.</td></tr>'}</tbody></table></div></div>`;}
  function header(kicker,title,action=''){
    return `<div class="admin-view-head"><div><p class="eyebrow">${kicker}</p><h1>${title}</h1></div>${action}</div>`;
  }

  function renderDashboard(root){
    const active=state.spaces.filter(s=>s.active).length;
    const pending=state.bookings.filter(b=>b.booking_status==='pending').length;
    const confirmed=state.bookings.filter(b=>b.booking_status==='confirmed').length;
    const owners=state.owners.filter(o=>o.active).length;
    const upcoming=state.bookings.filter(b=>b.booking_status==='confirmed' && b.end_date>=new Date().toISOString().slice(0,10)).sort((a,b)=>String(a.start_date).localeCompare(String(b.start_date))).slice(0,5);
    root.innerHTML=header('ADMINISTRACIÓN','Resumen')+`<div class="admin-kpis">
      <article><span>Espacios activos</span><strong>${active}</strong></article>
      <article><span>Propietarios activos</span><strong>${owners}</strong></article>
      <article><span>Solicitudes pendientes</span><strong>${pending}</strong></article>
      <article><span>Reservas confirmadas</span><strong>${confirmed}</strong></article>
    </div>
    <div class="admin-dashboard-grid">
      <section class="admin-card"><div class="admin-card-head"><div><p class="eyebrow">ATENCIÓN</p><h2>Solicitudes pendientes</h2></div><button class="btn btn-light" data-go="bookings">Ver reservas</button></div>
        ${pending?`<div class="admin-list">${state.bookings.filter(b=>b.booking_status==='pending').slice(0,6).map(b=>`<div class="admin-list-row"><div><strong>${esc(b.space_name)}</strong><span>${esc(b.customer_name)} · ${date(b.start_date)} → ${date(b.end_date)}</span></div><span class="status status-pending">Pendiente</span></div>`).join('')}</div>`:'<p class="muted">No hay solicitudes pendientes.</p>'}
      </section>
      <section class="admin-card"><div class="admin-card-head"><div><p class="eyebrow">PRÓXIMOS EVENTOS</p><h2>Reservas confirmadas</h2></div></div>
        ${upcoming.length?`<div class="admin-list">${upcoming.map(b=>`<div class="admin-list-row"><div><strong>${esc(b.space_name)}</strong><span>${esc(b.customer_name)} · ${date(b.start_date)} → ${date(b.end_date)}</span></div><span class="status status-confirmed">Confirmada</span></div>`).join('')}</div>`:'<p class="muted">No hay próximas reservas.</p>'}
      </section>
    </div>`;
    root.querySelectorAll('[data-go]').forEach(b=>b.onclick=()=>{const target=root.querySelector(`[data-view=\"${b.dataset.go}\"]`);if(target){target.click();}else{renderView(b.dataset.go);}});
  }

  function renderSpaces(root){
    root.innerHTML=header('ESPACIOS','Gestionar espacios',`<button id="newSpace" class="btn btn-dark">+ Añadir espacio</button>`)+`<div class="admin-card"><div class="admin-table-wrap"><table class="admin-table"><thead><tr><th>Espacio</th><th>Propietario</th><th>Estado</th><th>Periodo</th><th>Precios</th><th></th></tr></thead><tbody>${state.spaces.length?state.spaces.map(s=>spaceRow(s)).join(''):`<tr><td colspan="6" class="muted">No hay espacios.</td></tr>`}</tbody></table></div></div><p class="admin-message" aria-live="polite"></p>`;
    root.querySelector('#newSpace').onclick=()=>spaceModal(null);
    root.querySelectorAll('[data-space-edit]').forEach(b=>b.onclick=()=>spaceModal(state.spaces.find(s=>s.id===b.dataset.spaceEdit)));
    root.querySelectorAll('[data-space-toggle]').forEach(b=>b.onclick=()=>toggleSpace(b.dataset.spaceToggle,b.dataset.active==='true'));
    root.querySelectorAll('[data-space-tools]').forEach(b=>b.onclick=()=>spaceTools(state.spaces.find(s=>s.id===b.dataset.spaceTools)));
  }

  function spaceRow(s){
    const owner=state.owners.find(o=>o.id===s.owner_id);
    const period=s.active_until?`${date(s.active_from)} → ${date(s.active_until)}`:`Desde ${date(s.active_from)}`;
    return `<tr><td><strong>${esc(s.name)}</strong><span class="table-sub">${esc(s.city||'')} · ${esc(s.province||'')}</span></td><td>${owner?esc(`${owner.first_name||''} ${owner.last_name||''}`.trim()||owner.email):'—'}</td><td><span class="status ${s.active?'status-confirmed':'status-off'}">${s.active?'Activo':'Inactivo'}</span></td><td>${period}</td><td>${money(s.weekday_price)} / ${money(s.friday_price)}</td><td class="table-actions"><button class="btn btn-light" data-space-edit="${s.id}">Editar</button><button class="btn btn-light" data-space-tools="${s.id}">Gestionar</button><button class="btn btn-light" data-space-toggle="${s.id}" data-active="${s.active}">${s.active?'Desactivar':'Activar'}</button></td></tr>`;
  }

  async function spaceModal(s){
    const c=state.client, edit=!!s;
    const activeOwners=state.owners.filter(o=>o.active);
    const ownerOptions=activeOwners.map(o=>`<option value="${o.id}" ${s?.owner_id===o.id?'selected':''}>${esc(`${o.first_name||''} ${o.last_name||''}`.trim()||o.email)}</option>`).join('');
    let daily={};
    if(edit){const r=await c.rpc('admin_get_space_day_prices',{p_space_id:s.id});if(!r.error)(r.data||[]).forEach(x=>daily[x.day_of_week]=x.price);}
    const d=(n)=>daily[n]??((n>=1&&n<=4)?(s?.weekday_price??0):n===5?(s?.friday_price??0):n===6?(s?.saturday_price??0):(s?.sunday_price??0));
    const m=modal(edit?'Editar espacio':'Nuevo espacio',`<form id="spaceForm" class="admin-form-grid">
      <label>Propietario<select id="owner" required>${ownerOptions||'<option value="">No hay propietarios activos</option>'}</select></label>
      <label>Nombre<input id="name" required value="${esc(s?.name||'')}"></label>
      <label>Localidad<input id="city" value="${esc(s?.city||'')}"></label>
      <label>Provincia<input id="province" value="${esc(s?.province||'')}"></label>
      <div class="form-wide"><p class="eyebrow">PRECIOS POR DÍA</p><div class="admin-form-grid"><label>Lunes (€)<input id="monday" type="number" min="0" step="0.01" value="${d(1)}"></label><label>Martes (€)<input id="tuesday" type="number" min="0" step="0.01" value="${d(2)}"></label><label>Miércoles (€)<input id="wednesday" type="number" min="0" step="0.01" value="${d(3)}"></label><label>Jueves (€)<input id="thursday" type="number" min="0" step="0.01" value="${d(4)}"></label><label>Viernes (€)<input id="friday" type="number" min="0" step="0.01" value="${d(5)}"></label><label>Sábado (€)<input id="saturday" type="number" min="0" step="0.01" value="${d(6)}"></label><label>Domingo (€)<input id="sunday" type="number" min="0" step="0.01" value="${d(7)}"></label><label><strong>Festivo (€)</strong><input id="holiday" type="number" min="0" step="0.01" value="${s?.holiday_price??0}"></label></div></div>
      <label>Hora de apertura<input id="opening" type="time" value="${esc(s?.opening_time||'11:00')}" ></label>
      <label>Hora de cierre<input id="closing" type="time" value="${esc(s?.closing_time||'23:00')}" ></label>
      <label>Fianza (€)<input id="deposit" type="number" min="0" step="0.01" value="${s?.deposit??''}"></label>
      <label>Inicio de actividad<input id="from" type="date" value="${esc(s?.active_from||'')}" ></label>
      <label>Fin de actividad<input id="until" type="date" value="${esc(s?.active_until||'')}" ></label>
      <label>Latitud<input id="lat" type="number" step="0.000001" value="${s?.latitude??''}"></label>
      <label>Longitud<input id="lng" type="number" step="0.000001" value="${s?.longitude??''}"></label>
      <label class="form-wide">Descripción<textarea id="description">${esc(s?.description||'')}</textarea></label>
      <label class="form-wide">Condiciones de cancelación<textarea id="cancel">${esc(s?.cancellation_policy||'')}</textarea></label>
      <label class="form-wide">Información de pago<textarea id="payment">${esc(s?.payment_information||'')}</textarea></label>
      <label class="check-row"><input id="cleaningAvailable" type="checkbox" ${s?.cleaning_available?'checked':''}> Ofrecer limpieza</label>
      <label>Precio limpieza (€)<input id="cleaningPrice" type="number" min="0" step="0.01" value="${s?.cleaning_price??''}"></label>
      <label class="check-row"><input id="active" type="checkbox" ${s?.active!==false?'checked':''}> Espacio activo</label>
    </form><div class="modal-actions"><button id="saveSpace" class="btn btn-dark">${edit?'Guardar cambios':'Crear espacio'}</button><button class="btn btn-light" data-close>Cerrar</button></div><p class="admin-message" aria-live="polite"></p>`);
    m.querySelector('[data-close]').onclick=()=>m.remove();
    m.querySelector('#saveSpace').onclick=async()=>{
      const msg=m.querySelector('.admin-message'); msg.textContent='Guardando…';
      const args={p_owner_id:val(m,'#owner'),p_name:val(m,'#name'),p_city:val(m,'#city')||null,p_province:val(m,'#province')||null,p_description:val(m,'#description')||null,p_weekday_price:num(m,'#monday')??0,p_friday_price:num(m,'#friday')??0,p_saturday_price:num(m,'#saturday')??0,p_sunday_price:num(m,'#sunday')??0,p_opening_time:val(m,'#opening')||'11:00',p_closing_time:val(m,'#closing')||'23:00',p_cancellation_policy:val(m,'#cancel')||null,p_cleaning_available:m.querySelector('#cleaningAvailable').checked,p_cleaning_price:num(m,'#cleaningPrice')??0,p_payment_information:val(m,'#payment')||null,p_active:m.querySelector('#active').checked,p_latitude:num(m,'#lat'),p_longitude:num(m,'#lng'),p_deposit:num(m,'#deposit')??0,p_active_from:val(m,'#from')||null,p_active_until:val(m,'#until')||null};
      const r=edit?await c.rpc('admin_update_space',{p_space_id:s.id,...args}):await c.rpc('admin_create_space',args);
      if(r.error){msg.textContent=r.error.message;msg.classList.add('error');return;}
      const spaceId=edit?s.id:r.data;
      const dp=await c.rpc('admin_save_space_day_prices',{p_space_id:spaceId,p_monday:num(m,'#monday')??0,p_tuesday:num(m,'#tuesday')??0,p_wednesday:num(m,'#wednesday')??0,p_thursday:num(m,'#thursday')??0,p_friday:num(m,'#friday')??0,p_saturday:num(m,'#saturday')??0,p_sunday:num(m,'#sunday')??0});
      if(dp.error){msg.textContent=dp.error.message;msg.classList.add('error');return;}
      const hp=await c.rpc('admin_save_space_holiday_price',{p_space_id:spaceId,p_holiday_price:num(m,'#holiday')??0});
      if(hp.error){msg.textContent=hp.error.message;msg.classList.add('error');return;}
      m.remove();await refresh();renderView('spaces');
    };
  }

  function modal(title,body){
    const m=document.createElement('div');m.className='modal-backdrop';m.innerHTML=`<div class="modal-card admin-modal"><div class="modal-title"><div><p class="eyebrow">MiEspacioParaCelebrar</p><h2>${title}</h2></div><button class="modal-x" aria-label="Cerrar">×</button></div>${body}</div>`;document.body.appendChild(m);m.querySelector('.modal-x').onclick=()=>m.remove();m.addEventListener('click',e=>{if(e.target===m)m.remove();});return m;
  }

  async function toggleSpace(id,active){
    const r=await state.client.rpc('admin_set_space_active',{p_space_id:id,p_active:!active}); if(r.error){alert(r.error.message);return;} await refresh();renderView('spaces');
  }

  async function spaceTools(s){
    const m=modal(`Gestionar · ${esc(s.name)}`,`<div class="tool-tabs"><button class="active" data-tool="photos">Fotos</button><button data-tool="features">Características</button><button data-tool="services">Servicios</button><button data-tool="blocks">Bloqueos</button></div><div id="toolContent"></div>`);
    m.querySelectorAll('[data-tool]').forEach(b=>b.onclick=()=>{m.querySelectorAll('[data-tool]').forEach(x=>x.classList.remove('active'));b.classList.add('active');renderTool(m,s,b.dataset.tool);});
    renderTool(m,s,'photos');
  }

  async function renderTool(m,s,tool){
    const box=m.querySelector('#toolContent');box.innerHTML='<p class="muted">Cargando…</p>';
    if(tool==='photos') return photosTool(m,s,box);
    if(tool==='features') return featuresTool(m,s,box);
    if(tool==='services') return servicesTool(m,s,box);
    return blocksTool(m,s,box);
  }

  async function photosTool(m,s,box){
    const r=await state.client.rpc('admin_get_space_images',{p_space_id:s.id}); if(r.error){box.innerHTML=`<p class="message error">${esc(r.error.message)}</p>`;return;}
    box.innerHTML=`<div class="upload-box"><input id="photoFiles" type="file" accept="image/jpeg,image/png,image/webp" multiple><p>JPG, PNG o WebP. Puedes seleccionar varias imágenes.</p><button id="uploadPhotos" class="btn btn-dark">Subir fotografías</button></div><div class="photo-grid">${(r.data||[]).map((x,i)=>`<article class="photo-admin"><img src="${esc(x.image_url)}" alt="${esc(x.alt_text||s.name)}"><div><strong>${x.is_main?'Principal':'Fotografía '+(i+1)}</strong><p>${esc(x.alt_text||'Sin texto alternativo')}</p><div class="photo-actions">${!x.is_main?`<button class="btn btn-light" data-main="${x.id}">Hacer principal</button>`:''}<button class="btn btn-light" data-photo-edit="${x.id}">Editar</button><button class="btn btn-light" data-photo-delete="${x.id}" data-url="${esc(x.image_url)}">Eliminar</button></div></div></article>`).join('')||'<p class="muted">Todavía no hay fotografías.</p>'}</div><p class="admin-message"></p>`;
    box.querySelector('#uploadPhotos').onclick=async()=>{
      const files=[...box.querySelector('#photoFiles').files];if(!files.length){toast(box,'Selecciona al menos una imagen.',true);return;} const msg=box.querySelector('.admin-message');msg.textContent='Subiendo…';
      for(const file of files){if(file.size>8*1024*1024){msg.textContent=`${file.name}: supera 8 MB.`;msg.classList.add('error');continue;} const ext=(file.name.split('.').pop()||'jpg').toLowerCase().replace(/[^a-z0-9]/g,'');const path=`${s.id}/${crypto.randomUUID()}.${ext}`;const up=await state.client.storage.from('space-images').upload(path,file,{cacheControl:'31536000',upsert:false,contentType:file.type});if(up.error){msg.textContent=up.error.message;msg.classList.add('error');continue;}const pub=state.client.storage.from('space-images').getPublicUrl(path).data.publicUrl;const row=await state.client.rpc('admin_add_space_image',{p_space_id:s.id,p_image_url:pub,p_alt_text:s.name,p_is_main:false,p_sort_order:999});if(row.error){await state.client.storage.from('space-images').remove([path]);msg.textContent=row.error.message;msg.classList.add('error');break;}}
      msg.textContent='Fotografías procesadas.';await renderTool(m,s,'photos');
    };
    box.querySelectorAll('[data-main]').forEach(b=>b.onclick=async()=>{const img=(r.data||[]).find(x=>x.id===b.dataset.main);if(!img)return;const u=await state.client.rpc('admin_update_space_image',{p_image_id:img.id,p_image_url:img.image_url,p_alt_text:img.alt_text||s.name,p_is_main:true,p_sort_order:img.sort_order||0});if(u.error){alert(u.error.message);return;}await renderTool(m,s,'photos');});
    box.querySelectorAll('[data-photo-edit]').forEach(b=>b.onclick=()=>editPhoto(m,s,(r.data||[]).find(x=>x.id===b.dataset.photoEdit)));
    box.querySelectorAll('[data-photo-delete]').forEach(b=>b.onclick=async()=>{if(!confirm('¿Eliminar esta fotografía?'))return;const del=await state.client.rpc('admin_delete_space_image',{p_image_id:b.dataset.photoDelete});if(del.error){alert(del.error.message);return;}await removeStorageUrl(b.dataset.url);await renderTool(m,s,'photos');});
  }

  async function removeStorageUrl(url){try{const marker='/storage/v1/object/public/space-images/';const i=url.indexOf(marker);if(i<0)return;const path=decodeURIComponent(url.slice(i+marker.length));await state.client.storage.from('space-images').remove([path]);}catch(e){console.warn(e);}}

  function editPhoto(m,s,img){
    const box=m.querySelector('#toolContent');box.innerHTML=`<div class="photo-edit-form"><img src="${esc(img.image_url)}" alt=""><label>Texto alternativo<input id="photoAlt" value="${esc(img.alt_text||'')}"></label><label>Orden<input id="photoOrder" type="number" value="${img.sort_order??0}"></label><label class="check-row"><input id="photoMain" type="checkbox" ${img.is_main?'checked':''}> Fotografía principal</label><button id="savePhoto" class="btn btn-dark">Guardar</button><button id="backPhotos" class="btn btn-light">Volver</button><p class="admin-message"></p></div>`;
    box.querySelector('#savePhoto').onclick=async()=>{const r=await state.client.rpc('admin_update_space_image',{p_image_id:img.id,p_image_url:img.image_url,p_alt_text:val(box,'#photoAlt')||s.name,p_is_main:box.querySelector('#photoMain').checked,p_sort_order:Number(val(box,'#photoOrder')||0)});if(r.error){toast(box,r.error.message,true);return;}await renderTool(m,s,'photos');};box.querySelector('#backPhotos').onclick=()=>renderTool(m,s,'photos');
  }


  async function servicesTool(m,s,box){
    const r=await state.client.rpc('admin_get_space_services_custom',{p_space_id:s.id});
    if(r.error){box.innerHTML=`<p class="message error">${esc(r.error.message)}</p>`;return;}
    const rows=r.data||[];

    const dayLabels=[[1,'L'],[2,'M'],[3,'X'],[4,'J'],[5,'V'],[6,'S'],[7,'D']];
    const daysText=a=>a&&a.length?dayLabels.filter(([n])=>a.includes(n)).map(([,l])=>l).join(' · '):'Todos los días';
    const grouped={};
    const singles=[];
    rows.forEach(x=>{
      if(x.selection_group) (grouped[x.selection_group] ||= []).push(x);
      else singles.push(x);
    });

    const serviceCard=x=>`<article class="service-config-card" style="border:1px solid #e1e1e1;border-radius:18px;padding:18px 20px;margin-bottom:12px;background:#fff;">
      <div style="display:flex;justify-content:space-between;gap:20px;align-items:flex-start;flex-wrap:wrap;">
        <div style="min-width:220px;flex:1;">
          <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">
            <strong style="font-size:18px;">${esc(x.name)}</strong>
            <span class="status ${x.active?'status-confirmed':'status-off'}">${x.active?'Activo':'Inactivo'}</span>
          </div>
          ${x.description?`<p style="margin:7px 0;color:#666;">${esc(x.description)}</p>`:''}
          <div style="display:flex;gap:14px;flex-wrap:wrap;color:#555;font-size:14px;">
            <span><strong>${x.included?'Incluido':money(x.price)}</strong>${!x.included&&x.price_mode==='per_day'?' / día':''}</span>
            <span>${daysText(x.allowed_days)}</span>
            ${x.replaces_rental?'<span>Alternativa al precio del alquiler</span>':''}
          </div>
        </div>
        <div style="display:flex;gap:8px;flex-wrap:wrap;">
          <button class="btn btn-light" data-service-edit="${x.id}">Editar</button>
          <button class="btn btn-light" data-service-toggle="${x.id}">${x.active?'Desactivar':'Activar'}</button>
          <button class="btn btn-light" data-service-delete="${x.id}">Eliminar</button>
        </div>
      </div>
    </article>`;

    const groupCard=(name,items)=>`article class="service-group-card" style="border:1px solid #d8d8d8;border-radius:20px;padding:20px;margin-bottom:16px;background:#fafafa;">
      <div style="display:flex;justify-content:space-between;gap:16px;align-items:flex-start;flex-wrap:wrap;margin-bottom:12px;">
        <div>
          <p class="eyebrow" style="margin:0 0 5px;">GRUPO DE OPCIONES</p>
          <h3 style="margin:0;font-size:20px;">${esc(name)}</h3>
          <p style="margin:6px 0 0;color:#666;">El cliente puede elegir como máximo una opción de este grupo.</p>
        </div>
        <button class="btn btn-dark" data-group-add="${esc(name)}">+ Añadir opción</button>
      </div>
      ${items.map(serviceCard).join('')}
    </article>`;

    box.innerHTML=`<div class="services-redesign" style="max-width:1050px;">
      <div style="display:flex;justify-content:space-between;gap:20px;align-items:flex-start;flex-wrap:wrap;margin-bottom:18px;">
        <div>
          <p class="eyebrow">SERVICIOS DEL ESPACIO</p>
          <h2 style="margin:0 0 6px;">Servicios y opciones</h2>
          <p class="micro" style="max-width:700px;margin:0;">Añade extras, servicios incluidos o grupos de opciones. Los precios y condiciones se configuran directamente para este espacio.</p>
        </div>
        <button id="addServiceNew" class="btn btn-dark">＋ Añadir servicio</button>
      </div>

      <div class="admin-card" style="padding:16px 18px;margin-bottom:20px;">
        <strong>¿Cómo funcionan los grupos?</strong>
        <p class="micro" style="margin:6px 0 0;">Si varias opciones pertenecen al mismo grupo, el cliente solo puede escoger una. Por ejemplo: <strong>1 freidora · 30 €</strong> o <strong>2 freidoras · 50 €</strong>. Si elige dos freidoras, se cobran 50 €, no 30 € + 50 €.</p>
      </div>

      ${Object.entries(grouped).map(([g,items])=>groupCard(g,items)).join('')}
      ${singles.length?`<div><p class="eyebrow">SERVICIOS INDEPENDIENTES</p>${singles.map(serviceCard).join('')}</div>`:''}
      ${!rows.length?`<div class="admin-card" style="padding:28px;text-align:center;"><h3>Aún no hay servicios configurados</h3><p class="muted">Añade el primero con el botón «Añadir servicio».</p></div>`:''}
      <p class="admin-message"></p>
    </div>`;

    const openEditor=(x=null,groupName='')=>{
      const days=x?.allowed_days||[];
      const m=modal(x?'Editar servicio':'Añadir servicio',`<form id="serviceForm" class="admin-form-grid">
        <label class="form-wide">Nombre del servicio u opción<input id="serviceName" required value="${esc(x?.name||'')}" placeholder="Ej.: Uso de cocina, 1 freidora, 2 freidoras…"></label>
        <label class="form-wide">Descripción<textarea id="serviceDescription" placeholder="Explica brevemente qué incluye.">${esc(x?.description||'')}</textarea></label>

        <div class="form-wide" style="padding:16px;border:1px solid #e2e2e2;border-radius:16px;">
          <strong>Tipo de servicio</strong>
          <div style="display:flex;gap:18px;flex-wrap:wrap;margin-top:10px;">
            <label class="check-row"><input type="radio" name="serviceType" value="single" ${!x?.selection_group?'checked':''}> Servicio independiente</label>
            <label class="check-row"><input type="radio" name="serviceType" value="group" ${x?.selection_group?'checked':''}> Opción dentro de un grupo</label>
          </div>
          <div id="groupFields" style="margin-top:12px;${x?.selection_group?'':'display:none;'}">
            <label>Nombre del grupo<input id="groupName" value="${esc(x?.selection_group||groupName)}" placeholder="Ej.: Freidoras"></label>
            <label class="check-row" style="margin-top:10px;"><input id="groupRequired" type="checkbox" ${x?.selection_required?'checked':''}> El cliente debe elegir una opción de este grupo</label>
          </div>
        </div>

        <label>Precio (€)<input id="servicePrice" type="number" min="0" step="0.01" value="${x?.included?'':(x?.price??'')}" placeholder="0,00"></label>
        <label>Forma de cobro<select id="priceMode">
          <option value="fixed" ${x?.price_mode!=='per_day'?'selected':''}>Una vez por reserva</option>
          <option value="per_day" ${x?.price_mode==='per_day'?'selected':''}>Por día de reserva</option>
        </select></label>

        <div class="form-wide" style="padding:16px;border:1px solid #e2e2e2;border-radius:16px;">
          <strong>Disponibilidad</strong>
          <p class="micro" style="margin:5px 0 10px;">Si no marcas ningún día, estará disponible todos los días.</p>
          <div style="display:flex;gap:12px;flex-wrap:wrap;">${dayLabels.map(([n,l])=>`<label class="check-row"><input class="service-day-new" type="checkbox" value="${n}" ${days.includes(n)?'checked':''}> ${l}</label>`).join('')}</div>
        </div>

        <label class="form-wide check-row"><input id="serviceIncluded" type="checkbox" ${x?.included?'checked':''}> Está incluido en el alquiler y no tiene coste adicional</label>

        <details class="form-wide" style="padding:12px 0;">
          <summary style="cursor:pointer;font-weight:600;">Opciones avanzadas</summary>
          <div style="padding-top:14px;">
            <label class="check-row"><input id="serviceReplace" type="checkbox" ${x?.replaces_rental?'checked':''}> Esta opción sustituye el precio diario del alquiler</label>
          </div>
        </details>
      </form>
      <div class="modal-actions"><button id="saveServiceNew" class="btn btn-dark">Guardar servicio</button><button class="btn btn-light" data-close>Cerrar</button></div><p class="admin-message"></p>`);

      m.querySelector('[data-close]').onclick=()=>m.remove();

      const sync=()=>{
        const group=m.querySelector('input[name="serviceType"]:checked')?.value==='group';
        m.querySelector('#groupFields').style.display=group?'block':'none';
        if(!group)m.querySelector('#groupName').value='';
      };
      m.querySelectorAll('input[name="serviceType"]').forEach(r=>r.onchange=sync);
      m.querySelector('#serviceIncluded').onchange=()=>{
        const inc=m.querySelector('#serviceIncluded').checked;
        m.querySelector('#servicePrice').disabled=inc;
        if(inc)m.querySelector('#servicePrice').value='';
      };
      m.querySelector('#serviceIncluded').dispatchEvent(new Event('change'));

      m.querySelector('#saveServiceNew').onclick=async()=>{
        const name=val(m,'#serviceName');
        const group=m.querySelector('input[name="serviceType"]:checked')?.value==='group';
        const groupNameValue=group?val(m,'#groupName'):null;
        const included=m.querySelector('#serviceIncluded').checked;
        const price=included?0:Number(val(m,'#servicePrice')||0);
        const allowed=[...m.querySelectorAll('.service-day-new:checked')].map(x=>Number(x.value));
        if(!name){toast(m,'Indica el nombre del servicio.',true);return;}
        if(group&&!groupNameValue){toast(m,'Indica el nombre del grupo.',true);return;}
        if(!included&&!Number.isFinite(price)){toast(m,'El precio no es válido.',true);return;}
        const q=await state.client.rpc('admin_save_space_service_custom',{
          p_space_id:s.id,
          p_space_service_id:x?.id||null,
          p_name:name,
          p_description:val(m,'#serviceDescription')||null,
          p_included:included,
          p_price:price,
          p_active:x?.active!==false,
          p_selection_group:group?groupNameValue:null,
          p_selection_required:group&&m.querySelector('#groupRequired').checked,
          p_replaces_rental:m.querySelector('#serviceReplace').checked,
          p_price_mode:val(m,'#priceMode'),
          p_allowed_days:allowed.length?allowed:null
        });
        if(q.error){toast(m,q.error.message,true);return;}
        m.remove();
        const toolModal=document.querySelector('.admin-modal');
        if(toolModal) await renderTool(toolModal,s,'services');
      };
    };

    // Helper: renderTool needs the original space-management modal. Re-open it if editor closes.
    box.querySelector('#addServiceNew').onclick=()=>openEditor();
    box.querySelectorAll('[data-group-add]').forEach(b=>b.onclick=()=>openEditor(null,b.dataset.groupAdd));
    box.querySelectorAll('[data-service-edit]').forEach(b=>b.onclick=()=>{
      const x=rows.find(y=>y.id===b.dataset.serviceEdit); if(x) openEditor(x);
    });
    box.querySelectorAll('[data-service-toggle]').forEach(b=>b.onclick=async()=>{
      const q=await state.client.rpc('admin_set_space_service_active',{p_space_service_id:b.dataset.serviceToggle,p_active:b.textContent.trim()==='Activar'});
      if(q.error){alert(q.error.message);return;}
      await renderTool(document.querySelector('.admin-modal'),s,'services');
    });
    box.querySelectorAll('[data-service-delete]').forEach(b=>b.onclick=async()=>{
      if(!confirm('¿Eliminar este servicio u opción?'))return;
      const q=await state.client.rpc('admin_delete_space_service_custom',{p_space_service_id:b.dataset.serviceDelete});
      if(q.error){alert(q.error.message);return;}
      await renderTool(document.querySelector('.admin-modal'),s,'services');
    });
  }
  async function featuresTool(m,s,box){
    const r=await state.client.rpc('admin_get_space_features',{p_space_id:s.id});if(r.error){box.innerHTML=`<p class="message error">${esc(r.error.message)}</p>`;return;}
    box.innerHTML=`<div class="feature-add"><input id="newFeature" placeholder="Nueva característica"><button id="addFeature" class="btn btn-dark">Añadir</button></div><div class="feature-admin-list">${(r.data||[]).map((x,i)=>`<div><span>${esc(x.feature)}</span><span><button class="btn btn-light" data-feature-edit="${x.id}">Editar</button><button class="btn btn-light" data-feature-delete="${x.id}">Eliminar</button></span></div>`).join('')||'<p class="muted">No hay características.</p>'}</div><p class="admin-message"></p>`;
    box.querySelector('#addFeature').onclick=async()=>{const feature=val(box,'#newFeature');if(!feature)return;const q=await state.client.rpc('admin_add_space_feature',{p_space_id:s.id,p_feature:feature,p_sort_order:(r.data||[]).length});if(q.error){toast(box,q.error.message,true);return;}await renderTool(m,s,'features');};
    box.querySelectorAll('[data-feature-delete]').forEach(b=>b.onclick=async()=>{if(!confirm('¿Eliminar esta característica?'))return;const q=await state.client.rpc('admin_delete_space_feature',{p_feature_id:b.dataset.featureDelete});if(q.error){alert(q.error.message);return;}await renderTool(m,s,'features');});
    box.querySelectorAll('[data-feature-edit]').forEach(b=>b.onclick=()=>{const x=(r.data||[]).find(y=>y.id===b.dataset.featureEdit);const n=prompt('Característica',x.feature);if(n===null)return;state.client.rpc('admin_update_space_feature',{p_feature_id:x.id,p_feature:n.trim(),p_sort_order:x.sort_order}).then(q=>q.error?alert(q.error.message):renderTool(m,s,'features'));});
  }

  async function blocksTool(m,s,box){
    const r=await state.client.rpc('admin_get_blocked_dates',{p_space_id:s.id});if(r.error){box.innerHTML=`<p class="message error">${esc(r.error.message)}</p>`;return;}
    box.innerHTML=`<form class="block-form"><label>Desde<input id="blockFrom" type="date" required></label><label>Hasta<input id="blockUntil" type="date" required></label><label>Motivo<input id="blockReason" placeholder="Uso particular, mantenimiento…"></label><button id="addBlock" class="btn btn-dark">Bloquear fechas</button></form><div class="block-list">${(r.data||[]).map(x=>`<div><div><strong>${date(x.start_date)} → ${date(x.end_date)}</strong><span>${esc(x.reason||'Sin motivo')}</span></div><button class="btn btn-light" data-block-delete="${x.id}">Eliminar</button></div>`).join('')||'<p class="muted">No hay fechas bloqueadas.</p>'}</div><p class="admin-message"></p>`;
    box.querySelector('#addBlock').onclick=async e=>{e.preventDefault();const from=val(box,'#blockFrom'),until=val(box,'#blockUntil');if(!from||!until||until<from){toast(box,'El rango de fechas no es válido.',true);return;}const q=await state.client.rpc('admin_create_blocked_date',{p_space_id:s.id,p_start_date:from,p_end_date:until,p_reason:val(box,'#blockReason')||null});if(q.error){toast(box,q.error.message,true);return;}await renderTool(m,s,'blocks');};
    box.querySelectorAll('[data-block-delete]').forEach(b=>b.onclick=async()=>{const q=await state.client.rpc('admin_delete_blocked_date',{p_blocked_id:b.dataset.blockDelete});if(q.error){alert(q.error.message);return;}await renderTool(m,s,'blocks');});
  }

  function renderOwners(root){
    root.innerHTML=header('PROPIETARIOS','Propietarios',`<button id="newOwner" class="btn btn-dark">+ Añadir propietario</button>`)+`<div class="admin-card"><div class="admin-table-wrap"><table class="admin-table"><thead><tr><th>Propietario</th><th>Email</th><th>Teléfono</th><th>Espacios</th><th>Estado</th><th></th></tr></thead><tbody>${state.owners.length?state.owners.map(o=>`<tr><td><strong>${esc(`${o.first_name||''} ${o.last_name||''}`.trim()||'Sin nombre')}</strong></td><td>${esc(o.email||'')}</td><td>${esc(o.phone||'—')}</td><td>${state.spaces.filter(s=>s.owner_id===o.id).length}</td><td><span class="status ${o.active?'status-confirmed':'status-off'}">${o.active?'Activo':'Inactivo'}</span></td><td><button class="btn btn-light" data-owner-edit="${o.profile_id}">Editar</button> <button class="btn btn-light owner-resend-btn" data-owner-resend="${o.id}" style="display:inline-flex;align-items:center;justify-content:center;white-space:nowrap;padding:10px 14px;border:1px solid #d9d9d9;border-radius:999px;background:#fff;color:#222;font:inherit;font-weight:600;line-height:1.2;cursor:pointer;">✉️ Enviar recuperación de contraseña</button> <button class="btn btn-light" data-owner-toggle="${o.id}" data-active="${o.active}">${o.active?'Desactivar':'Activar'}</button></td></tr>`).join(''):'<tr><td colspan="6" class="muted">No hay propietarios.</td></tr>'}</tbody></table></div></div><p class="admin-message"></p>`;
    root.querySelector('#newOwner').onclick=()=>ownerModal(null);
    root.querySelectorAll('[data-owner-edit]').forEach(b=>b.onclick=()=>ownerModal(state.owners.find(o=>o.profile_id===b.dataset.ownerEdit)));
    root.querySelectorAll('[data-owner-resend]').forEach(b=>b.onclick=()=>resendOwnerInvitation(b.dataset.ownerResend));
    root.querySelectorAll('[data-owner-toggle]').forEach(b=>b.onclick=async()=>{const q=await state.client.rpc('admin_set_owner_active',{p_owner_id:b.dataset.ownerToggle,p_active:b.dataset.active!=='true'});if(q.error){alert(q.error.message);return;}await refresh();renderView('owners');});
  }

  async function resendOwnerInvitation(ownerId){
    const owner=state.owners.find(o=>o.id===ownerId);
    if(!owner)return;

    const name=`${owner.first_name||''} ${owner.last_name||''}`.trim()||owner.email||'este propietario';
    const email=owner.email||'';

    if(!confirm(`¿Enviar un nuevo correo de recuperación de contraseña a ${name}${email?` (${email})`:''}?`))return;

    const {data:{session},error:sessionError}=await state.client.auth.getSession();

    if(sessionError||!session){
      alert('La sesión de administración no es válida. Vuelve a iniciar sesión.');
      return;
    }

    try{
      const response=await fetch('https://hvuseljtqdgekotrsiwd.supabase.co/functions/v1/resend-owner-invitation',{
        method:'POST',
        headers:{
          'Content-Type':'application/json',
          Authorization:`Bearer ${session.access_token}`
        },
        body:JSON.stringify({owner_id:ownerId})
      });

      let data={};
      try{data=await response.json();}catch{}

      if(!response.ok){
        throw new Error(data.error||'No se ha podido reenviar la invitación.');
      }

      alert(`Se ha enviado un nuevo correo de recuperación de contraseña a ${email}.`);
    }catch(error){
      console.error(error);
      alert(error.message||'No se ha podido reenviar la invitación.');
    }
  }

  function ownerModal(o){
    if(!o){
      const m=modal('Nuevo propietario',`<form id="ownerForm" class="admin-form-grid"><label>Nombre<input id="first" required></label><label>Apellidos<input id="last" required></label><label>Email<input id="email" type="email" required></label><label>Teléfono<input id="phone"></label><label>Dirección<input id="address"></label><label>Localidad<input id="city"></label><label>Código postal<input id="postal"></label></form><div class="modal-actions"><button id="createOwner" class="btn btn-dark">Enviar invitación</button><button class="btn btn-light" data-close>Cerrar</button></div><p class="admin-message"></p>`);
      m.querySelector('[data-close]').onclick=()=>m.remove();m.querySelector('#createOwner').onclick=async()=>{const msg=m.querySelector('.admin-message');msg.classList.remove('error');const email=val(m,'#email'),firstName=val(m,'#first'),lastName=val(m,'#last');if(!firstName||!lastName||!email){msg.textContent='Nombre, apellidos y email son obligatorios.';msg.classList.add('error');return;}if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)){msg.textContent='El email no tiene un formato válido.';msg.classList.add('error');return;}msg.textContent='Enviando invitación…';const {data:{session}}=await state.client.auth.getSession();if(!session){msg.textContent='La sesión de administración no es válida. Vuelve a iniciar sesión.';msg.classList.add('error');return;}const body={email,first_name:firstName,last_name:lastName,phone:val(m,'#phone')||null,address:val(m,'#address')||null,city:val(m,'#city')||null,postal_code:val(m,'#postal')||null};try{const r=await fetch('https://hvuseljtqdgekotrsiwd.supabase.co/functions/v1/create-owner',{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${session.access_token}`},body:JSON.stringify(body)});let data={};try{data=await r.json();}catch{}if(!r.ok)throw new Error(data.error||'No se ha podido crear el propietario.');msg.textContent='Propietario creado. Se ha enviado una invitación para que establezca su contraseña.';setTimeout(async()=>{m.remove();await refresh();renderView('owners');},500);}catch(e){msg.textContent=e.message||'No se ha podido crear el propietario.';msg.classList.add('error');}};
      return;
    }
    const m=modal('Editar propietario',`<form id="ownerForm" class="admin-form-grid"><label>Nombre<input id="first" value="${esc(o.first_name||'')}"></label><label>Apellidos<input id="last" value="${esc(o.last_name||'')}"></label><label>Email<input id="email" type="email" value="${esc(o.email||'')}"></label><label>Teléfono<input id="phone" value="${esc(o.phone||'')}"></label><label>Dirección<input id="address" value="${esc(o.address||'')}"></label><label>Localidad<input id="city" value="${esc(o.city||'')}"></label><label>Código postal<input id="postal" value="${esc(o.postal_code||'')}"></label></form><div class="modal-actions"><button id="saveOwner" class="btn btn-dark">Guardar cambios</button><button class="btn btn-light" data-close>Cerrar</button></div><p class="admin-message"></p>`);
    m.querySelector('[data-close]').onclick=()=>m.remove();m.querySelector('#saveOwner').onclick=async()=>{const q=await state.client.rpc('admin_update_owner_profile',{p_profile_id:o.profile_id,p_first_name:val(m,'#first')||null,p_last_name:val(m,'#last')||null,p_phone:val(m,'#phone')||null,p_address:val(m,'#address')||null,p_city:val(m,'#city')||null,p_postal_code:val(m,'#postal')||null,p_email:val(m,'#email')||null});if(q.error){toast(m,q.error.message,true);return;}m.remove();await refresh();renderView('owners');};
  }

  function renderBookings(root){
    const rows=[...state.bookings].sort((a,b)=>String(b.created_at).localeCompare(String(a.created_at)));
    root.innerHTML=header('RESERVAS','Solicitudes y reservas')+`<div class="admin-filters"><select id="bookingFilter">
      <option value="all">Todos los estados</option>
      <option value="pending">Pendientes</option>
      <option value="confirmed">Confirmadas</option>
      <option value="rejected">Rechazadas</option>
      <option value="expired">Caducadas</option>
      <option value="cancelled">Canceladas</option>
    </select></div><div class="admin-card"><div class="admin-table-wrap"><table class="admin-table">
      <thead><tr><th>Espacio</th><th>Cliente</th><th>Fechas</th><th>Limpieza</th><th>Estado</th><th>Acciones</th></tr></thead>
      <tbody id="bookingRows"></tbody></table></div></div><p class="admin-message"></p>`;

    const paint=()=>{
      const f=root.querySelector('#bookingFilter').value;
      const filtered=f==='all'?rows:rows.filter(b=>b.booking_status===f);
      root.querySelector('#bookingRows').innerHTML=filtered.length
        ? filtered.map(b=>`<tr>
            <td data-label="Espacio"><strong>${esc(b.space_name)}</strong></td>
            <td data-label="Cliente"><strong>${esc(b.customer_name)}</strong><span class="table-sub">${esc(b.customer_email)}<br>${esc(b.customer_phone)}</span></td>
            <td data-label="Fechas">${date(b.start_date)} → ${date(b.end_date)}<span class="table-sub">${b.total_days} día(s)</span></td>
            <td data-label="Limpieza">${b.cleaning_requested?'Sí':'No'}</td>
            <td data-label="Estado"><span class="status status-${esc(b.booking_status)}">${labelStatus(b.booking_status)}</span></td>
            <td data-label="Acciones" class="admin-booking-actions">
              ${b.booking_status==='pending'?`<button class="btn btn-dark" data-confirm="${b.id}">Aceptar</button><button class="btn btn-light" data-reject="${b.id}">Rechazar</button>`:''}
              ${b.booking_status==='confirmed'?`<button class="btn btn-light" data-modify="${b.id}">Modificar</button><button class="btn btn-light" data-cancel="${b.id}">Cancelar</button>`:''}
            </td>
          </tr>`).join('')
        : `<tr><td colspan="6" class="muted">No hay reservas en este estado.</td></tr>`;

      root.querySelectorAll('[data-confirm]').forEach(b=>b.onclick=()=>decideBooking(b.dataset.confirm,true));
      root.querySelectorAll('[data-reject]').forEach(b=>b.onclick=()=>decideBooking(b.dataset.reject,false));
      root.querySelectorAll('[data-modify]').forEach(b=>b.onclick=()=>openAdminBookingEditor(b.dataset.modify));
      root.querySelectorAll('[data-cancel]').forEach(b=>b.onclick=()=>cancelAdminBooking(b.dataset.cancel));
    };

    root.querySelector('#bookingFilter').onchange=paint;
    paint();

    async function decideBooking(id,confirm){
      const q=await state.client.rpc(confirm?'confirm_booking':'reject_booking',{p_booking_id:id});
      if(q.error){toast(root,q.error.message,true);return;}
      await refresh();renderView('bookings');
    }
  }

  async function openAdminBookingEditor(bookingId){
    const b=state.bookings.find(x=>String(x.id)===String(bookingId));
    if(!b){alert('Reserva no encontrada.');return;}

    const servicesRes=await state.client.rpc('get_public_space_services',{p_space_id:b.space_id});
    if(servicesRes.error){alert(servicesRes.error.message);return;}
    const services=servicesRes.data||[];

    const m=modal('Modificar reserva',`<form id="adminBookingForm" class="admin-form-grid">
      <label>Fecha de inicio<input id="adminModStart" type="date" value="${esc(b.start_date)}"></label>
      <label>Fecha de fin<input id="adminModEnd" type="date" value="${esc(b.end_date)}"></label>
      <label class="form-wide">Limpieza <span class="check-row"><input id="adminModCleaning" type="checkbox" ${b.cleaning_requested?'checked':''}> Solicitar limpieza</span></label>
      ${services.length?`<label class="form-wide">Servicios${services.map(x=>x.included?'':`<span class="check-row"><input class="admin-mod-service" type="checkbox" value="${esc(x.id)}"> ${esc(x.name)} (${money(x.price)})</span>`).join('')}</label>`:''}
    </form><p class="micro">La reserva seguirá confirmada. Las nuevas fechas se comprobarán antes de guardar.</p>
    <button id="adminModSave" class="btn btn-dark full" type="button">Guardar modificación</button><p id="adminModMsg" class="message"></p>`);

    m.querySelector('#adminModSave').onclick=async()=>{
      const msg=m.querySelector('#adminModMsg');
      const selectedServices=[...m.querySelectorAll('.admin-mod-service:checked')].map(x=>({id:x.value}));
      const q=await state.client.rpc('owner_update_booking',{
        p_booking_id:bookingId,
        p_start_date:m.querySelector('#adminModStart').value,
        p_end_date:m.querySelector('#adminModEnd').value,
        p_cleaning_requested:m.querySelector('#adminModCleaning').checked,
        p_selected_services:selectedServices,
        p_customer_notes:null
      });
      if(q.error){msg.textContent=q.error.message;return;}
      m.remove();await refresh();renderView('bookings');
    };
  }

  async function cancelAdminBooking(bookingId){
    const reason=prompt('Motivo de la cancelación (obligatorio):','');
    if(!reason?.trim()) return;
    const q=await state.client.rpc('owner_cancel_booking',{p_booking_id:bookingId,p_reason:reason.trim()});
    if(q.error){alert(q.error.message);return;}
    await refresh();renderView('bookings');
  }

  const labelStatus=s=>({pending:'Pendiente',confirmed:'Confirmada',rejected:'Rechazada',expired:'Caducada',cancelled:'Cancelada'}[s]||s);

  async function renderCalendar(root){
    root.innerHTML=header('CALENDARIO','Bloqueos de espacios',`<select id="calendarSpace">${state.spaces.map(s=>`<option value="${s.id}">${esc(s.name)}</option>`).join('')}</select>`)+`<div id="calendarContent"></div>`;
    const paint=async()=>{const s=state.spaces.find(x=>x.id===root.querySelector('#calendarSpace').value);if(!s){root.querySelector('#calendarContent').innerHTML='<p class="muted">No hay espacios.</p>';return;}const [blocks,books]=await Promise.all([state.client.rpc('admin_get_blocked_dates',{p_space_id:s.id}),state.client.rpc('admin_get_space_bookings',{p_space_id:s.id})]);root.querySelector('#calendarContent').innerHTML=`<div class="calendar-admin-grid"><section class="admin-card"><p class="eyebrow">BLOQUEOS</p><h2>${esc(s.name)}</h2><div class="admin-list">${(blocks.data||[]).map(x=>`<div class="admin-list-row"><div><strong>${date(x.start_date)} → ${date(x.end_date)}</strong><span>${esc(x.reason||'Sin motivo')}</span></div><button class="btn btn-light" data-del-block="${x.id}">Eliminar</button></div>`).join('')||'<p class="muted">Sin bloqueos.</p>'}</div></section><section class="admin-card"><p class="eyebrow">RESERVAS</p><h2>Calendario de ${esc(s.name)}</h2><div class="admin-list">${(books.data||[]).filter(x=>['pending','confirmed'].includes(x.booking_status)).map(x=>`<div class="admin-list-row"><div><strong>${date(x.start_date)} → ${date(x.end_date)}</strong><span>${esc(x.customer_name)} · ${x.cleaning_requested?'Con limpieza':'Sin limpieza'}</span></div><span class="status status-${x.booking_status}">${labelStatus(x.booking_status)}</span></div>`).join('')||'<p class="muted">Sin reservas activas.</p>'}</div></section></div><div class="admin-card block-quick"><h2>Bloquear fechas</h2><div class="block-form"><label>Desde<input id="quickFrom" type="date"></label><label>Hasta<input id="quickUntil" type="date"></label><label>Motivo<input id="quickReason"></label><button id="quickAdd" class="btn btn-dark">Bloquear</button></div><p class="admin-message"></p></div>`;root.querySelectorAll('[data-del-block]').forEach(b=>b.onclick=async()=>{const q=await state.client.rpc('admin_delete_blocked_date',{p_blocked_id:b.dataset.delBlock});if(q.error){toast(root,q.error.message,true);return;}paint();});root.querySelector('#quickAdd').onclick=async()=>{const from=val(root,'#quickFrom'),until=val(root,'#quickUntil');const q=await state.client.rpc('admin_create_blocked_date',{p_space_id:s.id,p_start_date:from,p_end_date:until,p_reason:val(root,'#quickReason')||null});if(q.error){toast(root,q.error.message,true);return;}paint();};};
    root.querySelector('#calendarSpace').onchange=paint;await paint();
  }

  async function refresh(){await loadAll(state.client);}

  window.initAdminPanel=async function(){
    const root=document.querySelector('#adminArea');if(!root)return;
    root.innerHTML='<p class="muted">Comprobando acceso…</p>';
    try{const c=await requireAdmin();if(!c)return;await loadAll(c);shell();renderView('dashboard');}
    catch(e){console.error(e);root.innerHTML=`<div class="admin-card"><h2>No se ha podido cargar la administración</h2><p class="message error">${esc(e.message||'Error desconocido')}</p><a class="btn btn-light" href="area-privada.html">Volver al área privada</a></div>`;}
  };
})();