import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const resendKey = Deno.env.get('RESEND_API_KEY')!;
const adminEmail = Deno.env.get('ADMIN_EMAIL') || 'miespacioparacelebrar@gmail.com';
const fromEmail = Deno.env.get('FROM_EMAIL') || adminEmail;
const siteUrl = Deno.env.get('SITE_URL') || 'https://webjisa.github.io/MiEspacioParaCelebrar/';
const supabase = createClient(supabaseUrl, serviceKey);

const esc = (v: unknown) => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
const dateLong = (iso: string) => new Intl.DateTimeFormat('es-ES',{day:'numeric',month:'long',year:'numeric'}).format(new Date(`${iso}T12:00:00`));
const dates = (start:string,end:string) => { if(start===end) return dateLong(start); const a=new Date(`${start}T12:00:00`),b=new Date(`${end}T12:00:00`); const sameMonth=a.getMonth()===b.getMonth()&&a.getFullYear()===b.getFullYear(); const arr:string[]=[]; for(let d=new Date(a);d<=b;d.setDate(d.getDate()+1)) arr.push(new Intl.DateTimeFormat('es-ES',{day:'numeric'}).format(d)); if(sameMonth) return `${arr.slice(0,-1).join(', ')} y ${arr.at(-1)} de ${new Intl.DateTimeFormat('es-ES',{month:'long',year:'numeric'}).format(b)}`; return `${dateLong(start)} y ${dateLong(end)}`; };
const base = (title:string,body:string,buttons='') => `<div style="font-family:Arial,sans-serif;max-width:620px;margin:auto;color:#20201f"><h1 style="font-size:24px">${esc(title)}</h1>${body}${buttons?`<p style="margin-top:28px">${buttons}</p>`:''}<p style="font-size:12px;color:#777;margin-top:35px">MiEspacioParaCelebrar</p></div>`;
const button=(href:string,label:string)=>`<a href="${esc(href)}" style="display:inline-block;padding:12px 18px;border-radius:999px;background:#20201f;color:#fff;text-decoration:none;margin-right:8px">${esc(label)}</a>`;

async function send(to:string,name:string,subject:string,html:string){
  const r=await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:`Bearer ${resendKey}`,'Content-Type':'application/json'},body:JSON.stringify({from:`MiEspacioParaCelebrar <${fromEmail}>`,to:[to],subject,html})});
  if(!r.ok) throw new Error(await r.text());
}

function customerTemplate(type:string,p:any){
  const ds=dates(p.start_date,p.end_date), space=p.space_name;
  if(type==='customer_request_received') return {subject:`Reserva — ${space} — Solicitud recibida`,html:base(`Solicitud recibida — ${space}`,`<p>Hola ${esc(p.customer_name)},</p><p>Hemos recibido tu solicitud.</p><p><strong>Espacio:</strong> ${esc(space)}<br><strong>Fecha(s):</strong> ${esc(ds)}</p><p>El propietario dispone de 72 horas para procesarla. La reserva no queda confirmada hasta que el propietario la acepte.</p>`)};
  if(type==='customer_updated') return {subject:`Reserva — ${space} — Actualizada`,html:base(`Reserva actualizada — ${space}`,`<p>Hola ${esc(p.customer_name)},</p><p>La reserva ha sido modificada correctamente y permanece en vigor para las fechas acordadas.</p><p><strong>Espacio:</strong> ${esc(space)}<br><strong>Fecha(s):</strong> ${esc(ds)}</p>`)};
  if(type==='customer_confirmed') return {subject:`Reserva — ${space} — Confirmada`,html:base(`Reserva confirmada — ${space}`,`<p>Hola ${esc(p.customer_name)},</p><p>Tu solicitud ha sido aceptada.</p><p><strong>Espacio:</strong> ${esc(space)}<br><strong>Fecha(s):</strong> ${esc(ds)}</p>`)};
  if(type==='customer_cancelled') return {subject:`Reserva — ${space} — Cancelada`,html:base(`Reserva cancelada — ${space}`,`<p>Hola ${esc(p.customer_name)},</p><p>La reserva ha sido cancelada por el propietario.</p><p><strong>Espacio:</strong> ${esc(space)}<br><strong>Fecha(s):</strong> ${esc(ds)}</p>`,button(`${siteUrl}espacios.html`,'Buscar otra fecha')+button(`${siteUrl}espacios.html`,'Ver otros espacios'))};
  if(type==='customer_not_processed') return {subject:`Reserva — ${space} — No procesada`,html:base(`Solicitud no procesada — ${space}`,`<p>Hola ${esc(p.customer_name)},</p><p>La solicitud no ha podido ser procesada.</p><p><strong>Espacio:</strong> ${esc(space)}<br><strong>Fecha(s):</strong> ${esc(ds)}</p>`,button(`${siteUrl}espacios.html`,'Buscar otra fecha')+button(`${siteUrl}espacios.html`,'Ver otros espacios'))};
  return {subject:`Reserva — ${space} — ${type==='customer_expired'?'Caducada':'Actualizada'}`,html:base(`Reserva — ${space}`,`<p>Hola ${esc(p.customer_name)},</p><p>${type==='customer_expired'?'La solicitud no fue confirmada por el propietario dentro del periodo establecido.':'La reserva ha sido actualizada correctamente y permanece vigente para las fechas acordadas.'}</p><p><strong>Espacio:</strong> ${esc(space)}<br><strong>Fecha(s):</strong> ${esc(ds)}</p>`,type==='customer_expired'?button(`${siteUrl}espacios.html`,'Buscar otra fecha')+button(`${siteUrl}espacios.html`,'Ver otros espacios'):'')};
}

