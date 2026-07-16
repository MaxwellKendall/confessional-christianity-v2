import type { Metadata } from 'next';
import { Cinzel, Marcellus } from 'next/font/google';

import { SiteHeader } from '@/components/SiteHeader';
import './globals.css';

const cinzel = Cinzel({
  variable: '--font-cinzel',
  subsets: ['latin'],
  weight: ['400', '500', '600', '700'],
});

const marcellus = Marcellus({
  variable: '--font-marcellus',
  subsets: ['latin'],
  weight: '400',
});

export const metadata: Metadata = {
  metadataBase: new URL('https://confessionalchristianity.com'),
  title: {
    default: 'Confessional Christianity',
    template: '%s | Confessional Christianity',
  },
  description:
    'Catechize your child — walk through a historic catechism question by question, '
    + 'rooted in scripture, with the confessions and catechisms of historic '
    + 'Protestantism to read and search.',
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={`${cinzel.variable} ${marcellus.variable} h-full antialiased`}>
      <body className="min-h-full">
        {/*
          The shell spans the whole viewport; width discipline belongs to the
          routes — content pages share a centered column via the (column)
          route group, the homepage manages its own wider measure.
        */}
        <div className="flex min-h-screen w-full flex-col bg-card">
          <SiteHeader />
          <main className="flex flex-1 flex-col">{children}</main>
        </div>
      </body>
    </html>
  );
}
