import production from '../ios/TasteMap/TasteMap/Configuration/ProductionEnvironment.json'

// Only the formal Browser origin can make cross-origin API calls. Native uses
// URLSession and does not need a wildcard or capacitor://localhost permission.
export async function withProductionCORS(request: Request, next: () => Promise<Response>): Promise<Response> {
  const url = new URL(request.url)
  const allowed = url.origin === production.apiBaseURL &&
    request.headers.get('Origin') === production.publicWebOrigin && url.pathname.startsWith('/api/')
  if (!allowed) return next()
  const requestedHeaders = (request.headers.get('Access-Control-Request-Headers') ?? '')
    .toLowerCase().split(',').map(value => value.trim()).filter(Boolean)
  const headers = new Headers({
    'Access-Control-Allow-Origin': production.publicWebOrigin,
    'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type, If-Match, X-Request-ID',
    'Vary': 'Origin',
  })
  if (request.method === 'OPTIONS') {
    if (requestedHeaders.some(value => !['authorization', 'content-type', 'if-match', 'x-request-id'].includes(value))) {
      return new Response(null, { status: 403 })
    }
    return new Response(null, { status: 204, headers })
  }
  const response = await next()
  const result = new Response(response.body, response)
  headers.forEach((value, key) => result.headers.set(key, value))
  return result
}
