import { NextRequest, NextResponse } from 'next/server';

import { loadResources } from '@/lib/resources';

// Resources are read from the filesystem (content/resources/<entryId>/), so
// client components ask for an entry's list here rather than importing fs
// code — same shape as /api/reflection.
export async function GET(request: NextRequest) {
  const entryId = request.nextUrl.searchParams.get('entryId');
  if (!entryId) {
    return NextResponse.json({ error: 'entryId required' }, { status: 400 });
  }
  return NextResponse.json({ resources: await loadResources(entryId) });
}
