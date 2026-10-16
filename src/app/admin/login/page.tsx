import { LoginForm } from './LoginForm';

export const metadata = { title: 'Sign in' };

export default async function AdminLoginPage(
  { searchParams }: { searchParams: Promise<{ next?: string }> },
) {
  const { next } = await searchParams;
  return (
    <div className="mx-auto w-full max-w-sm pt-10 text-center">
      <div className="label-caps text-[9.5px] tracking-[0.12em] text-ink-3">Admin</div>
      <h1 className="mt-1.5 mb-6 heading-page">Sign in</h1>
      <LoginForm next={next ?? '/admin/devotions'} />
    </div>
  );
}
