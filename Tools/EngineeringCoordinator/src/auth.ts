import { SignJWT, jwtVerify } from "jose";
import { timingSafeEqual } from "node:crypto";
import { botIds, DomainError } from "./domain";
export type Principal = { role: "owner" } | { role: "runner"; botId: string };
const bytes = (s: string) => new TextEncoder().encode(s);
export async function authenticate(
  request: Request,
  ownerToken: string | undefined,
  signingKey: string | undefined,
): Promise<Principal> {
  if (
    !ownerToken ||
    ownerToken.length < 32 ||
    !signingKey ||
    signingKey.length < 32
  )
    throw new DomainError("Runtime credentials are not configured", 503);
  const header = request.headers.get("Authorization");
  if (!header?.startsWith("Bearer "))
    throw new DomainError("Authentication required", 401);
  const token = header.slice(7);
  if (
    bytes(token).length === bytes(ownerToken).length &&
    timingSafeEqual(bytes(token), bytes(ownerToken))
  )
    return { role: "owner" };
  try {
    const { payload } = await jwtVerify(token, bytes(signingKey), {
      issuer: "engineering-coordinator",
      audience: "engineering-runner",
      algorithms: ["HS256"],
    });
    if (payload.role !== "runner" || !botIds.some((id) => id === payload.sub))
      throw Error();
    return { role: "runner", botId: payload.sub! };
  } catch {
    throw new DomainError("Invalid or expired runner token", 401);
  }
}
export async function mintRunner(botId: string, signingKey: string) {
  if (!botIds.some((id) => id === botId))
    throw new DomainError("Unknown specialist", 400);
  return new SignJWT({ role: "runner" })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuer("engineering-coordinator")
    .setAudience("engineering-runner")
    .setSubject(botId)
    .setIssuedAt()
    .setExpirationTime("24h")
    .sign(bytes(signingKey));
}
