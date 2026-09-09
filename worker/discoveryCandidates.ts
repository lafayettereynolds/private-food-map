/** Candidate narrowing only. Authorization and ranking remain in the readers.
 * Always return the complete candidate set; city size is not an availability gate.
 * Request-local IDs are not cached across owners or permission changes. */
export async function discoveryRestaurantCandidates(
  database: D1Database, viewerID: string, city: string,
  options: { visitOwners?: string[]; restaurantOwners?: string[]; includeCity?: boolean; includeOwnWants?: boolean } = {},
): Promise<string[]> {
  const trimmed = city.trim()
  const normalized = trimmed.length > 2 && trimmed.endsWith('市') ? trimmed.slice(0, -1) : trimmed
  const branches: string[] = []
  const bindings: unknown[] = []
  if (options.includeCity !== false) {
    branches.push(`SELECT id FROM restaurants INDEXED BY idx_restaurants_discovery_trimmed_city WHERE deleted_at IS NULL
      AND COALESCE(is_test_data,0)=0 AND TRIM(city) IN (?, ?)`)
    bindings.push(normalized, `${normalized}市`)
  }
  const owners = options.restaurantOwners ?? [viewerID]
  branches.push(`SELECT id FROM restaurants INDEXED BY idx_restaurants_user WHERE deleted_at IS NULL
    AND COALESCE(is_test_data,0)=0 AND user_id IN (SELECT value FROM json_each(?))`)
  bindings.push(JSON.stringify(owners))
  if (options.visitOwners) {
    branches.push(`SELECT restaurant_id AS id FROM visits INDEXED BY idx_visits_user WHERE user_id IN (SELECT value FROM json_each(?))
      AND deleted_at IS NULL AND COALESCE(is_test_data,0)=0`)
    bindings.push(JSON.stringify(options.visitOwners))
  }
  if (options.includeOwnWants) {
    branches.push(`SELECT restaurant_id AS id FROM want_to_go WHERE user_id=?
      AND deleted_at IS NULL AND COALESCE(is_test_data,0)=0`)
    bindings.push(viewerID)
  }
  const result = await database.prepare(branches.join(' UNION '))
    .bind(...bindings).all<{id:string}>()
  return result.results.map(row => row.id)
}
