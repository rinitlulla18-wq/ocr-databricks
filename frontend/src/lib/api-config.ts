function getApiBaseUrls(): string[] {
  if (process.env.NEXT_PUBLIC_API_URL) {
    return [process.env.NEXT_PUBLIC_API_URL];
  }
  if (typeof window !== "undefined") {
    // In Databricks Apps, frontend and backend share the same origin
    // In local dev (port 3000), we need to hit the backend on port 8000
    const origin = window.location.origin;
    return origin.includes(":3000") ? ["http://localhost:8000"] : [origin, "http://localhost:8000"];
  }
  return ["http://localhost:8000"];
}

const API_BASE_URLS = getApiBaseUrls();

export async function apiCall(
  path: string,
  options?: RequestInit
): Promise<unknown> {
  const urls = path.startsWith("http")
    ? [path]
    : [...new Set(API_BASE_URLS.map((base) => `${base}${path}`))];

  let lastError: Error | null = null;

  for (const url of urls) {
    try {
      const response = await fetch(url, options);
      if (!response.ok) {
        const text = await response.text();
        throw new Error(`HTTP ${response.status}: ${text}`);
      }
      return response.json();
    } catch (err) {
      lastError = err instanceof Error ? err : new Error(String(err));
    }
  }

  throw lastError ?? new Error(`All API URLs failed for ${path}`);
}
