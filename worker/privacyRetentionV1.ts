import { PRIVACY_RETENTION, retentionCutoff } from './privacyRetentionPolicy'

// Preserve IDs, foreign keys, versions and deletion time: these are the minimal
// synchronization tombstone, not the deleted restaurant/visit payload.
const REDACTIONS: Record<string, string> = {
  restaurants: "amap_poi_id='', name='Deleted', address='', city='', latitude=0, longitude=0, status='visited', preference_level='normal', marker_type='emoji', overall_rating=NULL, food_rating=NULL, environment_rating=NULL, service_rating=NULL, value_rating=NULL, tags_json='[]', long_term_note='', price_per_person=NULL, merchant_image_url=NULL, marker_emoji='🍽️', marker_photo_id=NULL, phone=NULL, opening_hours=NULL, website_url=NULL",
  visits: "visited_at='1970-01-01T00:00:00.000Z', rating=NULL, total_price=NULL, price_per_person=NULL, party_size=1, party_size_optional=NULL, queue_duration=NULL, companions_json='[]', dishes_json='[]', note='', photo_ids_json='[]', visibility='private', dining_mode='dine_in', payment_mode=NULL, recommendation_source_type=NULL, my_actual_spend=NULL, dining_occasion=NULL, value_rating=NULL, environment_rating=NULL, service_rating=NULL, noise_level=NULL, dining_duration=NULL, portion_level=NULL, transport_convenience=NULL, special_notes='', recommendation_source_user_id=NULL, recommendation_source_text='', value_tags_json='[]', environment_tags_json='[]', service_tags_json='[]', dining_occasion_text='', dining_occasions_json='[]', companion_ids_json='[]'",
  dishes: "name='Deleted', taste='', rating=NULL, price=NULL, photo_id=NULL",
  photos: "file_name=NULL, drive_account_id='', drive_file_id='', file_size=0, thumbnail_file_size=NULL, width=NULL, height=NULL, visibility='private', storage_key='', thumbnail_storage_key=''",
  companion_link_requests: "companion_display_name='Deleted'",
  shared_meals: "occurred_at='1970-01-01T00:00:00.000Z', visibility='private'",
  dining_companions: "display_name='Deleted', normalized_name='Deleted', linked_user_id=NULL",
  recommendation_sources: "display_name='Deleted', normalized_name='Deleted', linked_user_id=NULL",
  restaurant_lists: "title='Deleted', description='', visibility='private', custom_cover_photo_id=NULL",
  restaurant_list_items: "note='', restaurant_snapshot_json=NULL, restaurant_global_key=''",
  content_comments: "body='[deleted]'",
  user_profiles: "display_name='Deleted user', bio='', city='', avatar_photo_id=NULL, avatar_preset_id='polar-bear', visibility='private'",
}

