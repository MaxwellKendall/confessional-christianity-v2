// The handful of GitHub REST calls /admin needs to turn a save into a commit
// on a review branch with an open pull request. Plain fetch, no Octokit — the
// surface is six endpoints. Server-only: GITHUB_TOKEN must never reach the
// browser.

export interface GitHubConfig {
  token: string;
  owner: string;
  repo: string;
  baseBranch: string;
}

export const githubConfig = (env: NodeJS.ProcessEnv = process.env): GitHubConfig | null => {
  const [owner, repo] = (env.ADMIN_GITHUB_REPO ?? '').split('/');
  if (!env.ADMIN_GITHUB_TOKEN || !owner || !repo) return null;
  return {
    token: env.ADMIN_GITHUB_TOKEN,
    owner,
    repo,
    baseBranch: env.ADMIN_GITHUB_BASE_BRANCH || 'main',
  };
};

export class GitHubError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

export interface PullRequest {
  number: number;
  url: string;
  branch: string;
}

export const createGitHubClient = (config: GitHubConfig) => {
  const { token, owner, repo, baseBranch } = config;

  const request = async <T>(method: string, path: string, body?: unknown): Promise<T> => {
    const response = await fetch(`https://api.github.com/repos/${owner}/${repo}${path}`, {
      method,
      headers: {
        Accept: 'application/vnd.github+json',
        Authorization: `Bearer ${token}`,
        'X-GitHub-Api-Version': '2022-11-28',
        ...(body ? { 'Content-Type': 'application/json' } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
      cache: 'no-store',
    });
    if (!response.ok) {
      const detail = await response.text().catch(() => '');
      throw new GitHubError(response.status, `GitHub ${method} ${path} failed (${response.status}): ${detail.slice(0, 300)}`);
    }
    return response.status === 204 ? (undefined as T) : (response.json() as Promise<T>);
  };

  const encodePath = (path: string) => path.split('/').map(encodeURIComponent).join('/');

  /** A file's UTF-8 text at `ref`, or null when it doesn't exist there. */
  const readFile = async (path: string, ref = baseBranch): Promise<string | null> => {
    try {
      const file = await request<{ content: string; encoding: string }>(
        'GET', `/contents/${encodePath(path)}?ref=${encodeURIComponent(ref)}`,
      );
      return Buffer.from(file.content, file.encoding as BufferEncoding).toString('utf8');
    } catch (error) {
      if (error instanceof GitHubError && error.status === 404) return null;
      throw error;
    }
  };

  /** The names of the files directly inside `dir` at `ref`. */
  const listDirectory = async (dir: string, ref = baseBranch): Promise<string[]> => {
    const entries = await request<{ name: string; type: string }[]>(
      'GET', `/contents/${encodePath(dir)}?ref=${encodeURIComponent(ref)}`,
    );
    return entries.filter((e) => e.type === 'file').map((e) => e.name);
  };

  const branchSha = async (branch: string): Promise<string | null> => {
    try {
      const ref = await request<{ object: { sha: string } }>('GET', `/git/ref/heads/${encodePath(branch)}`);
      return ref.object.sha;
    } catch (error) {
      if (error instanceof GitHubError && error.status === 404) return null;
      throw error;
    }
  };

  /** Open PRs into the base branch whose head branch starts with `prefix`. */
  const openPullRequests = async (prefix: string): Promise<PullRequest[]> => {
    const pulls = await request<{ number: number; html_url: string; head: { ref: string; repo: { full_name: string } | null } }[]>(
      'GET', `/pulls?state=open&base=${encodeURIComponent(baseBranch)}&per_page=100`,
    );
    return pulls
      .filter((p) => p.head.ref.startsWith(prefix) && p.head.repo?.full_name === `${owner}/${repo}`)
      .map((p) => ({ number: p.number, url: p.html_url, branch: p.head.ref }));
  };

  /** Commits `files` onto `branch` as one commit. When `restart` is set (or
   * the branch doesn't exist) the branch is first pointed at the base
   * branch's head, so a review branch whose PR already merged or closed
   * starts clean instead of carrying stale history. */
  const commitFiles = async (
    branch: string,
    files: { path: string; content: string }[],
    message: string,
    { restart }: { restart: boolean },
  ): Promise<string> => {
    const existing = await branchSha(branch);
    const parent = restart || !existing ? await branchSha(baseBranch) : existing;
    if (!parent) throw new Error(`base branch "${baseBranch}" not found`);

    const parentCommit = await request<{ tree: { sha: string } }>('GET', `/git/commits/${parent}`);
    const tree = await request<{ sha: string }>('POST', '/git/trees', {
      base_tree: parentCommit.tree.sha,
      tree: files.map((f) => ({ path: f.path, mode: '100644', type: 'blob', content: f.content })),
    });
    const commit = await request<{ sha: string }>('POST', '/git/commits', {
      message, tree: tree.sha, parents: [parent],
    });
    if (existing) {
      await request('PATCH', `/git/refs/heads/${encodePath(branch)}`, { sha: commit.sha, force: true });
    } else {
      await request('POST', '/git/refs', { ref: `refs/heads/${branch}`, sha: commit.sha });
    }
    return commit.sha;
  };

  const openPullRequest = async (branch: string, title: string, body: string): Promise<PullRequest> => {
    const pull = await request<{ number: number; html_url: string }>('POST', '/pulls', {
      title, body, head: branch, base: baseBranch,
    });
    return { number: pull.number, url: pull.html_url, branch };
  };

  return { config, readFile, listDirectory, openPullRequests, commitFiles, openPullRequest };
};

export type GitHubClient = ReturnType<typeof createGitHubClient>;
