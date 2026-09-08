export interface PrivateDirectoryEntry {
  id:string
  kind:'companion'|'source'
  displayName:string
  linkedUserID:string|null
  avatarURL:string|null
}
export interface PrivateDirectoryDashboard {
  apiVersion:1
  userID:string
  entries:PrivateDirectoryEntry[]
  users:Array<{id:string;displayName:string}>
  links:Array<{id:string;companionId:string;companionDisplayName:string;requesterUserId:string;targetUserId:string;status:string;otherUser:{displayName:string}}>
}
export interface PrivateDirectoryMutation {
  kind:'companion'|'source'
  id:string
  action:'avatar'|'linkSource'|'linkCompanion'
  targetUserID?:string|null
  photoID?:string|null
}
