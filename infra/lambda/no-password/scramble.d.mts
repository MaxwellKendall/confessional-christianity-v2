export interface SetPasswordInput { UserPoolId: string; Username: string; Password: string; Permanent: boolean }
export function randomPassword(): string;
export function scrambleHandler<E extends { userPoolId: string; userName: string }>(
  setPassword: (input: SetPasswordInput) => Promise<unknown>,
): (event: E) => Promise<E>;
