import SwiftUI
import PhotosUI

struct PrivateDirectorySettingsView: View {
    @Environment(NativeAuthServices.self) private var auth
    @Environment(SyncCoordinator.self) private var sync
    @State private var data: PrivateDirectoryDashboard?
    @State private var selected: PrivateDirectoryDashboard.Entry?
    @State private var avatarEntry: PrivateDirectoryDashboard.Entry?
    @State private var photo: PhotosPickerItem?
    @State private var picking = false
    @State private var busy = false
    @State private var message: String?
    @State private var query = ""
    @State private var searchResults:[PrivateDirectoryDashboard.Person] = []

    var body: some View {
        List {
            Section {
                Text("私人头像和推荐来源归因仅自己可见。饭搭子关联需对方确认，不会自动复制或公开双方记录。")
                    .font(TasteMapDesignTokens.Typography.emptyMessage)
            }
            if let data {
                ForEach(["companion","source"],id:\.self) { kind in
                    Section(kind == "companion" ? "饭搭子 · 关联好友与头像" : "推荐来源 · 头像与用户关联") {
                        ForEach(data.entries.filter { $0.kind == kind }) { entry in
                            HStack(alignment:.top,spacing:TasteMapDesignTokens.Spacing.regular) {
                                DirectoryPrivateAvatar(entry:entry,owner:data.userID)
                                VStack(alignment:.leading) {
                                    Text(entry.displayName).font(.headline)
                                    Text(entry.linkedUserID == nil ? "未关联账号" : "已关联 Taste Map 用户").font(.caption).foregroundStyle(.secondary)
                                    Button("自定义头像") { avatarEntry=entry;picking=true }
                                    if entry.avatarURL != nil { Button("移除头像") { mutate(entry,action:"avatar") } }
                                    if entry.linkedUserID == nil {
                                        Button(kind == "companion" ? "关联好友" : "关联用户") { selected=entry;query="";searchResults=[] }
                                    } else if kind == "source" {
                                        Button("解除用户关联") { mutate(entry,action:"linkSource") }
                                    }
                                }
                            }.buttonStyle(.borderless).disabled(busy)
                        }
                        if !data.entries.contains(where:{$0.kind==kind}) {
                            Text("在到访中添加名称并同步后，即可在这里管理。").foregroundStyle(.secondary)
                        }
                    }
                }
                if !data.links.isEmpty {
                    Section("饭搭子关联请求") {
                        ForEach(uniqueLinks(data.links)) { link in
                            VStack(alignment:.leading) {
                                Text("\(link.companionDisplayName) · \(link.otherUser.displayName)")
                                if link.status == "accepted" {
                                    Button("解除关联") { respond(link.id,action:"unlink") }
                                } else if link.targetUserId == data.userID {
                                    Button("接受") { respond(link.id,action:"accept") }
                                    Button("拒绝") { respond(link.id,action:"reject") }
                                } else { Button("取消请求") { respond(link.id,action:"cancel") } }
                            }.disabled(busy)
                        }
                    }
                }
            }
            if busy { ProgressView("正在处理…") }
            if let message { Section { Text(message);Button("重试") { Task { await load() } }.disabled(busy) } }
        }
        .navigationTitle("饭搭子与推荐来源")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .onChange(of:auth.localAccountScope) { _,_ in data=nil;selected=nil;avatarEntry=nil;Task { await load() } }
        .photosPicker(isPresented:$picking,selection:$photo,matching:.images)
        .onChange(of:photo) { _,item in
            guard let item,let entry=avatarEntry,let owner=data?.userID else{return}
            Task {
                do {
                    guard let bytes=try await item.loadTransferable(type:Data.self),auth.localAccountScope == .authenticated(owner) else{return}
                    let encoded=try PrivateDirectoryAvatar.encoded(bytes)
                    await save(["kind":entry.kind,"id":entry.id,"action":"avatar","avatarData":encoded],owner:owner)
                } catch { message="无法读取头像，请换一张照片。" }
                photo=nil;avatarEntry=nil
            }
        }
        .sheet(item:$selected) { entry in
            NavigationStack {
                List {
                    Section("关联「\(entry.displayName)」") {
                        if entry.kind == "source" {
                            Button("搜索 Taste Map 用户") {
                                guard let owner=data?.userID else{return}
                                let searchedQuery=query
                                Task {
                                    do {
                                        let page=try await auth.socialAPI.search(query:searchedQuery,cursor:nil,limit:20)
                                        guard auth.localAccountScope == .authenticated(owner),selected?.id == entry.id,query==searchedQuery else{return}
                                        searchResults=page.items.map { .init(id:$0.profile.userId,displayName:$0.profile.displayName) }
                                    } catch { message="用户搜索暂时不可用。" }
                                }
                            }.disabled(query.trimmingCharacters(in:.whitespaces).count<2)
                        }
                        ForEach(people(kind:entry.kind)) { user in
                            Button(user.displayName) { selected=nil;mutate(entry,action:entry.kind == "companion" ? "linkCompanion":"linkSource",target:user.id) }
                        }
                        if data?.users.isEmpty != false && searchResults.isEmpty { Text("暂无互相关注的好友，请先在好友与关注中建立关系。推荐来源也可搜索其他用户。") }
                    }
                }.searchable(text:$query,prompt:"搜索好友")
                    .navigationTitle("选择 Taste Map 用户")
                    .toolbar { ToolbarItem(placement:.cancellationAction) { Button("取消") { selected=nil } } }
            }
        }
    }
    private func uniqueLinks(_ links:[CompanionLinkRequestV1])->[CompanionLinkRequestV1] {
        var seen=Set<String>();return links.filter { seen.insert($0.id).inserted }
    }
    private func people(kind:String)->[PrivateDirectoryDashboard.Person] {
        let local=data?.users.filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) } ?? []
        var seen=Set<String>()
        return (local + (kind == "source" ? searchResults : [])).filter { seen.insert($0.id).inserted }
    }
    private func mutate(_ entry:PrivateDirectoryDashboard.Entry,action:String,target:String?=nil) {
        guard let owner=data?.userID else{return}
        Task { await save(["kind":entry.kind,"id":entry.id,"action":action,"targetUserID":target as Any? ?? NSNull(),"avatarData":NSNull()],owner:owner) }
    }
    private func respond(_ id:String,action:String) {
        guard let owner=data?.userID,let escaped=id.addingPercentEncoding(withAllowedCharacters:.urlPathAllowed.subtracting(CharacterSet(charactersIn:"/?#%"))) else{return}
        Task { await save(["action":action],owner:owner,path:"/api/v1/social/companion-links/\(escaped)") }
    }
    @MainActor private func save(_ body:[String:Any],owner:String,path:String="/api/v1/directory") async {
        guard !busy,auth.localAccountScope == .authenticated(owner) else{return};busy=true
        do {
            _ = try await auth.premiumAPI.directoryRequest(path:path,body:JSONSerialization.data(withJSONObject:body))
            guard auth.localAccountScope == .authenticated(owner) else{busy=false;return}
            busy=false;await load()
        } catch { busy=false;message="未能保存，请检查网络、同步与双方关系。" }
    }
    @MainActor private func load() async {
        guard !busy else{return}
        guard case .authenticated(let owner)=auth.localAccountScope else{data=nil;message="请先登录。";return}
        busy=true;defer{busy=false}
        do {
            await sync.synchronizeNow()
            let result=try await auth.premiumAPI.directoryDashboard(userID:owner)
            guard auth.localAccountScope == .authenticated(owner) else{return}
            data=result;message=nil
        } catch { data=nil;message="资料暂时无法加载，请完成同步后重试。" }
    }
}

private struct DirectoryPrivateAvatar: View {
    @Environment(NativeAuthServices.self) private var auth
    let entry:PrivateDirectoryDashboard.Entry
    let owner:String
    @State private var image:UIImage?
    var body: some View {
        Group { if let image { Image(uiImage:image).resizable().scaledToFill() } else { Text(String(entry.displayName.prefix(1))) } }
            .frame(width:TasteMapDesignTokens.Avatar.standard,height:TasteMapDesignTokens.Avatar.standard)
            .clipShape(Circle()).overlay(Circle().stroke(.primary,lineWidth:TasteMapDesignTokens.Border.standard))
            .task(id:entry.avatarURL) {
                image=nil
                guard let url=entry.avatarURL,auth.localAccountScope == .authenticated(owner),
                      let bytes=try? await auth.premiumAPI.directoryRequest(path:url.components(separatedBy:"?")[0]),auth.localAccountScope == .authenticated(owner) else{return}
                image=UIImage(data:bytes)
            }
    }
}
