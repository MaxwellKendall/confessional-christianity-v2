// The devotion admin: a working tool, not a reading page, so it takes a
// wider measure than the (column) group and stays out of search indexes.
import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: { default: 'Admin', template: '%s | Admin' },
  robots: { index: false, follow: false },
};

export default function AdminLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <div className="mx-auto flex w-full max-w-[60rem] flex-1 flex-col px-4 pt-6 pb-16 sm:px-8">
      {children}
    </div>
  );
}
