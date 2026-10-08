import { DomainError } from "./domain";
export async function readJSON(
  request: Request,
  limit = 65536,
): Promise<unknown> {
  if (!request.body) throw new DomainError("JSON body required", 400);
  const reader = request.body.getReader();
  const decoder = new TextDecoder();
  let size = 0,
    result = "";
  try {
    for (;;) {
      const part = await reader.read();
      if (part.done) break;
      size += part.value.length;
      if (size > limit) {
        await reader.cancel();
        throw new DomainError("Request too large", 413);
      }
      result += decoder.decode(part.value, { stream: true });
    }
    result += decoder.decode();
    return JSON.parse(result);
  } catch (e) {
    if (e instanceof DomainError) throw e;
    throw new DomainError("Invalid JSON", 400);
  } finally {
    reader.releaseLock();
  }
}
export const json = (value: unknown, status = 200) =>
  Response.json(value, {
    status,
    headers: {
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
