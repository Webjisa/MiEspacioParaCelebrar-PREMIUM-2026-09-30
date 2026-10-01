import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const c=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
Deno.serve(async()=>{const {data,error}=await c.rpc('expire_pending_bookings');if(error)return new Response(JSON.stringify({error:error.message}),{status:500});return new Response(JSON.stringify({expired:data||0}),{headers:{'Content-Type':'application/json'}})});
