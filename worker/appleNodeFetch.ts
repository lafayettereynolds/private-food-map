import { Buffer } from 'node:buffer'

// Apple's Node SDK expects node-fetch v2's default export and Response.buffer().
// Workers' automatic node-fetch shim supplies neither contract consistently.
// Keep the native transport and all SDK OCSP verification, including failures.
const NativeHeaders = Headers
const NativeRequest = Request
const NativeResponse = Response
export { NativeHeaders as Headers, NativeRequest as Request, NativeResponse as Response }

type NodeFetchOptions = RequestInit & { timeout?: number }
export default async function appleNodeFetch(input: string | URL | Request, options: NodeFetchOptions = {}) {
  const { timeout, ...init } = options
  const deadline = timeout && timeout > 0 ? AbortSignal.timeout(timeout) : undefined
  const signal = deadline && init.signal ? AbortSignal.any([init.signal, deadline]) : deadline ?? init.signal
  const response = await globalThis.fetch(input, { ...init, signal })
  return Object.assign(response, { buffer: async () => Buffer.from(await response.arrayBuffer()) })
}
