export function renderMessage(message: string): void {
  const target = document.querySelector('#message');
  if (target) {
    target.innerHTML = message;
  }
}

export function createRequestId(): string {
  return `${Date.now()}-${Math.random()}`;
}
