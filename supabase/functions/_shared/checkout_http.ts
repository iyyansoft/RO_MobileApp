import { createClient, type User } from 'https://esm.sh/@supabase/supabase-js@2';

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

export function serviceClient() {
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) throw new HttpError(503, 'Supabase checkout is not configured.');
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

export async function authenticatedUser(request: Request): Promise<User> {
  const authorization = request.headers.get('Authorization');
  if (!authorization?.startsWith('Bearer ')) throw new HttpError(401, 'Sign in to continue checkout.');
  const accessToken = authorization.slice('Bearer '.length).trim();
  if (!accessToken) throw new HttpError(401, 'Sign in to continue checkout.');
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_ANON_KEY');
  if (!url || !key) throw new HttpError(503, 'Supabase checkout is not configured.');
  const client = createClient(url, key, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.getUser(accessToken);
  if (error || !data.user || !data.user.email_confirmed_at) {
    throw new HttpError(401, 'A verified Supabase sign-in is required for checkout.');
  }
  return data.user;
}

export async function postBody(request: Request): Promise<Record<string, unknown>> {
  let body: unknown;
  try { body = await request.json(); } catch { throw new HttpError(400, 'Invalid checkout request.'); }
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new HttpError(400, 'Invalid checkout request.');
  return body as Record<string, unknown>;
}

export function requiredRequestId(value: unknown): string {
  // The existing secure-storage helper formats 128 random bits as UUID text
  // but does not set RFC version/variant bits; PostgreSQL accepts that UUID form.
  if (typeof value !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)) {
    throw new HttpError(400, 'Checkout retry identifier is invalid. Retry checkout.');
  }
  return value;
}

export function errorResponse(error: unknown): Response {
  const status = error instanceof HttpError ? error.status : 400;
  const message = error instanceof Error ? error.message : 'Checkout could not be processed.';
  // Do not log request bodies, credentials, tokens or provider responses.
  console.error('[SUPABASE CHECKOUT]', error instanceof HttpError ? `HTTP_${status}` : 'CHECKOUT_FAILED');
  return jsonResponse({ success: false, error: message }, status);
}

export function safeRpcError(error: { message?: string } | null, fallback: string): string {
  const message = error?.message ?? '';
  const known = [
    'Dealer account is not approved for checkout',
    'Verified Supabase account required',
    'Select Cash on Delivery or Razorpay',
    'Unsupported payment confirmation',
    'Add products before checkout',
    'Product quantity must be a positive integer',
    'A product is no longer available; refresh the cart',
    'With GST requires a valid GST number',
    'Delivery and billing addresses are required',
    'Complete delivery address is required',
    'Complete billing address is required',
    'Payment checkout was not found or does not match',
    'Checkout details changed; create a new checkout request',
    'This request already started online payment',
    'Configured default shop is not active',
    'Order cannot be routed: configure a default shop or assign orders in Admin',
    'This checkout order was cancelled',
    'Order cancellation request is invalid',
    'Order was not found',
    'Online-paid or collected orders require a verified refund before cancellation',
    'An order with delivery activity must be resolved through the shop delivery workflow',
  ];
  if (known.some(value => message.startsWith(value))) return message;
  if (message.startsWith('Not enough stock for ')) return message;
  return fallback;
}

export async function validateShopRoute(client: ReturnType<typeof serviceClient>) {
  const { data, error } = await client.from('shop_employees').select('shop_name').eq('active', true).not('shop_name', 'is', null);
  if (error) throw new HttpError(503, 'Shop routing could not be verified before payment.');
  const shops = [...new Map<string, string>((data ?? [])
    .map(row => String(row.shop_name ?? '').trim())
    .filter(Boolean)
    .map(name => [name.toLowerCase(), name] as const)).values()];
  const configured = Deno.env.get('SHOP_DEFAULT_NAME')?.trim();
  if (configured) {
    if (!shops.some(name => name.toLowerCase() === configured.toLowerCase())) {
      throw new HttpError(503, 'Configured default shop is not active; contact the administrator before paying.');
    }
  } else if (shops.length > 1) {
    throw new HttpError(503, 'Order routing is ambiguous; contact the administrator before paying.');
  }
}

export async function razorpayRequest(path: string, method = 'GET', body?: unknown) {
  const key = Deno.env.get('RAZORPAY_KEY_ID');
  const secret = Deno.env.get('RAZORPAY_KEY_SECRET');
  if (!key || !secret) throw new HttpError(503, 'Razorpay is not configured. Select Cash on Delivery or contact the administrator.');
  let response: Response;
  try {
    response = await fetch(`https://api.razorpay.com/v1/${path}`, {
      method,
      headers: {
        Authorization: `Basic ${btoa(`${key}:${secret}`)}`,
        'Content-Type': 'application/json',
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      signal: AbortSignal.timeout(20000),
    });
  } catch {
    throw new HttpError(502, 'Razorpay could not be reached. Please retry verification before starting another payment.');
  }
  const value = await response.json().catch(() => ({}));
  if (!response.ok) throw new HttpError(502, 'Razorpay could not process this request. Please retry or contact the administrator.');
  return value as Record<string, unknown>;
}

export async function verifySignature(orderId: string, paymentId: string, signature: string) {
  const secret = Deno.env.get('RAZORPAY_KEY_SECRET');
  if (!secret) throw new HttpError(503, 'Razorpay is not configured.');
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const digest = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${orderId}|${paymentId}`)));
  let supplied: Uint8Array;
  try {
    if (!/^[0-9a-f]{64}$/i.test(signature)) throw new Error();
    supplied = new Uint8Array(signature.match(/.{2}/g)!.map(part => Number.parseInt(part, 16)));
  } catch { throw new HttpError(400, 'Payment signature verification failed.'); }
  let diff = digest.length ^ supplied.length;
  for (let i = 0; i < digest.length; i++) diff |= digest[i] ^ (supplied[i] ?? 0);
  if (diff !== 0) throw new HttpError(400, 'Payment signature verification failed.');
}

export async function approvedDealerId(client: ReturnType<typeof serviceClient>, authUserId: string): Promise<string> {
  const { data, error } = await client.from('users')
    .select('id,email_verified,is_approved,status')
    .eq('auth_user_id', authUserId).maybeSingle();
  if (error) throw new HttpError(503, 'Dealer profile could not be verified.');
  if (!data || data.email_verified !== true || data.is_approved !== true || data.status !== 'approved') {
    throw new HttpError(403, 'Your dealer account must be verified and approved before checkout.');
  }
  return String(data.id);
}
