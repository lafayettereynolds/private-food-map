export interface ReferralDashboardV1 {
  apiVersion: 1
  userID: string
  code: string
  inviteLink: string
  qualifiedCount: number
  maxQualified: 5
  earnedDays: number
  pendingDays: number
  records: Array<{id:string; status:'pending'|'qualified'|'capped'|'revoked';boundAt:string;qualifiedAt:string|null;revokedAt:string|null}>
}
export const referralStatusLabel = {pending:'等待首次有效到访',qualified:'邀请成功',capped:'已达 5 人上限',revoked:'已撤销'} as const
