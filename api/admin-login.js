import { createClient } from '@supabase/supabase-js';

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: '허용되지 않은 요청입니다.' });

  const { SUPABASE_URL, SUPABASE_ANON_KEY, ADMIN_EMAIL } = process.env;
  const password = typeof req.body?.password === 'string' ? req.body.password : '';
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !ADMIN_EMAIL) {
    return res.status(500).json({ error: 'Vercel 환경변수 설정이 완료되지 않았습니다.' });
  }
  if (!password || password.length > 256) return res.status(400).json({ error: '비밀번호를 입력해 주세요.' });

  // The admin email stays server-side. Supabase Auth verifies the password and
  // RLS + admin_users decides whether this account can write site data.
  const authClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }
  });
  const { data, error } = await authClient.auth.signInWithPassword({ email: ADMIN_EMAIL, password });
  if (error || !data.session) return res.status(401).json({ error: '관리자 비밀번호가 올바르지 않습니다.' });

  return res.status(200).json({
    session: { access_token: data.session.access_token, refresh_token: data.session.refresh_token }
  });
}
