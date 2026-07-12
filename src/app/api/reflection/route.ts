import { NextRequest, NextResponse } from 'next/server';

import { getReflectionByEntryId } from '@/lib/reflections';

// Reflections are read from the filesystem (content/commentary/*.md), so a
// client component asks for one by entry id rather than importing fs code.
export async function GET(request: NextRequest) {
  const entryId = request.nextUrl.searchParams.get('entryId');
  if (!entryId) {
    return NextResponse.json({ error: 'entryId required' }, { status: 400 });
  }
  const reflection = await getReflectionByEntryId(entryId);
  if (!reflection) {
    return NextResponse.json({ slug: null, title: null });
  }
  return NextResponse.json({ slug: reflection.slug, title: reflection.title });
}
