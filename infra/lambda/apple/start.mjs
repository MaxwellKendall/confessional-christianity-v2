// TKL-889: appleStart, behind a Function URL. See provision.mjs.
import { randomBytes } from "node:crypto";
import {
  AdminCreateUserCommand, AdminGetUserCommand, AdminSetUserPasswordCommand, CognitoIdentityProviderClient,
} from "@aws-sdk/client-cognito-identity-provider";
import { startHandler } from "./provision.mjs";
import { verifyToken } from "./token.mjs";

const cognito = new CognitoIdentityProviderClient({});
const UserPoolId = process.env.USER_POOL_ID;
const toMap = (list) => Object.fromEntries((list ?? []).map(({ Name, Value }) => [Name, Value]));

const pool = {
  async get(address) {
    try {
      const user = await cognito.send(new AdminGetUserCommand({ UserPoolId, Username: address }));
      return { username: user.Username, status: user.UserStatus, attributes: toMap(user.UserAttributes) };
    } catch (e) {
      if (e.name === "UserNotFoundException") return undefined;
      throw e;
    }
  },
  async create(address, attributes) {
    const { User } = await cognito.send(new AdminCreateUserCommand({
      UserPoolId,
      Username: address,
      MessageAction: "SUPPRESS",
      UserAttributes: Object.entries({ email: address, ...attributes }).map(([Name, Value]) => ({ Name, Value })),
    }));
    return { username: User.Username, status: User.UserStatus, attributes: toMap(User.Attributes) };
  },
  async confirm(username) {
    // A password nobody ever sees, only to leave FORCE_CHANGE_PASSWORD. The NoPassword trigger replaces it again before
    // every sign-in, and the app client has no password flows.
    await cognito.send(new AdminSetUserPasswordCommand({
      UserPoolId, Username: username, Password: `${randomBytes(32).toString("base64url")}aA1!`, Permanent: true,
    }));
  },
};

export const handler = startHandler({ verifyToken, pool });
