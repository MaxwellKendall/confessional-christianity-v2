import { NextResponse, type NextRequest } from 'next/server';

import { ADMIN_COOKIE, adminAccess, isAdminToken } from '@/lib/admin/session';

// Gates /admin (the devotion editor). Pages redirect to the login screen;
// the server actions re-check the cookie themselves (requireAdmin), since a
// proxy matcher is a routing convenience, not an authorization boundary.
export async function proxy(request: NextRequest) {
  if (adminAccess() === 'disabled') {
    return new NextResponse('Not Found', { status: 404 });
  }
  if (request.nextUrl.pathname === '/admin/login') return NextResponse.next();
  if (await isAdminToken(request.cookies.get(ADMIN_COOKIE)?.value)) return NextResponse.next();

  const login = new URL('/admin/login', request.url);
  login.searchParams.set('next', request.nextUrl.pathname);
  return NextResponse.redirect(login);
}

export const config = {
  matcher: ['/admin', '/admin/:path*'],
};
