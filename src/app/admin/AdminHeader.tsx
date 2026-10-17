import Link from 'next/link';

import { adminAccess } from '@/lib/admin/session';
import { getDevotionStore } from '@/lib/admin/store';
import { logout } from './actions';

const MODE_NOTE = {
  local: 'Local — saves write to content/devotions on this checkout',
  github: 'Saves open a pull request for review',
} as const;

const SECTIONS = [
  { key: 'devotions', href: '/admin/devotions', label: 'Devotions' },
  { key: 'series', href: '/admin/series', label: 'Series' },
] as const;

export function AdminHeader(
  { section = 'devotions', crumbs = [] }: {
    section?: (typeof SECTIONS)[number]['key'];
    crumbs?: { href?: string; label: string }[];
  },
) {
  const setup = getDevotionStore();
  return (
    <div className="mb-6 flex flex-wrap items-baseline justify-between gap-3 border-b border-hairline pb-3">
      <nav className="label-caps flex flex-wrap items-baseline gap-2 text-[10.5px] text-ink-3">
        <span className="text-ink">Admin</span>
        <span aria-hidden="true">·</span>
        {SECTIONS.map(({ key, href, label }) => (
          <Link
            key={key}
            href={href}
            aria-current={key === section ? 'page' : undefined}
            className={`no-underline ${key === section ? 'text-ink' : 'text-ink-3'}`}
          >
            {label}
          </Link>
        ))}
        {crumbs.map((crumb) => (
          <span key={crumb.label} className="flex gap-2">
            <span aria-hidden="true">›</span>
            {crumb.href
              ? <Link href={crumb.href} className="text-ink-3 no-underline">{crumb.label}</Link>
              : <span className="normal-case tracking-normal font-body text-[13px]">{crumb.label}</span>}
          </span>
        ))}
      </nav>
      <div className="flex items-baseline gap-4 text-[12px] text-ink-3">
        <span>{setup.ok ? MODE_NOTE[setup.store.mode] : 'Saving is not configured'}</span>
        {adminAccess() === 'password' && (
          <form action={logout}>
            <button type="submit" className="dotted-link cursor-pointer text-ink-3">Sign out</button>
          </form>
        )}
      </div>
    </div>
  );
}