export async function runPrivacyRetention(database: D1Database, bucket: R2Bucket | undefined, now = new Date()) {
  const cutoff = retentionCutoff(now, PRIVACY_RETENTION.recordContentDays)
  // No object metadata is erased before its physical binaries have been removed.
  const photos = await database.prepare(`SELECT id,user_id,storage_key,thumbnail_storage_key FROM photos
    WHERE deleted_at<=? AND (COALESCE(storage_key,'')<>'' OR COALESCE(thumbnail_storage_key,'')<>'') LIMIT ?`)
    .bind(cutoff, PRIVACY_RETENTION.objectBatch).all<{id:string;user_id:string;storage_key:string|null;thumbnail_storage_key:string|null}>()
  for (const photo of photos.results) {
    if (!bucket) throw new Error('retention_photo_storage_unavailable')
    const prefix = `users/${photo.user_id}/photos/`
    const keys = [photo.storage_key, photo.thumbnail_storage_key].filter((key): key is string => Boolean(key))
    if (keys.some(key => !key.startsWith(prefix))) throw new Error('retention_object_owner_mismatch')
    await bucket.delete(keys)
    await database.prepare("UPDATE photos SET storage_key='',thumbnail_storage_key='' WHERE id=? AND user_id=? AND deleted_at<=?")
      .bind(photo.id, photo.user_id, cutoff).run()
  }
  for (const [table, assignments] of Object.entries(REDACTIONS)) {
    const condition = table === 'photos' ? " AND COALESCE(storage_key,'')='' AND COALESCE(thumbnail_storage_key,'')=''" : ''
    const alreadyCleared = assignments.split(',').map(assignment => assignment.replace('=', ' IS ')).join(' AND ')
    await database.prepare(`UPDATE ${table} SET ${assignments} WHERE rowid IN
      (SELECT rowid FROM ${table} WHERE deleted_at<=?${condition} AND NOT (${alreadyCleared}) LIMIT ?)`)
      .bind(cutoff,PRIVACY_RETENTION.recordBatch).run()
  }
  await database.prepare(`DELETE FROM restaurant_place_identities WHERE restaurant_id IN
    (SELECT id FROM restaurants WHERE deleted_at<=?)`).bind(cutoff).run()
  await database.prepare(`DELETE FROM private_directory_profiles WHERE user_id IN
    (SELECT id FROM users WHERE deleted_at<=?) OR
    (kind='companion' AND entity_id IN (SELECT id FROM dining_companions WHERE deleted_at<=?)) OR
    (kind='source' AND entity_id IN (SELECT id FROM recommendation_sources WHERE deleted_at<=?))`).bind(cutoff,cutoff,cutoff).run()
  const securityCutoff = retentionCutoff(now, PRIVACY_RETENTION.securityDays)
  for (const [table, column] of [['private_directory_audit','created_at'],['content_reports','updated_at'],['recommendation_events','created_at'],['recommendation_preference_events','received_at']] as const) {
    await database.prepare(`DELETE FROM ${table} WHERE ${column}<=? AND ${table === 'content_reports' ? 'reporter_user_id' : 'user_id'} IN (SELECT id FROM users WHERE deleted_at IS NOT NULL)`).bind(securityCutoff).run()
  }
  await database.prepare('DELETE FROM auth_refresh_token_history WHERE session_id IN (SELECT id FROM auth_sessions WHERE revoked_at<=?)').bind(securityCutoff).run()
  await database.prepare('DELETE FROM auth_sessions WHERE revoked_at<=?').bind(securityCutoff).run()
  await database.prepare('DELETE FROM auth_challenges WHERE expires_at<=?').bind(securityCutoff).run()
  await database.prepare('DELETE FROM auth_identity_token_uses WHERE used_at<=?').bind(securityCutoff).run()
  await database.prepare('DELETE FROM public_api_rate_limits WHERE window_started_at<=?').bind(securityCutoff).run()
  const commerceCutoff = retentionCutoff(now, PRIVACY_RETENTION.commerceDays)
  // Only closed accounts. Keep an active transaction and its owner proof until
  // 365 days after the later of account closure and the transaction's end.
  const closed = 'user_id IN (SELECT id FROM users WHERE deleted_at<=?)'
  const ended = "COALESCE(revocation_at,expires_at,updated_at)<=? AND MAX(updated_at,verified_at)<=?"
  await database.batch([
    database.prepare('INSERT INTO privacy_purge_authorization(id,cutoff) VALUES(1,?)').bind(commerceCutoff),
    database.prepare(`DELETE FROM app_store_verification_audit WHERE (environment,transaction_id) IN
      (SELECT environment,transaction_id FROM app_store_transactions_v2 WHERE ${closed} AND ${ended})`).bind(commerceCutoff,commerceCutoff,commerceCutoff),
    database.prepare(`DELETE FROM app_store_transactions_v2 WHERE ${closed} AND ${ended}`).bind(commerceCutoff,commerceCutoff,commerceCutoff),
    database.prepare(`DELETE FROM app_store_transactions WHERE ${closed} AND ${ended}`).bind(commerceCutoff,commerceCutoff,commerceCutoff),
    database.prepare(`DELETE FROM app_store_owners_v2 WHERE ${closed} AND NOT EXISTS
      (SELECT 1 FROM app_store_transactions_v2 t WHERE t.environment=app_store_owners_v2.environment AND t.original_transaction_id=app_store_owners_v2.original_transaction_id)`).bind(commerceCutoff),
    database.prepare(`DELETE FROM app_store_subscription_owners WHERE ${closed} AND NOT EXISTS
      (SELECT 1 FROM app_store_transactions t WHERE t.original_transaction_id=app_store_subscription_owners.original_transaction_id)`).bind(commerceCutoff),
    database.prepare(`DELETE FROM app_store_accounts WHERE ${closed} AND NOT EXISTS
      (SELECT 1 FROM app_store_owners_v2 o WHERE o.user_id=app_store_accounts.user_id) AND NOT EXISTS
      (SELECT 1 FROM app_store_subscription_owners o WHERE o.user_id=app_store_accounts.user_id)`).bind(commerceCutoff),
    database.prepare('DELETE FROM privacy_purge_authorization WHERE id=1'),
  ])
  for (const [table,date] of [['app_store_notification_events','processed_at'],['app_store_notification_events_v2','processed_at'],['membership_audit_log','created_at'],['referral_audit_log','created_at']] as const) {
    await database.batch([
      database.prepare('INSERT INTO privacy_purge_authorization(id,cutoff) VALUES(1,?)').bind(commerceCutoff),
      database.prepare(`DELETE FROM ${table} WHERE ${date}<=?${table === 'membership_audit_log' ? ' AND target_user_id IN (SELECT id FROM users WHERE deleted_at IS NOT NULL)' : table === 'referral_audit_log' ? ' AND user_id IN (SELECT id FROM users WHERE deleted_at<=?)' : ''}`).bind(...(table === 'referral_audit_log' ? [commerceCutoff,commerceCutoff] : [commerceCutoff])),
      database.prepare('DELETE FROM privacy_purge_authorization WHERE id=1'),
    ])
  }
  const accounts = await database.prepare(`SELECT u.id FROM users u LEFT JOIN privacy_retention_attempts p ON p.user_id=u.id WHERE u.deleted_at<=? ORDER BY COALESCE(p.attempted_at,''),u.deleted_at LIMIT ?`)
    .bind(commerceCutoff,PRIVACY_RETENTION.jobBatch).all<{id:string}>()
  for (const account of accounts.results) {
    await database.prepare('INSERT INTO privacy_retention_attempts(user_id,attempted_at) VALUES (?,?) ON CONFLICT(user_id) DO UPDATE SET attempted_at=excluded.attempted_at').bind(account.id,now.toISOString()).run()
    await purgeClosedAccount(database, account.id, commerceCutoff)
  }
}

