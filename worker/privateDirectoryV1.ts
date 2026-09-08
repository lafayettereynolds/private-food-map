import { handleSocialCollaborationV1, SocialCollaborationV1Error } from './socialCollaborationV1'

const tables = { companion: ['dining_companions','owner_user_id'], source: ['recommendation_sources','user_id'] } as const
type Kind = keyof typeof tables
const rejected = () => new SocialCollaborationV1Error('记录不存在、权限已变化或输入无效，请刷新后重试。', 403)
export async function handlePrivateDirectoryV1(request: Request, db: D1Database, owner: string) {
  const url = new URL(request.url)
  if (request.method === 'GET') {
    const rows = []
    for (const kind of ['companion','source'] as const) {
      const [table,column] = tables[kind]
      const result = await db.prepare(`SELECT d.id,d.display_name,d.linked_user_id,p.updated_at AS avatar_revision
        FROM ${table} d LEFT JOIN private_directory_profiles p ON p.entity_id=d.id AND p.user_id=? AND p.kind=? AND p.avatar_data IS NOT NULL
        WHERE d.${column}=? AND d.deleted_at IS NULL ORDER BY d.display_name,d.id`).bind(owner,kind,owner).all<{id:string;display_name:string;linked_user_id:string|null;avatar_revision:string|null}>()
      rows.push(...result.results.map(r=>({id:r.id,kind,displayName:r.display_name,linkedUserID:r.linked_user_id,
        avatarURL:r.avatar_revision?`/api/v1/directory/avatar/${kind}/${encodeURIComponent(r.id)}?revision=${encodeURIComponent(r.avatar_revision)}`:null})))
    }
    const users = await db.prepare(`SELECT p.user_id AS id,p.display_name AS displayName FROM user_profiles p JOIN users u ON u.id=p.user_id
      WHERE u.deleted_at IS NULL AND p.deleted_at IS NULL AND p.user_id<>?
      AND EXISTS(SELECT 1 FROM follows a JOIN follows b ON b.follower_id=a.followed_user_id AND b.followed_user_id=a.follower_id
        WHERE a.follower_id=? AND a.followed_user_id=p.user_id AND a.deleted_at IS NULL AND b.deleted_at IS NULL)
      AND NOT EXISTS(SELECT 1 FROM user_blocks x WHERE x.deleted_at IS NULL AND
        ((x.blocker_user_id=? AND x.blocked_user_id=p.user_id) OR (x.blocker_user_id=p.user_id AND x.blocked_user_id=?)))
      ORDER BY p.display_name,p.user_id`).bind(owner,owner,owner,owner).all()
    const linkItems:unknown[]=[]
    for(const scope of ['incoming','outgoing','active']) {
      let cursor:string|null=null
      const seen=new Set<string>()
      do {
        const page=await handleSocialCollaborationV1(new Request(`${url.origin}/api/v1/social/companion-links?scope=${scope}&limit=50${cursor?'&cursor='+encodeURIComponent(cursor):''}`),db,owner)
        if(!('items' in page)) throw rejected()
        linkItems.push(...page.items)
        cursor='nextCursor' in page && typeof page.nextCursor==='string'?page.nextCursor:null
        if(cursor && seen.has(cursor)) throw rejected()
        if(cursor) seen.add(cursor)
      } while(cursor)
    }
    return {apiVersion:1,userID:owner,entries:rows,users:users.results,links:linkItems}
  }
  if (request.method !== 'POST' || Number(request.headers.get('content-length') ?? 0)>100_000) throw rejected()
  const raw = await request.text()
  if (raw.length>100_000) throw rejected()
  let body:Record<string,unknown>
  try { body=JSON.parse(raw); if(!body || Array.isArray(body) || typeof body!=='object') throw rejected() } catch { throw rejected() }
  const kind=body.kind as Kind, id=body.id
  if (!Object.hasOwn(tables,kind) || typeof id!=='string' || id.length>200) throw rejected()
  const [table,column]=tables[kind]
  const entity=await db.prepare(`SELECT id FROM ${table} WHERE id=? AND ${column}=? AND deleted_at IS NULL`).bind(id,owner).first()
  if (!entity) throw rejected()
  if(body.action==='linkCompanion' && kind==='companion') {
    return handleSocialCollaborationV1(new Request(`${url.origin}/api/v1/social/companion-links`,{method:'POST',body:JSON.stringify({companionId:id,targetUserId:body.targetUserID})}),db,owner)
  }
  const now=new Date().toISOString(), statements:D1PreparedStatement[]=[]
  if(body.action==='avatar') {
    const data=body.avatarData
    if(data!==null && (typeof data!=='string' || data.length>90_000 || !/^data:image\/jpeg;base64,\/9j\/[A-Za-z0-9+/=]+$/.test(data))) throw rejected()
    statements.push(db.prepare(`INSERT INTO private_directory_profiles(user_id,kind,entity_id,avatar_data,updated_at) VALUES(?,?,?,?,?)
      ON CONFLICT(user_id,kind,entity_id) DO UPDATE SET avatar_data=excluded.avatar_data,updated_at=excluded.updated_at`).bind(owner,kind,id,data,now))
  } else if(body.action==='linkSource' && kind==='source') {
    const target=body.targetUserID
    if(target!==null) {
      if(typeof target!=='string'||target===owner) throw rejected()
      const valid=await db.prepare(`SELECT p.user_id FROM user_profiles p JOIN users u ON u.id=p.user_id WHERE p.user_id=?
        AND p.deleted_at IS NULL AND u.deleted_at IS NULL
        AND (p.visibility='public' OR EXISTS(SELECT 1 FROM follows a JOIN follows b ON b.follower_id=a.followed_user_id AND b.followed_user_id=a.follower_id
          WHERE a.follower_id=? AND a.followed_user_id=p.user_id AND a.deleted_at IS NULL AND b.deleted_at IS NULL))
        AND NOT EXISTS(SELECT 1 FROM user_blocks x WHERE x.deleted_at IS NULL AND
          ((x.blocker_user_id=? AND x.blocked_user_id=p.user_id) OR (x.blocker_user_id=p.user_id AND x.blocked_user_id=?)))`).bind(target,owner,owner,owner).first()
      if(!valid) throw rejected()
    }
    const mutation=`directory:${crypto.randomUUID()}`
    statements.push(db.prepare(`UPDATE recommendation_sources SET linked_user_id=?,updated_at=?,server_version=server_version+1,last_mutation_id=? WHERE id=? AND user_id=?`).bind(target,now,mutation,id,owner),
      db.prepare(`INSERT INTO sync_change_log_v6(user_id,entity_type,entity_id,operation,server_version,mutation_id,changed_at)
        SELECT user_id,'recommendationSource',id,'upsert',server_version,?,? FROM recommendation_sources WHERE id=? AND user_id=?`).bind(mutation,now,id,owner))
  } else throw rejected()
  statements.push(db.prepare('INSERT INTO private_directory_audit(user_id,kind,entity_id,action,target_user_id,created_at) VALUES(?,?,?,?,?,?)')
    .bind(owner,kind,id,body.action,typeof body.targetUserID==='string'?body.targetUserID:null,now))
  await db.batch(statements)
  return {apiVersion:1,userID:owner,saved:true}
}
export async function privateDirectoryAvatar(db:D1Database,owner:string,kind:string,id:string) {
  if(!Object.hasOwn(tables,kind)) throw rejected()
  const [table,column]=tables[kind as Kind]
  const row=await db.prepare(`SELECT p.avatar_data FROM private_directory_profiles p JOIN ${table} d ON d.id=p.entity_id
    WHERE p.user_id=? AND p.kind=? AND p.entity_id=? AND d.${column}=? AND d.deleted_at IS NULL`).bind(owner,kind,id,owner).first<{avatar_data:string|null}>()
  if(!row?.avatar_data) throw rejected()
  return new Response(Uint8Array.from(atob(row.avatar_data.split(',')[1]),x=>x.charCodeAt(0)),{headers:{'Content-Type':'image/jpeg','Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff'}})
}
