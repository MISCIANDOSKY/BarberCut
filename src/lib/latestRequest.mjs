// Only the newest request may publish a result. Disposed views ignore late replies.
export function createLatestRequest({ load, onData, onError }) {
  let version = 0;
  let stopped = false;
  return {
    async refresh() {
      if (stopped) return;
      const request = ++version;
      try {
        const data = await load();
        if (!stopped && request === version) onData(data);
      } catch (error) {
        if (!stopped && request === version) onError(error);
      }
    },
    stop() {
      stopped = true;
      version++;
    },
  };
}
