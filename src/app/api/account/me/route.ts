import { handleAccountMeRequest } from '@/lib/account/meHandler';
import { studioAuthConfigFromEnv } from '@/lib/lordsDay/auth';

export const dynamic = 'force-dynamic';

export async function GET(request: Request) {
  return handleAccountMeRequest(request, studioAuthConfigFromEnv());
}
