export function createLatestRequest<T>(options: {
  load: () => PromiseLike<T>;
  onData: (data: T) => void;
  onError: (error: unknown) => void;
}): { refresh(): Promise<void>; stop(): void };
