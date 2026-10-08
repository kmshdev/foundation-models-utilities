import { REPOSITORY, DomainError } from "./domain";
import { readJSON } from "./http";
const projectId = "c655b4e0-e003-424a-a29a-3674e9a3983b";
async function bounded(response: Response) {
  if (!response.ok) {
    await response.body?.cancel();
    throw new DomainError("Integration returned HTTP " + response.status, 502);
  }
  return readJSON(
    new Request("https://local.invalid", {
      method: "POST",
      body: response.body,
      duplex: "half",
    } as RequestInit),
    1024 * 1024,
  );
}
export async function integrationStatus(env: Env) {
  const result: { github: unknown; linear: unknown } = {
    github: { connected: false, reason: "Runtime credential not configured" },
    linear: { connected: false, reason: "Runtime credential not configured" },
  };
  if (env.GITHUB_TOKEN) {
    try {
      const data = await bounded(
        await fetch(`https://api.github.com/repos/${REPOSITORY}`, {
          headers: {
            Authorization: `Bearer ${env.GITHUB_TOKEN}`,
            Accept: "application/vnd.github+json",
            "User-Agent": "EngineeringCoordinator",
          },
          signal: AbortSignal.timeout(10000),
        }),
      );
      result.github = {
        connected: true,
        repository: REPOSITORY,
        metadata: data,
      };
    } catch {
      result.github = {
        connected: false,
        reason: "Repository access check failed",
      };
    }
  }
  if (env.LINEAR_TOKEN) {
    try {
      const data = await bounded(
        await fetch("https://api.linear.app/graphql", {
          method: "POST",
          headers: {
            Authorization: env.LINEAR_TOKEN,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            query:
              "query ProjectScope($id: String!) { project(id: $id) { id name url } }",
            variables: { id: projectId },
          }),
          signal: AbortSignal.timeout(10000),
        }),
      );
      const p = data as {
        data?: { project?: { id?: string } };
        errors?: unknown;
      };
      result.linear = {
        connected: !p.errors && p.data?.project?.id === projectId,
        project: p.data?.project,
      };
    } catch {
      result.linear = {
        connected: false,
        reason: "Project access check failed",
      };
    }
  }
  return result;
}
