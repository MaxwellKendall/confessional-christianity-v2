import { AdminSetUserPasswordCommand, CognitoIdentityProviderClient } from "@aws-sdk/client-cognito-identity-provider";
import { scrambleHandler } from "./scramble.mjs";

const cognito = new CognitoIdentityProviderClient({});
export const handler = scrambleHandler((input) => cognito.send(new AdminSetUserPasswordCommand(input)));
