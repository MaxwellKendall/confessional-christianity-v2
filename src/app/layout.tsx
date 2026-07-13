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
          The app renders as a single centered column on the canvas —
          full-bleed on mobile (the mockups' 390px frame), a bordered card
          on wider screens. Reading pages cap their own prose at 44rem.
        */}
        <div className="mx-auto flex min-h-screen w-full max-w-[44rem] flex-col bg-card sm:border-x sm:border-hairline-2">
          <SiteHeader />
          <main className="flex flex-1 flex-col">{children}</main>
        </div>
      </body>
    </html>
  );
}
