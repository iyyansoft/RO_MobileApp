import { createClient, type User } from 'https://esm.sh/@supabase/supabase-js@2';
import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import {
  createShopDeliveryHandler, createShopDeliveryRepository, ShopDeliveryError,
} from '../_shared/shop_delivery_core.mjs';

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new ShopDeliveryError(503, 'Shop delivery is not configured.');
  return value;
}

async function authenticate(request: Request): Promise<User | null> {
  const authorization = request.headers.get('Authorization');
  if (!authorization?.startsWith('Bearer ')) return null;
  const token = authorization.slice('Bearer '.length).trim();
  if (!token) return null;
  const client = createClient(env('SUPABASE_URL'), env('SUPABASE_ANON_KEY'), {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.getUser(token);
  return error ? null : data.user;
}

const service = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), {
  auth: { persistSession: false, autoRefreshToken: false },
});

serve(createShopDeliveryHandler({
  authenticate,
  submit: createShopDeliveryRepository(service),
}));
