// Public Cognito configuration for the /account page (TKL-1043).
// Pool and client IDs are public identifiers, not secrets.

export interface PublicCognitoConfig {
  userPoolId: string;
  clientId: string;
  region: string;
}

const POOL_ID_PATTERN = /^([a-z]{2}-[a-z0-9-]+-\d+)_[A-Za-z0-9]+$/;

export const parseCognitoRegion = (userPoolId: string): string | null => {
  const match = POOL_ID_PATTERN.exec(userPoolId.trim());
  return match ? match[1] : null;
};

export const publicCognitoConfig = (
  env: Record<string, string | undefined> = process.env,
): PublicCognitoConfig | null => {
  const userPoolId = env.NEXT_PUBLIC_COGNITO_USER_POOL_ID?.trim();
  const clientId = env.NEXT_PUBLIC_COGNITO_CLIENT_ID?.trim();
  if (!userPoolId || !clientId) return null;
  const region = parseCognitoRegion(userPoolId);
  if (!region) return null;
  return { userPoolId, clientId, region };
};