async function purgeClosedAccount(db: D1Database, id: string, cutoff: string) {
  // Other users' still-effective rewards must not disappear with their inviter.
  // Dependency retention has an explicit end: related benefit end + 365 days.
  const dependency = await db.prepare(`SELECT 1 AS held FROM premium_rewards WHERE
    user_id<>? AND invitee_id IN (SELECT invitee_id FROM referrals WHERE referrer_id=? OR invitee_id=?)
    AND (state IN ('pending','lifetime') OR COALESCE(revoked_at,expires_at,changed_at,granted_at)>?) LIMIT 1`)
    .bind(id,id,id,cutoff).first()
  const commerce = await db.prepare('SELECT 1 FROM app_store_accounts WHERE user_id=?').bind(id).first()
  const recentAudit = await db.prepare(`SELECT 1 FROM membership_audit_log WHERE target_user_id=? AND created_at>?
    UNION ALL SELECT 1 FROM referral_audit_log WHERE user_id=? AND created_at>? LIMIT 1`).bind(id,cutoff,id,cutoff).first()
  if (dependency || commerce || recentAudit) return
  const statements: D1PreparedStatement[] = []
  const add = (sql: string, ...args: (string|number)[]) => statements.push(db.prepare(sql).bind(...args))
  add('INSERT INTO privacy_purge_authorization(id,cutoff) VALUES(1,?)',cutoff)
  add('DELETE FROM sandbox_offer_assignments WHERE reward_id IN (SELECT id FROM premium_rewards WHERE user_id=? OR invitee_id IN (SELECT invitee_id FROM referrals WHERE referrer_id=? OR invitee_id=?))',id,id,id)
  add('DELETE FROM premium_rewards WHERE user_id=? OR invitee_id IN (SELECT invitee_id FROM referrals WHERE referrer_id=? OR invitee_id=?)',id,id,id)
  add('DELETE FROM referrals WHERE referrer_id=? OR invitee_id=?',id,id)
  add('DELETE FROM referral_codes WHERE user_id=?',id)
  add('DELETE FROM shared_meal_participants WHERE user_id=? OR shared_meal_id IN (SELECT id FROM shared_meals WHERE created_by_user_id=?)',id,id)
  add('DELETE FROM shared_meals WHERE created_by_user_id=?',id)
  add('DELETE FROM companion_link_requests WHERE requester_user_id=? OR target_user_id=?',id,id)
  for (const [table,a,b] of [['friendships','requester_id','addressee_id'],['follows','follower_id','followed_user_id'],['user_blocks','blocker_user_id','blocked_user_id']] as const) add(`DELETE FROM ${table} WHERE ${a}=? OR ${b}=?`,id,id)
  for (const version of ['', '_v2','_v3','_v4','_v5','_v6']) {
    add(`DELETE FROM sync_mutation_receipts${version} WHERE user_id=?`,id)
    add(`DELETE FROM sync_change_log${version} WHERE user_id=?`,id)
  }
  for (const table of ['private_directory_profiles','restaurant_list_items','restaurant_lists','visit_dishes','photos','dishes','want_to_go','visits','restaurant_place_identities','restaurants','recommendation_sources','user_profiles','content_comments','content_likes','discovery_rate_limits','social_search_rate_limits','membership_entitlements','sandbox_membership_entitlements']) add(`DELETE FROM ${table} WHERE user_id=?`,id)
  add('DELETE FROM dining_companions WHERE owner_user_id=?',id)
  add('DELETE FROM public_share_links WHERE owner_user_id=?',id)
  add('DELETE FROM account_deletion_objects WHERE job_id IN (SELECT id FROM account_deletion_jobs WHERE user_id=? AND status=\'completed\')',id)
  add("DELETE FROM account_deletion_jobs WHERE user_id=? AND status='completed'",id)
  add('DELETE FROM privacy_retention_attempts WHERE user_id=?',id)
  // Revoked sessions and Apple identity mappings are already gone. A new Apple
  // sign-in gets a new random account ID, so an old device cannot restore this ID.
  add('DELETE FROM users WHERE id=?',id)
  add('DELETE FROM privacy_purge_authorization WHERE id=1')
  await db.batch(statements)
}