async function main(){
  const {data:rows,error}=await supabase.from('email_queue').select('*').eq('status','pending').lte('next_attempt_at',new Date().toISOString()).order('created_at').limit(20);
  if(error) throw error;
  const results=[];
  for(const row of rows||[]){
    await supabase.from('email_queue').update({status:'processing',attempts:(row.attempts||0)+1}).eq('id',row.id).eq('status','pending');
    try{
      const p=row.payload||{}; let subject='MiEspacioParaCelebrar'; let html='';
      if(row.communication_type.startsWith('customer_')){const t=customerTemplate(row.communication_type,p);subject=t.subject;html=t.html;}
      else if(row.communication_type==='request_created'){
        subject=`Nueva solicitud — ${p.space_name}`; html=base(subject,`<p>Has recibido una nueva solicitud de ${esc(p.customer_name)}.</p><p><strong>Espacio:</strong> ${esc(p.space_name)}<br><strong>Fecha(s):</strong> ${esc(dates(p.start_date,p.end_date))}<br><strong>Cliente:</strong> ${esc(p.customer_name)}<br><strong>Email:</strong> ${esc(p.customer_email)}<br><strong>Teléfono:</strong> ${esc(p.customer_phone)}<br><strong>Caduca:</strong> ${esc(new Date(p.expires_at).toLocaleString('es-ES'))}</p><p>Consulta el detalle en tu área privada y contacta directamente con el cliente.</p>`);
      } else if(row.communication_type==='admin_request_created'){
        subject=`Reserva — ${p.space_name} — Nueva solicitud`; html=base(subject,`<p>Se ha creado una solicitud de reserva.</p><p><strong>Espacio:</strong> ${esc(p.space_name)}<br><strong>Cliente:</strong> ${esc(p.customer_name)}<br><strong>Fecha(s):</strong> ${esc(dates(p.start_date,p.end_date))}<br><strong>Email:</strong> ${esc(p.customer_email)}<br><strong>Teléfono:</strong> ${esc(p.customer_phone)}</p>`);
      } else if(row.communication_type==='admin_booking_final'){
        subject=`Reserva — ${p.space_name} — Finalizada`; html=base(subject,`<p>La solicitud ha finalizado.</p><p><strong>Espacio:</strong> ${esc(p.space_name)}<br><strong>Cliente:</strong> ${esc(p.customer_name)}<br><strong>Estado:</strong> ${esc(p.status)}<br><strong>Comentario:</strong> ${esc(p.comment||'No se han añadido comentarios')}</p>`);
      } else if(row.communication_type==='owner_booking_final'){
        subject=`Reserva — ${p.space_name} — Finalizada`; html=base(subject,`<p>La solicitud ha finalizado.</p><p><strong>Espacio:</strong> ${esc(p.space_name)}<br><strong>Cliente:</strong> ${esc(p.customer_name)}<br><strong>Estado:</strong> ${esc(p.status)}<br><strong>Comentario:</strong> ${esc(p.comment||'No se han añadido comentarios')}</p>`);
      } else if(row.communication_type==='owner_pending_reminder'){
        subject=`Reserva — ${p.space_name} — Recordatorio`; html=base(subject,`<p>Tienes una solicitud pendiente que todavía no ha sido procesada.</p><p><strong>Espacio:</strong> ${esc(p.space_name)}<br><strong>Cliente:</strong> ${esc(p.customer_name)}<br><strong>Fecha(s):</strong> ${esc(dates(p.start_date,p.end_date))}<br><strong>Caduca:</strong> ${esc(new Date(p.expires_at).toLocaleString('es-ES'))}</p>`);
      } else if(row.communication_type==='owner_customer_delivery_failed'){
        subject=`Reserva — ${p.space_name} — Error de entrega`; html=base(subject,`<p>No se ha podido entregar al cliente la última comunicación de la reserva.</p><p><strong>Espacio:</strong> ${esc(p.space_name)}<br><strong>Cliente:</strong> ${esc(p.customer_name)}<br><strong>Email:</strong> ${esc(p.customer_email)}<br><strong>Fecha(s):</strong> ${esc(dates(p.start_date,p.end_date))}</p><p>La reserva sigue vigente. Puedes revisar los datos y reenviar la misma comunicación desde el área privada.</p>`,button(p.resend_url,'Reenviar comunicación'));
      } else if(row.communication_type==='owner_email_changed'){
        subject=`Reserva — ${p.space_name} — Email actualizado`; html=base(subject,`<p>Se ha actualizado el email del cliente.</p><p><strong>Espacio:</strong> ${esc(p.space_name)}<br><strong>Cliente:</strong> ${esc(p.customer_name)}<br><strong>Nuevo email:</strong> ${esc(p.customer_email)}<br><strong>Fecha(s):</strong> ${esc(dates(p.start_date,p.end_date))}</p>`);
      } else if(row.communication_type==='space_enabled' || row.communication_type==='space_disabled'){
        subject=`${row.communication_type==='space_enabled'?'Habilitado':'Deshabilitado'} — ${p.space_name}`; html=base(subject,`<p>El espacio <strong>${esc(p.space_name)}</strong> ha sido ${row.communication_type==='space_enabled'?'habilitado':'deshabilitado'} por administración.</p>`);
      } else if(row.communication_type==='survey_created'){
        subject=`Encuesta — ${p.space_name}`; html=base(subject,`<p>Hola ${esc(row.recipient_name||'')},</p><p>Queremos conocer tu experiencia en <strong>${esc(p.space_name)}</strong>.</p><p>${button(`${siteUrl}encuesta.html?token=${encodeURIComponent(p.token)}`,'Completar encuesta')}</p>`);
      } else { subject=`MiEspacioParaCelebrar — ${row.communication_type}`; html=base(subject,`<p>Información de MiEspacioParaCelebrar.</p>`); }
      await send(row.recipient_email,row.recipient_name||'',subject,html);
      await supabase.from('email_queue').update({status:'sent',sent_at:new Date().toISOString(),last_error:null}).eq('id',row.id);
      if(row.booking_id && row.communication_type.startsWith('customer_')) await supabase.from('bookings').update({customer_email_delivery_status:'sent',last_customer_email_sent_at:new Date().toISOString()}).eq('id',row.booking_id);
      results.push({id:row.id,status:'sent'});
    }catch(e){
      const attempts=(row.attempts||0)+1, failed=attempts>=5, next=new Date(Date.now()+Math.min(60,2**attempts)*60000).toISOString();
      await supabase.from('email_queue').update({status:failed?'failed':'pending',next_attempt_at:next,last_error:String(e)}).eq('id',row.id);
      if(row.booking_id && row.communication_type.startsWith('customer_')) { await supabase.from('bookings').update({customer_email_delivery_status:'failed'}).eq('id',row.booking_id); if(failed){ const {data:b}=await supabase.from('bookings').select('id,customer_name,customer_email,start_date,end_date,space_id').eq('id',row.booking_id).maybeSingle(); if(b){ const {data:sp}=await supabase.from('spaces').select('name,owner_id').eq('id',b.space_id).maybeSingle(); const {data:ow}=sp?await supabase.from('owners').select('profile_id').eq('id',sp.owner_id).maybeSingle():{data:null}; const {data:pr}=ow?await supabase.from('profiles').select('email,first_name,last_name').eq('id',ow.profile_id).maybeSingle():{data:null}; if(pr?.email){await supabase.from('email_queue').insert({category:'reservas',communication_type:'owner_customer_delivery_failed',booking_id:b.id,space_id:b.space_id,recipient_email:pr.email,recipient_name:`${pr.first_name||''} ${pr.last_name||''}`.trim(),payload:{booking_id:b.id,space_name:sp.name,customer_name:b.customer_name,customer_email:b.customer_email,start_date:b.start_date,end_date:b.end_date,resend_url:`${siteUrl}area-privada.html?resend=${b.id}`}});} } } }
      results.push({id:row.id,status:failed?'failed':'retry'});
    }
  }
  return new Response(JSON.stringify({processed:results}),{headers:{'Content-Type':'application/json'}});
}
Deno.serve(()=>main().catch(e=>new Response(JSON.stringify({error:String(e)}),{status:500,headers:{'Content-Type':'application/json'}})));
