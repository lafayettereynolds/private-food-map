#if DEBUG
import SwiftUI

/// DEBUG-only, candidate-branch-only visual approval surfaces.
///
/// These pages intentionally do not replace the shipping product. They let
/// Lafayette inspect a runnable Legacy-base + Current-capability composition
/// before any design decision is approved or merged.
enum FuseVisualCandidateKind: String, CaseIterable {
    case profile
    case visitEditor = "visit-editor"
    case dishPhoto = "dish-photo"
    case publicProfile = "public-profile"
    case lists
    case analyticsCompanion = "analytics-companion"
    case analyticsSource = "analytics-source"
    case analyticsMonthly = "analytics-monthly"
    case analyticsAnnual = "analytics-annual"
    case posterTaste = "poster-taste"
    case posterTasteB = "poster-taste-b"
    case posterCompanion = "poster-companion"
    case posterCompanionB = "poster-companion-b"
    case posterSource = "poster-source"
    case posterSourceB = "poster-source-b"
    case posterMonthly = "poster-monthly"
    case posterMonthlyB = "poster-monthly-b"
    case posterAnnual = "poster-annual"
    case posterAnnualB = "poster-annual-b"
    case paywall
    case settings
}

enum FuseVisualCandidateRuntime {
    static let argument = "-fuse-candidate"

    static var current: FuseVisualCandidateKind? {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: argument), arguments.indices.contains(index + 1) {
            return FuseVisualCandidateKind(rawValue: arguments[index + 1])
        }
        if let argument = arguments.first(where: { $0.hasPrefix("\(argument)=") }) {
            return FuseVisualCandidateKind(rawValue: String(argument.dropFirst(argument.count + 1)))
        }
        return nil
    }
}

struct FuseVisualCandidateHost: View {
    let kind: FuseVisualCandidateKind

    var body: some View {
        Group {
            switch kind {
            case .profile: FuseProfileCandidate()
            case .visitEditor: FuseVisitEditorCandidate()
            case .dishPhoto: FuseDishPhotoCandidate()
            case .publicProfile: FusePublicProfileCandidate()
            case .lists: FuseListsCandidate()
            case .analyticsCompanion: FuseAnalysisCandidate(kind: .companion)
            case .analyticsSource: FuseAnalysisCandidate(kind: .source)
            case .analyticsMonthly: FuseAnalysisCandidate(kind: .monthly)
            case .analyticsAnnual: FuseAnalysisCandidate(kind: .annual)
            case .posterTaste: FusePosterCandidate(kind: .taste, style: .storyMap)
            case .posterTasteB: FusePosterCandidate(kind: .taste, style: .editorial)
            case .posterCompanion: FusePosterCandidate(kind: .companion, style: .storyMap)
            case .posterCompanionB: FusePosterCandidate(kind: .companion, style: .editorial)
            case .posterSource: FusePosterCandidate(kind: .source, style: .storyMap)
            case .posterSourceB: FusePosterCandidate(kind: .source, style: .editorial)
            case .posterMonthly: FusePosterCandidate(kind: .monthly, style: .storyMap)
            case .posterMonthlyB: FusePosterCandidate(kind: .monthly, style: .editorial)
            case .posterAnnual: FusePosterCandidate(kind: .annual, style: .storyMap)
            case .posterAnnualB: FusePosterCandidate(kind: .annual, style: .editorial)
            case .paywall: FusePaywallCandidate()
            case .settings: FuseSettingsCandidate()
            }
        }
        .environment(\.colorScheme, .light)
    }
}

private enum FuseFixture {
    static let name = "Lafayette"
    static let joined = "加入 Taste Map 842 天"
    static let visited = "96"
    static let want = "24"
    static let spending = "¥36,842"
    static let following = "38"
    static let followers = "126"

    static let restaurants = [
        ("鮨一", "杭州 · 日料", "4.8", "FoodHeroJapanese"),
        ("山野火锅", "杭州 · 火锅", "4.7", "FoodHeroHotpotGrill"),
        ("湖畔牛排馆", "上海 · 西餐", "4.6", "FoodHeroWestern"),
    ]
}

private struct FusePage<Content: View>: View {
    let title: String
    let subtitle: String?
    let badge: String
    @ViewBuilder var content: Content

    init(_ title: String, subtitle: String? = nil, badge: String = "FUSE V1", @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TasteMapDesignTokens.Spacing.section) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(TasteMapCoreTheme.textPrimary)
                        if let subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(TasteMapCoreTheme.textSecondary)
                        }
                    }
                    Spacer()
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(TasteMapCoreTheme.brandDeep)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(TasteMapCoreTheme.brandSoft, in: Capsule())
                }
                content
            }
            .padding(.horizontal, TasteMapDesignTokens.Layout.pageInset)
            .padding(.top, 12)
            .padding(.bottom, 34)
        }
        .safeAreaInset(edge: .top) { Color.clear.frame(height: 2) }
        .tasteMapCorePage()
    }
}

private struct FuseSection<Content: View>: View {
    let title: String
    let trailing: String?
    @ViewBuilder let content: Content

    init(_ title: String, trailing: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline).foregroundStyle(TasteMapCoreTheme.textPrimary)
                Spacer()
                if let trailing {
                    Text(trailing).font(.caption).foregroundStyle(TasteMapCoreTheme.brand)
                }
            }
            content
        }
    }
}

private struct FuseMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(TasteMapCoreTheme.textPrimary)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.caption2)
                .foregroundStyle(TasteMapCoreTheme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FuseEntry: View {
    let title: String
    let detail: String
    let kind: FoodDiningVisualKind
    var accent = TasteMapCoreTheme.brand

    var body: some View {
        HStack(spacing: 10) {
            FoodDiningVisualIcon(
                kind: kind,
                usage: .dataLinked,
                size: 38,
                foregroundColor: accent,
                backgroundColor: accent.opacity(0.11)
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(TasteMapCoreTheme.textPrimary)
                Text(detail).font(.caption2).foregroundStyle(TasteMapCoreTheme.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 3)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TasteMapCoreTheme.textSecondary.opacity(0.62))
        }
        .padding(11)
        .tasteMapCoreCard(radius: 15)
    }
}

private struct FuseRestaurantImage: View {
    let asset: String
    let name: String
    var height: CGFloat = 92

    var body: some View {
        Image(asset)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                    .overlay(alignment: .bottomLeading) {
                        Text(name)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(9)
                    }
            }
    }
}

private struct FuseProfileCandidate: View {
    var body: some View {
        FusePage("我的", subtitle: "仅重做关注数据 · 其余区域继续冻结", badge: "FUSE V3") {
            legacyFrozenHeader

            FuseSection("核心入口") {
                HStack(spacing: 10) {
                    FuseEntry(title: "今天吃什么", detail: "10 家候选餐厅", kind: .genericDining)
                    FuseEntry(title: "我的口味档案", detail: "日料 · 火锅 · 咖啡", kind: .food)
                }
            }

            FuseSection("回味", trailing: "查看全部") {
                HStack(spacing: 8) {
                    FuseMemoryTile(title: "本月回顾", value: "18 次", kind: .calendar)
                    FuseMemoryTile(title: "年度回顾", value: "96 家", kind: .trend)
                    FuseMemoryTile(title: "那年今日", value: "3 条", kind: .time)
                }
            }

            FuseSection("我的食单", trailing: "5 个食单") {
                HStack(spacing: 8) {
                    ForEach(Array(FuseFixture.restaurants.enumerated()), id: \.offset) { _, item in
                        FuseRestaurantImage(asset: item.3, name: item.0, height: 96)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                }
            }

            FuseSection("发现与洞察") {
                VStack(spacing: 8) {
                    FuseEntry(title: "最佳饭搭子", detail: "Mia · 一起吃过 42 次", kind: .sharedMeal)
                    FuseEntry(title: "谁最会种草", detail: "小红书最常记录，Mia 平均分最高", kind: .discovery)
                }
            }

            legacyFrozenSettings
        }
    }

    private var legacyFrozenHeader: some View {
        VStack(spacing: 13) {
            HStack {
                Label("添加好友", systemImage: "person.badge.plus")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button { } label: {
                    Image(systemName: "gearshape")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("设置")
            }

            VStack(spacing: 7) {
                ZStack {
                    Circle().fill(TasteMapCoreTheme.brandSoft)
                    Text("L").font(.title.bold()).foregroundStyle(TasteMapCoreTheme.brandDeep)
                }
                .frame(width: 76, height: 76)
                HStack(spacing: 7) {
                    Text(FuseFixture.name).font(.title2.bold())
                    PremiumBurgerBadge().frame(width: 24, height: 24)
                }
                HStack(spacing: 16) {
                    Label("关注 (FuseFixture.following)", systemImage: "person.2")
                    Label("粉丝 (FuseFixture.followers)", systemImage: "person.2.fill")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(TasteMapCoreTheme.textSecondary)
                Text(FuseFixture.joined)
                    .font(.caption)
                    .foregroundStyle(TasteMapCoreTheme.textSecondary)
                HStack(spacing: 7) {
                    Button("编辑资料") { }.buttonStyle(.bordered).controlSize(.small)
                    Button { } label: { Image(systemName: "square.and.arrow.up") }
                        .buttonStyle(.bordered).controlSize(.small)
                        .accessibilityLabel("分享个人主页")
                }
            }

            HStack(spacing: 0) {
                FuseMetric(value: FuseFixture.visited, label: "去过")
                Divider().frame(height: 34)
                FuseMetric(value: FuseFixture.want, label: "想去")
                Divider().frame(height: 34)
                FuseMetric(value: FuseFixture.spending, label: "总消费")
            }
            .padding(.top, 11)
            .overlay(alignment: .top) { Divider() }
        }
        .padding(15)
        .tasteMapCoreCard(radius: 20)
        .overlay(alignment: .topTrailing) {
            Text("V3 · SOCIAL ONLY")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(TasteMapCoreTheme.brand)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(TasteMapCoreTheme.brandSoft, in: Capsule())
                .padding(10)
        }
    }

    private var legacyFrozenSettings: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape")
                .foregroundStyle(TasteMapCoreTheme.brand)
                .frame(width: 32, height: 32)
                .background(TasteMapCoreTheme.brandSoft, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("设置与数据").font(.subheadline.weight(.semibold))
                Text("同步、备份、隐私和账户")
                    .font(.caption)
                    .foregroundStyle(TasteMapCoreTheme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(TasteMapCoreTheme.textSecondary)
        }
        .padding(13)
        .tasteMapCoreCard(radius: 15)
        .overlay(alignment: .topTrailing) {
            Text("FROZEN")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(TasteMapCoreTheme.brand)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(TasteMapCoreTheme.brandSoft, in: Capsule())
                .padding(7)
        }
    }
}

private struct FuseMemoryTile: View {
    let title: String
    let value: String
    let kind: FoodDiningVisualKind

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            FoodDiningVisualIcon(kind: kind, usage: .dataLinked, size: 30)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(TasteMapCoreTheme.textPrimary)
            Text(value).font(.caption2).foregroundStyle(TasteMapCoreTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .tasteMapCoreCard(radius: 14)
    }
}

private struct FuseVisitEditorCandidate: View {
    var body: some View {
        FusePage("记录一次到访", subtitle: "FUSE V1 · Legacy continuous diary + Current optional contract") {
            HStack(spacing: 11) {
                Image("FoodHeroJapanese").resizable().scaledToFill().frame(width: 76, height: 76).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("鮨一").font(.title3.bold())
                    Text("杭州 · 日料 · 第 8 次到访").font(.caption).foregroundStyle(TasteMapCoreTheme.textSecondary)
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").foregroundStyle(.orange)
                        Text("参考评分 4.8 · 128 人")
                    }.font(.caption2)
                }
                Spacer()
            }
            .padding(11).tasteMapCoreCard()

            FuseSection("这次到访", trailing: "所有字段均可选") {
                VStack(spacing: 1) {
                    FuseFormRow(icon: "note.text", title: "先写下这一餐", value: "金枪鱼很惊喜…")
                    FuseFormRow(icon: "star.fill", title: "我的评分", value: "4.7")
                    FuseFormRow(icon: "calendar", title: "到访时间", value: "2026/09/01 晚餐")
                    FuseFormRow(icon: "takeoutbag.and.cup.and.straw.fill", title: "用餐方式", value: "堂食")
                    FuseFormRow(icon: "person.2.fill", title: "饭搭子", value: "Mia、Alex")
                    FuseFormRow(icon: "sparkles", title: "推荐来源", value: "小红书 · Mia")
                }.tasteMapCoreCard(radius: 16)
            }
            FuseSection("多维评分") {
                HStack {
                    FuseMetric(value: "4.8", label: "口味")
                    FuseMetric(value: "4.6", label: "服务")
                    FuseMetric(value: "4.7", label: "环境")
                }.padding(.vertical, 11).tasteMapCoreCard(radius: 16)
            }
            FuseSection("把这一餐补完整") {
                VStack(spacing: 1) {
                    FuseFormRow(icon: "receipt", title: "实际消费", value: "¥568")
                    FuseFormRow(icon: "fork.knife", title: "菜品", value: "6 道")
                    FuseFormRow(icon: "photo", title: "照片", value: "4 张 · 已上传")
                }.tasteMapCoreCard(radius: 16)
            }
            Button("保存到访") { }
                .font(.headline)
                .frame(maxWidth: .infinity).frame(height: 48)
                .foregroundStyle(.white).background(TasteMapCoreTheme.brand, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

private struct FuseFormRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(TasteMapCoreTheme.brand)
            Text(title).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline.weight(.medium)).foregroundStyle(TasteMapCoreTheme.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.72)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(TasteMapCoreTheme.textSecondary.opacity(0.5))
        }.padding(.horizontal, 12).frame(minHeight: 48)
    }
}

private struct FuseDishPhotoCandidate: View {
    var body: some View {
        FusePage("菜品与实拍", subtitle: "Legacy in-flow manager · Current photo lifecycle") {
            FuseSection("本次实拍", trailing: "4 / 9") {
                HStack(spacing: 7) {
                    ForEach(["FoodHeroJapanese", "FoodHeroHotpotGrill", "FoodHeroCafe"], id: \.self) { asset in
                        Image(asset).resizable().scaledToFill().frame(maxWidth: .infinity).frame(height: 108).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                    }
                }
                HStack(spacing: 7) {
                    Label("添加照片", systemImage: "plus").font(.caption.weight(.semibold))
                    Spacer()
                    Label("3 已同步", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Label("1 重试", systemImage: "arrow.clockwise.circle.fill").foregroundStyle(.orange)
                }.font(.caption2).padding(.horizontal, 3)
            }

            FuseSection("菜品", trailing: "6 道") {
                VStack(spacing: 8) {
                    FuseDishRow(name: "金枪鱼中腹", rating: "4.9", note: "今天最惊喜", asset: "FoodHeroJapanese")
                    FuseDishRow(name: "海胆手卷", rating: "4.7", note: "奶油感很足", asset: "FoodHeroMixed")
                    FuseDishRow(name: "赤身握寿司", rating: "4.6", note: "稳定发挥", asset: "FoodHeroJapanese")
                    Button { } label: {
                        Label("新增菜品", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }
            }

            FuseSection("照片安全状态") {
                VStack(spacing: 1) {
                    FuseFormRow(icon: "iphone", title: "本地原图", value: "4 张保留")
                    FuseFormRow(icon: "icloud.and.arrow.up", title: "云端副本", value: "3 张完成")
                    FuseFormRow(icon: "exclamationmark.arrow.triangle.2.circlepath", title: "待重试", value: "1 张")
                }.tasteMapCoreCard(radius: 16)
            }
        }
    }
}

private struct FuseDishRow: View {
    let name: String
    let rating: String
    let note: String
    let asset: String

    var body: some View {
        HStack(spacing: 10) {
            Image(asset).resizable().scaledToFill().frame(width: 58, height: 58).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.subheadline.weight(.semibold))
                Text(note).font(.caption).foregroundStyle(TasteMapCoreTheme.textSecondary)
            }
            Spacer()
            Label(rating, systemImage: "star.fill").font(.caption.weight(.bold)).foregroundStyle(.orange)
        }.padding(8).tasteMapCoreCard(radius: 14)
    }
}

private struct FusePublicProfileCandidate: View {
    @State private var tab = "足迹"

    var body: some View {
        FusePage("TA 的主页", subtitle: "Legacy public-profile topology · Current social actions") {
            VStack(spacing: 11) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.purple.opacity(0.13))
                        Text("M").font(.title.bold()).foregroundStyle(.purple)
                    }.frame(width: 70, height: 70)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mia Chen").font(.title3.bold())
                        Text("杭州 · 加入 530 天").font(.caption).foregroundStyle(TasteMapCoreTheme.textSecondary)
                        Text("日料与咖啡重度爱好者").font(.caption).foregroundStyle(TasteMapCoreTheme.brandDeep)
                    }
                    Spacer()
                    Menu { Button("举报") { }; Button("屏蔽") { } } label: { Image(systemName: "ellipsis") }
                }
                HStack(spacing: 8) {
                    Button("已关注") { }.buttonStyle(.borderedProminent)
                    Button { } label: { Label("分享", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
                    Button { } label: { Label("一起吃", systemImage: "person.2.fill") }.buttonStyle(.bordered)
                }.controlSize(.small)
                HStack {
                    FuseMetric(value: "128", label: "去过")
                    FuseMetric(value: "31", label: "想去")
                    FuseMetric(value: "68", label: "关注")
                    FuseMetric(value: "204", label: "被关注")
                }.padding(.vertical, 9).tasteMapCoreCard(radius: 16)
            }
            HStack(spacing: 0) {
                ForEach(["足迹", "动态", "食单"], id: \.self) { item in
                    Button(item) { tab = item }
                        .font(.subheadline.weight(tab == item ? .bold : .medium))
                        .foregroundStyle(tab == item ? TasteMapCoreTheme.brandDeep : TasteMapCoreTheme.textSecondary)
                        .frame(maxWidth: .infinity).frame(height: 42)
                        .overlay(alignment: .bottom) { if tab == item { Rectangle().fill(TasteMapCoreTheme.brand).frame(height: 2) } }
                }
            }.tasteMapCoreCard(radius: 14)
            FuseSection("代表餐厅", trailing: "查看全部") {
                HStack(spacing: 8) {
                    ForEach(Array(FuseFixture.restaurants.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 4) {
                            FuseRestaurantImage(asset: item.3, name: item.0, height: 88)
                            Label(item.2, systemImage: "star.fill").font(.caption2).foregroundStyle(.orange)
                        }.frame(maxWidth: .infinity).padding(5).tasteMapCoreCard(radius: 13)
                    }
                }
            }
            FuseSection("最近动态") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mia 在 鮨一 记录了一次晚餐").font(.subheadline.weight(.semibold))
                    Text("到访评分 4.8 · 和 Lafayette 一起 · 2 小时前").font(.caption).foregroundStyle(TasteMapCoreTheme.textSecondary)
                    HStack { Label("18", systemImage: "heart.fill"); Label("6", systemImage: "bubble.left.fill"); Spacer(); Label("分享", systemImage: "square.and.arrow.up") }
                        .font(.caption).foregroundStyle(TasteMapCoreTheme.brand)
                }.padding(12).tasteMapCoreCard(radius: 16)
            }
        }
    }
}

private struct FuseListsCandidate: View {
    var body: some View {
        FusePage("我的食单", subtitle: "Legacy list hierarchy · Current visibility, ranking and sharing") {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("城市约会餐厅").font(.title3.bold())
                    Text("公开 · 排名食单 · 12 家餐厅").font(.caption).foregroundStyle(TasteMapCoreTheme.textSecondary)
                }
                Spacer()
                Button { } label: { Image(systemName: "square.and.arrow.up") }.buttonStyle(.bordered)
                Button { } label: { Image(systemName: "ellipsis") }.buttonStyle(.bordered)
            }
            ZStack(alignment: .bottomLeading) {
                HStack(spacing: 2) {
                    ForEach(Array(FuseFixture.restaurants.enumerated()), id: \.offset) { _, item in
                        Image(item.3).resizable().scaledToFill().frame(maxWidth: .infinity).frame(height: 145).clipped()
                    }
                }
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                Text("这份食单由真实餐厅图片组成")
                    .font(.caption.weight(.semibold)).foregroundStyle(.white).padding(12)
            }.clipShape(RoundedRectangle(cornerRadius: 18))
            FuseSection("餐厅排名", trailing: "编辑") {
                VStack(spacing: 8) {
                    ForEach(Array(FuseFixture.restaurants.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 10) {
                            Text("\(index + 1)").font(.title3.bold()).foregroundStyle(TasteMapCoreTheme.brand)
                                .frame(width: 28)
                            Image(item.3).resizable().scaledToFill().frame(width: 58, height: 58).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 11))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.0).font(.subheadline.weight(.semibold))
                                Text(item.1).font(.caption).foregroundStyle(TasteMapCoreTheme.textSecondary)
                            }
                            Spacer()
                            Label(item.2, systemImage: "star.fill").font(.caption.weight(.bold)).foregroundStyle(.orange)
                        }.padding(8).tasteMapCoreCard(radius: 14)
                    }
                }
            }
            FuseSection("更多食单") {
                HStack(spacing: 8) {
                    FuseMemoryTile(title: "深夜食堂", value: "8 家 · 私密", kind: .time)
                    FuseMemoryTile(title: "周末咖啡", value: "15 家 · 公开", kind: .drink)
                    FuseMemoryTile(title: "朋友来杭", value: "11 家 · 公开", kind: .menu)
                }
            }
        }
    }
}

private enum FuseAnalysisKind: String {
    case companion, source, monthly, annual

    var eyebrow: String { switch self { case .companion: "TOGETHER"; case .source: "DISCOVERY"; case .monthly: "THIS MONTH"; case .annual: "YEAR IN TASTE" } }
    var title: String { switch self { case .companion: "最佳饭搭子"; case .source: "谁最会种草"; case .monthly: "本月回顾"; case .annual: "年度回顾" } }
    var headline: String { switch self { case .companion: "你和 Mia，把城市吃成了共同记忆"; case .source: "Mia 最懂你的口味，小红书最会把你带进新店"; case .monthly: "九月是一场日料与夜宵的接力"; case .annual: "这一年，你用 96 家餐厅画出味觉轨迹" } }
    var summary: String {
        switch self {
        case .companion: "42 次共同到访里，日料与深夜食堂构成你们最稳定的双人餐桌。"
        case .source: "朋友推荐更准，内容平台带来更多新店；靠谱与踩坑被明确分开。"
        case .monthly: "18 次到访、12 家餐厅和 7 家新店，组成这个月真实发生的味觉故事。"
        case .annual: "278 次到访横跨四季，回头率与消费轨迹共同定义了你的 2026。"
        }
    }
    var heroTag: String {
        switch self {
        case .companion: "双人餐桌"
        case .source: "来源命中"
        case .monthly: "九月主线"
        case .annual: "年度味觉"
        }
    }
    var heroAsset: String { switch self { case .companion: "FoodHeroJapanese"; case .source: "FoodHeroMixed"; case .monthly: "FoodHeroHotpotGrill"; case .annual: "FoodHeroMixed" } }
    var callouts: [(String, String, FoodDiningVisualKind)] {
        switch self {
        case .companion: [("42 次", "一起吃过", .sharedMeal), ("鮨一", "最常去", .restaurant), ("日料", "最常吃", .food), ("11 天前", "最近一次", .calendar)]
        case .source: [("4.72", "Mia 平均分", .rating), ("28 次", "小红书记录", .discovery), ("3 家", "最坑来源", .receipt), ("日料", "命中口味", .food)]
        case .monthly: [("18 次", "本月到访", .calendar), ("12 家", "餐厅数量", .restaurant), ("¥4,286", "实际消费", .receipt), ("7 家", "新店", .discovery)]
        case .annual: [("278 次", "全年到访", .calendar), ("96 家", "餐厅数量", .restaurant), ("¥36,842", "消费总览", .receipt), ("41%", "回头率", .repeatVisit)]
        }
    }
}

private struct FuseAnalysisCandidate: View {
    let kind: FuseAnalysisKind

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .frame(width: 44, height: 44)
                    Spacer()
                    Text(kind.title)
                        .font(.headline)
                        .foregroundStyle(TasteMapAnalysisTheme.ink)
                    Spacer()
                    Image(systemName: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundStyle(TasteMapAnalysisTheme.brand)
                        .frame(width: 44, height: 44)
                }

                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        Text(kind.eyebrow)
                            .font(.caption2.bold())
                            .tracking(2.2)
                            .foregroundStyle(TasteMapAnalysisTheme.brand)
                        Spacer()
                        Label("重新设计 V2", systemImage: "sparkles")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(TasteMapAnalysisTheme.brand)
                    }
                    Text(kind.title)
                        .font(.system(size: 37, weight: .heavy, design: .rounded))
                        .foregroundStyle(TasteMapAnalysisTheme.ink)
                    Text(kind.summary)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(TasteMapAnalysisTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Label("生成分享海报", systemImage: "wand.and.stars")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .frame(height: 58)
                        .background(TasteMapAnalysisTheme.brand, in: RoundedRectangle(cornerRadius: 18))
                }

                FuseAnalysisHero(kind: kind)

                VStack(alignment: .leading, spacing: 8) {
                    Text("核心洞察").font(.caption.bold()).foregroundStyle(TasteMapAnalysisTheme.brand)
                    Text(kind.headline).font(.title3.bold()).foregroundStyle(TasteMapAnalysisTheme.ink)
                    Text("结论来自 Rich Demo 的 Restaurant、Visit、消费、饭搭子与推荐来源记录；装饰图形不冒充数据语义。")
                        .font(.caption).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                }.padding(15).background(TasteMapAnalysisTheme.card, in: ReceiptShape())

                FuseSection("TOP 3") {
                    HStack(spacing: 8) {
                        ForEach(Array(FuseFixture.restaurants.enumerated()), id: \.offset) { index, item in
                            VStack(alignment: .leading, spacing: 4) {
                                FuseRestaurantImage(asset: item.3, name: "#\(index + 1) \(item.0)", height: 92)
                                Text(item.1).font(.caption2).foregroundStyle(TasteMapAnalysisTheme.secondaryInk).padding(.horizontal, 5)
                            }.padding(4).background(TasteMapAnalysisTheme.card, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                FuseDistribution(kind: kind)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .background(TasteMapAnalysisTheme.canvas.ignoresSafeArea())
    }
}

private struct FuseAnalysisHero: View {
    let kind: FuseAnalysisKind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(TasteMapAnalysisTheme.creamSoft.opacity(0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(TasteMapAnalysisTheme.hairline)
                }
            AnalysisConnectorWeb()
                .stroke(
                    TasteMapAnalysisTheme.brand.opacity(0.28),
                    style: StrokeStyle(lineWidth: 1.3, dash: [5, 6])
                )
                .frame(width: 285, height: 275)
            Image(kind.heroAsset)
                .resizable()
                .scaledToFill()
                .frame(width: 184, height: 184)
                .clipShape(Circle())
                .overlay { Circle().stroke(.white, lineWidth: 7) }
                .shadow(color: TasteMapAnalysisTheme.brand.opacity(0.19), radius: 20, y: 11)
                .overlay(alignment: .bottom) {
                    Text(kind.heroTag)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TasteMapAnalysisTheme.ink)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.96), in: Capsule())
                        .offset(y: 17)
                }
            ForEach(Array(kind.callouts.enumerated()), id: \.offset) { index, item in
                FuseAnalysisNode(value: item.0, label: item.1, visual: item.2, tone: index)
                    .offset(nodeOffset(index))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 430)
    }

    private func nodeOffset(_ index: Int) -> CGSize {
        switch index {
        case 0: CGSize(width: -112, height: -145)
        case 1: CGSize(width: 112, height: -145)
        case 2: CGSize(width: -112, height: 145)
        default: CGSize(width: 112, height: 145)
        }
    }
}

private struct FuseAnalysisNode: View {
    let value: String
    let label: String
    let visual: FoodDiningVisualKind
    let tone: Int

    var color: Color { [TasteMapAnalysisTheme.ingredientRed, TasteMapAnalysisTheme.leafGreen, TasteMapAnalysisTheme.caramel, TasteMapAnalysisTheme.brand][tone % 4] }

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4, height: 50)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    FoodDiningVisualIcon(
                        kind: visual,
                        usage: .dataLinked,
                        size: 23,
                        foregroundColor: color,
                        backgroundColor: color.opacity(0.12)
                    )
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                }
                Text(value)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(TasteMapAnalysisTheme.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 126, alignment: .leading)
        .padding(9)
        .background(TasteMapAnalysisTheme.card.opacity(0.97), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(TasteMapAnalysisTheme.hairline) }
        .shadow(color: TasteMapAnalysisTheme.ink.opacity(0.055), radius: 9, y: 4)
    }
}

private struct FuseDistribution: View {
    let kind: FuseAnalysisKind
    let rows = [("日料", 0.86, "42%"), ("火锅与烧烤", 0.64, "31%"), ("咖啡与甜点", 0.42, "18%")]

    var body: some View {
        FuseSection(kind == .source ? "来源表现" : "口味分布") {
            VStack(spacing: 10) {
                ForEach(rows, id: \.0) { row in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text(row.0).font(.caption.weight(.semibold)); Spacer(); Text(row.2).font(.caption2.monospacedDigit()) }
                        GeometryReader { proxy in
                            Capsule().fill(TasteMapAnalysisTheme.brandSoft)
                                .overlay(alignment: .leading) { Capsule().fill(TasteMapAnalysisTheme.brand).frame(width: proxy.size.width * row.1) }
                        }.frame(height: 8)
                    }
                }
            }.padding(14).background(TasteMapAnalysisTheme.card, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

private enum FusePosterKind: String {
    case taste, companion, source, monthly, annual
    var eyebrow: String { switch self { case .taste: "MY TASTE MAP"; case .companion: "BEST TABLEMATE"; case .source: "WHO INSPIRES ME"; case .monthly: "SEPTEMBER RECAP"; case .annual: "2026 IN TASTE" } }
    var title: String { switch self { case .taste: "我的口味档案"; case .companion: "我和 Mia 的最佳饭搭子报告"; case .source: "谁最会种草"; case .monthly: "本月回顾"; case .annual: "年度回顾" } }
    var hero: String { switch self { case .taste, .companion: "FoodHeroJapanese"; case .source: "FoodHeroMixed"; case .monthly: "FoodHeroHotpotGrill"; case .annual: "FoodHeroMixed" } }
    var statement: String { switch self { case .taste: "清鲜日料 × 热烈火锅，是你最稳定的双主线"; case .companion: "42 次一起吃饭，把杭州吃成共同记忆"; case .source: "Mia 最懂你，小红书带你发现最多新店"; case .monthly: "18 次到访，九月的夜宵比白天更精彩"; case .annual: "96 家餐厅，278 次到访，一整年的味觉轨迹" } }
}

private enum FusePosterStyle: String {
    case storyMap
    case infographic
    case editorial

    var candidateLabel: String {
        switch self {
        case .storyMap: "REDESIGN V2 · DINING STORY MAP"
        case .infographic: "CANDIDATE A · INFOGRAPHIC ORBIT"
        case .editorial: "CANDIDATE B · EDITORIAL RECEIPT"
        }
    }
}

private struct FusePosterCandidate: View {
    let kind: FusePosterKind
    let style: FusePosterStyle

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width - 18, 390)
            let height = width * 16 / 9
            ScrollView {
                VStack {
                    Group {
                        switch style {
                        case .storyMap:
                            FuseStoryPosterCanvas(kind: kind, style: style)
                        case .infographic:
                            FusePosterCanvas(kind: kind, style: style)
                        case .editorial:
                            FuseEditorialPosterCanvas(kind: kind, style: style)
                        }
                    }
                        .frame(width: width, height: height)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
                        .padding(.vertical, 10)
                }.frame(maxWidth: .infinity)
            }.background(Color(white: 0.90).ignoresSafeArea())
        }
    }
}

/// Redesign V2 is a real SwiftUI 9:16 dining story map. It keeps the native
/// renderer/footer contract but replaces the rejected orbit/editorial options
/// with one stronger hierarchy: statement → food story → evidence → brand.
private struct FuseStoryPosterCanvas: View {
    let kind: FusePosterKind
    let style: FusePosterStyle

    private var metrics: [(String, String, FoodDiningVisualKind)] {
        switch kind {
        case .taste:
            [("日料", "稳定偏爱", .food), ("¥188", "典型消费", .receipt), ("41%", "回头率", .repeatVisit)]
        case .companion:
            [("42 次", "一起吃饭", .sharedMeal), ("鮨一", "共同记忆", .restaurant), ("11 天", "最近一次", .calendar)]
        case .source:
            [("4.72", "Mia 命中", .rating), ("28 次", "小红书", .discovery), ("3 家", "最坑来源", .receipt)]
        case .monthly:
            [("18 次", "本月到访", .calendar), ("7 家", "新店", .discovery), ("¥4,286", "实际消费", .receipt)]
        case .annual:
            [("278 次", "全年到访", .calendar), ("96 家", "餐厅", .restaurant), ("¥36.8k", "全年消费", .receipt)]
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 390
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4 * scale) {
                        Text(style.candidateLabel)
                            .font(.system(size: 8 * scale, weight: .heavy))
                            .tracking(1.4)
                            .foregroundStyle(TasteMapAnalysisTheme.ingredientRed)
                        Text(kind.eyebrow)
                            .font(.system(size: 10 * scale, weight: .heavy))
                            .tracking(2.2)
                            .foregroundStyle(TasteMapAnalysisTheme.brand)
                    }
                    Spacer()
                    FoodDiningVisualIcon(kind: kind.visual, usage: .dataLinked, size: 40 * scale)
                }

                Text(kind.title)
                    .font(.system(size: 30 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(TasteMapAnalysisTheme.ink)
                    .padding(.top, 8 * scale)
                Text(kind.statement)
                    .font(.system(size: 15 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 5 * scale)

                ZStack {
                    RoundedRectangle(cornerRadius: 30 * scale, style: .continuous)
                        .fill(TasteMapAnalysisTheme.creamSoft.opacity(0.82))
                        .overlay {
                            RoundedRectangle(cornerRadius: 30 * scale, style: .continuous)
                                .stroke(TasteMapAnalysisTheme.hairline)
                        }
                    AnalysisConnectorWeb()
                        .stroke(
                            TasteMapAnalysisTheme.brand.opacity(0.24),
                            style: StrokeStyle(lineWidth: 1.1 * scale, dash: [4 * scale, 5 * scale])
                        )
                        .frame(width: 295 * scale, height: 185 * scale)
                    Image(kind.hero)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 170 * scale, height: 170 * scale)
                        .clipShape(Circle())
                        .overlay { Circle().stroke(.white, lineWidth: 6 * scale) }
                        .shadow(color: TasteMapAnalysisTheme.ink.opacity(0.13), radius: 14 * scale, y: 8 * scale)
                    storyBadge(metrics[0], color: TasteMapAnalysisTheme.ingredientRed, scale: scale)
                        .offset(x: -112 * scale, y: -86 * scale)
                    storyBadge(metrics[1], color: TasteMapAnalysisTheme.brand, scale: scale)
                        .offset(x: 112 * scale, y: -86 * scale)
                    storyBadge(metrics[2], color: TasteMapAnalysisTheme.leafGreen, scale: scale)
                        .offset(x: 0, y: 102 * scale)
                }
                .frame(height: 290 * scale)
                .padding(.top, 16 * scale)

                VStack(alignment: .leading, spacing: 7 * scale) {
                    HStack {
                        Text("代表餐厅")
                            .font(.system(size: 11 * scale, weight: .heavy))
                            .foregroundStyle(TasteMapAnalysisTheme.brand)
                        Spacer()
                        Text("真实图片优先")
                            .font(.system(size: 8 * scale, weight: .semibold))
                            .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                    }
                    HStack(spacing: 7 * scale) {
                        ForEach(Array(FuseFixture.restaurants.enumerated()), id: \.offset) { index, item in
                            FuseRestaurantImage(asset: item.3, name: "#\(index + 1) \(item.0)", height: 76 * scale)
                                .clipShape(RoundedRectangle(cornerRadius: 11 * scale))
                        }
                    }
                }
                .padding(.top, 13 * scale)

                HStack(spacing: 7 * scale) {
                    ForEach(kind.editorialTags.prefix(4), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 9 * scale, weight: .bold))
                            .padding(.horizontal, 8 * scale)
                            .padding(.vertical, 5 * scale)
                            .background(.white.opacity(0.82), in: Capsule())
                            .overlay { Capsule().stroke(TasteMapAnalysisTheme.hairline) }
                    }
                }
                .padding(.top, 12 * scale)

                Spacer(minLength: 0)
                SharePosterBrandFooter(
                    supportingText: "Taste Map · 把真实吃过的故事分享出去",
                    configuration: SharePosterBrandConfiguration(qrDestinationURL: nil)
                )
                .scaleEffect(scale, anchor: .bottomLeading)
                .frame(height: 62 * scale)
            }
            .padding(20 * scale)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .background(
                ZStack {
                    TasteMapAnalysisTheme.canvas
                    Circle()
                        .fill(TasteMapAnalysisTheme.leafGreenSoft.opacity(0.50))
                        .frame(width: 200 * scale)
                        .offset(x: -150 * scale, y: 255 * scale)
                    Circle()
                        .fill(TasteMapAnalysisTheme.creamSoft.opacity(0.68))
                        .frame(width: 250 * scale)
                        .offset(x: 155 * scale, y: -255 * scale)
                }
            )
        }
        .preferredColorScheme(.light)
    }

    private func storyBadge(
        _ item: (String, String, FoodDiningVisualKind),
        color: Color,
        scale: CGFloat
    ) -> some View {
        HStack(spacing: 6 * scale) {
            FoodDiningVisualIcon(
                kind: item.2,
                usage: .dataLinked,
                size: 24 * scale,
                foregroundColor: color,
                backgroundColor: color.opacity(0.12)
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(item.0)
                    .font(.system(size: 11 * scale, weight: .heavy))
                    .foregroundStyle(TasteMapAnalysisTheme.ink)
                Text(item.1)
                    .font(.system(size: 8 * scale, weight: .semibold))
                    .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            }
        }
        .frame(width: 105 * scale, alignment: .leading)
        .padding(8 * scale)
        .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 14 * scale))
        .overlay { RoundedRectangle(cornerRadius: 14 * scale).stroke(TasteMapAnalysisTheme.hairline) }
    }
}

private struct FusePosterCanvas: View {
    let kind: FusePosterKind
    let style: FusePosterStyle

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 390
            VStack(alignment: .leading, spacing: 13 * scale) {
                VStack(alignment: .leading, spacing: 4 * scale) {
                    Text(style.candidateLabel).font(.system(size: 8 * scale, weight: .heavy)).tracking(1.4)
                        .foregroundStyle(TasteMapAnalysisTheme.ingredientRed)
                    Text(kind.eyebrow).font(.system(size: 10 * scale, weight: .heavy)).tracking(2)
                        .foregroundStyle(TasteMapAnalysisTheme.brand)
                    Text(kind.title).font(.system(size: 27 * scale, weight: .heavy, design: .rounded))
                        .foregroundStyle(TasteMapAnalysisTheme.ink)
                    Text(kind.statement).font(.system(size: 13 * scale, weight: .semibold))
                        .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                }
                ZStack {
                    AnalysisConnectorWeb().stroke(TasteMapAnalysisTheme.brand.opacity(0.24), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    Image(kind.hero).resizable().scaledToFill().frame(width: 168 * scale, height: 168 * scale).clipShape(Circle())
                        .overlay { Circle().stroke(.white, lineWidth: 6 * scale) }
                    posterBadge("4.8", "口味", .rating).offset(x: -125 * scale, y: -68 * scale)
                    posterBadge("42%", "最常吃", .food).offset(x: 125 * scale, y: -68 * scale)
                    posterBadge("¥36.8k", "消费", .receipt).offset(x: -125 * scale, y: 72 * scale)
                    posterBadge("41%", "回头率", .repeatVisit).offset(x: 125 * scale, y: 72 * scale)
                }.frame(height: 240 * scale)
                VStack(alignment: .leading, spacing: 6 * scale) {
                    Text("代表餐厅").font(.system(size: 12 * scale, weight: .bold)).foregroundStyle(TasteMapAnalysisTheme.brand)
                    HStack(spacing: 6 * scale) {
                        ForEach(Array(FuseFixture.restaurants.enumerated()), id: \.offset) { _, item in
                            FuseRestaurantImage(asset: item.3, name: item.0, height: 82 * scale)
                                .clipShape(RoundedRectangle(cornerRadius: 10 * scale))
                        }
                    }
                }
                HStack(spacing: 7 * scale) {
                    ForEach(["日料", "火锅", "夜宵", "稳定偏爱"], id: \.self) { tag in
                        Text(tag).font(.system(size: 10 * scale, weight: .bold)).padding(.horizontal, 8 * scale).padding(.vertical, 5 * scale)
                            .background(TasteMapAnalysisTheme.brandSoft, in: Capsule())
                    }
                }
                Spacer(minLength: 0)
                SharePosterBrandFooter(
                    supportingText: "仅基于 Rich Demo 的真实语义记录生成",
                    configuration: SharePosterBrandConfiguration(qrDestinationURL: nil)
                ).scaleEffect(scale, anchor: .bottomLeading).frame(height: 62 * scale)
            }
            .padding(20 * scale)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .background(
                ZStack {
                    TasteMapAnalysisTheme.canvas
                    Circle().fill(TasteMapAnalysisTheme.creamSoft.opacity(0.75)).frame(width: 230 * scale).offset(x: 145 * scale, y: -220 * scale)
                    Circle().fill(TasteMapAnalysisTheme.leafGreenSoft.opacity(0.7)).frame(width: 170 * scale).offset(x: -150 * scale, y: 230 * scale)
                }
            )
        }.preferredColorScheme(.light)
    }

    private func posterBadge(_ value: String, _ label: String, _ visual: FoodDiningVisualKind) -> some View {
        VStack(spacing: 2) {
            FoodDiningVisualIcon(kind: visual, usage: .dataLinked, size: 28)
            Text(value).font(.caption.bold()).foregroundStyle(TasteMapAnalysisTheme.ink)
            Text(label).font(.caption2).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
        }.frame(width: 78).padding(.vertical, 6).background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 13))
    }
}

/// Candidate B deliberately uses a different, real SwiftUI 9:16 renderer:
/// an editorial meal-journal / receipt composition instead of Candidate A's
/// radial infographic. Both preserve the same data and sharing footer contract.
private struct FuseEditorialPosterCanvas: View {
    let kind: FusePosterKind
    let style: FusePosterStyle

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 390
            VStack(alignment: .leading, spacing: 12 * scale) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5 * scale) {
                        Text(style.candidateLabel)
                            .font(.system(size: 8 * scale, weight: .heavy))
                            .tracking(1.4)
                            .foregroundStyle(TasteMapAnalysisTheme.ingredientRed)
                        Text(kind.eyebrow)
                            .font(.system(size: 10 * scale, weight: .heavy))
                            .tracking(2)
                            .foregroundStyle(TasteMapAnalysisTheme.brand)
                        Text(kind.title)
                            .font(.system(size: 27 * scale, weight: .heavy, design: .rounded))
                            .foregroundStyle(TasteMapAnalysisTheme.ink)
                    }
                    Spacer()
                    FoodDiningVisualIcon(kind: kind.visual, usage: .dataLinked, size: 42 * scale)
                }

                FuseEditorialHero(kind: kind, scale: scale)

                HStack(alignment: .top, spacing: 9 * scale) {
                    VStack(alignment: .leading, spacing: 7 * scale) {
                        Text("THIS STORY")
                            .font(.system(size: 9 * scale, weight: .heavy))
                            .tracking(1.5)
                            .foregroundStyle(TasteMapAnalysisTheme.brand)
                        Text(kind.statement)
                            .font(.system(size: 17 * scale, weight: .bold, design: .rounded))
                            .foregroundStyle(TasteMapAnalysisTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Divider().overlay(TasteMapAnalysisTheme.hairline)
                        ForEach(kind.editorialFacts, id: \.0) { fact in
                            HStack {
                                Text(fact.0).foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                                Spacer()
                                Text(fact.1).fontWeight(.bold).foregroundStyle(TasteMapAnalysisTheme.ink)
                            }
                            .font(.system(size: 11 * scale))
                        }
                    }
                    .padding(12 * scale)
                    .background(TasteMapAnalysisTheme.card, in: ReceiptShape())

                    VStack(spacing: 7 * scale) {
                        ForEach(Array(FuseFixture.restaurants.prefix(2).enumerated()), id: \.offset) { _, item in
                            FuseRestaurantImage(asset: item.3, name: item.0, height: 91 * scale)
                                .clipShape(RoundedRectangle(cornerRadius: 12 * scale))
                        }
                    }
                    .frame(width: 128 * scale)
                }

                HStack(spacing: 6 * scale) {
                    ForEach(kind.editorialTags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 9 * scale, weight: .bold))
                            .padding(.horizontal, 8 * scale)
                            .padding(.vertical, 5 * scale)
                            .background(.white.opacity(0.78), in: Capsule())
                            .overlay { Capsule().stroke(TasteMapAnalysisTheme.hairline) }
                    }
                }

                Spacer(minLength: 0)
                SharePosterBrandFooter(
                    supportingText: "Taste Map · 把每一餐变成可分享的生活故事",
                    configuration: SharePosterBrandConfiguration(qrDestinationURL: nil)
                )
                .scaleEffect(scale, anchor: .bottomLeading)
                .frame(height: 62 * scale)
            }
            .padding(20 * scale)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .background(
                ZStack {
                    TasteMapAnalysisTheme.canvas
                    RoundedRectangle(cornerRadius: 80 * scale)
                        .fill(TasteMapAnalysisTheme.creamSoft.opacity(0.62))
                        .frame(width: 280 * scale, height: 170 * scale)
                        .rotationEffect(.degrees(-12))
                        .offset(x: 145 * scale, y: -245 * scale)
                    Circle()
                        .fill(TasteMapAnalysisTheme.leafGreenSoft.opacity(0.52))
                        .frame(width: 185 * scale)
                        .offset(x: -165 * scale, y: 250 * scale)
                }
            )
        }
        .preferredColorScheme(.light)
    }
}

private struct FuseEditorialHero: View {
    let kind: FusePosterKind
    let scale: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(kind.hero)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 178 * scale)
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.62)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 3 * scale) {
                Text(kind.heroKicker)
                    .font(.system(size: 9 * scale, weight: .heavy))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.82))
                Text(kind.heroValue)
                    .font(.system(size: 25 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(14 * scale)
        }
        .clipShape(RoundedRectangle(cornerRadius: 19 * scale, style: .continuous))
    }
}

private extension FusePosterKind {
    var visual: FoodDiningVisualKind {
        switch self {
        case .taste: .food
        case .companion: .sharedMeal
        case .source: .menu
        case .monthly: .calendar
        case .annual: .trend
        }
    }

    var heroKicker: String {
        switch self {
        case .taste: "YOUR TASTE IN ONE PLATE"
        case .companion: "42 SHARED MEALS"
        case .source: "MOST TRUSTED SOURCE"
        case .monthly: "SEPTEMBER HIGHLIGHT"
        case .annual: "YOUR YEAR AT THE TABLE"
        }
    }

    var heroValue: String {
        switch self {
        case .taste: "清鲜 × 热烈"
        case .companion: "Mia"
        case .source: "Mia 最懂你"
        case .monthly: "18 次到访"
        case .annual: "278 次到访"
        }
    }

    var editorialFacts: [(String, String)] {
        switch self {
        case .taste: [("最常吃", "日料 42%"), ("回头率", "41%"), ("常去价位", "¥150–300")]
        case .companion: [("一起吃过", "42 次"), ("共同最爱", "日料"), ("最近一次", "8 月 28 日")]
        case .source: [("最靠谱", "Mia · 4.8"), ("记录最多", "小红书"), ("最坑推荐来源", "同事群")]
        case .monthly: [("餐厅", "14 家"), ("新店", "6 家"), ("本月消费", "¥4,820")]
        case .annual: [("餐厅", "96 家"), ("新店", "58 家"), ("全年消费", "¥36,842")]
        }
    }

    var editorialTags: [String] {
        switch self {
        case .taste: ["日料", "火锅", "夜宵", "稳定偏爱"]
        case .companion: ["默契", "会复购", "纪念日", "深夜食堂"]
        case .source: ["朋友", "小红书", "同事群", "餐厅回访"]
        case .monthly: ["夜宵上升", "火锅月", "6 家新店"]
        case .annual: ["杭州", "上海", "日料", "278 次"]
        }
    }
}

private struct FusePaywallCandidate: View {
    var body: some View {
        FusePage(
            "Taste Map Premium",
            subtitle: "仅重做汉堡主视觉 · 其余区域继续冻结",
            badge: "REDESIGN V2"
        ) {
            VStack(spacing: 12) {
                FusePremiumHamburgerV2()
                    .frame(width: 138, height: 138)
                Text("把每一顿饭，变成更完整的味觉记忆")
                    .font(.title3.bold()).multilineTextAlignment(.center).foregroundStyle(TasteMapCoreTheme.textPrimary)
                Text("价格和订阅周期以 App Store 实际配置为准")
                    .font(.caption).foregroundStyle(TasteMapCoreTheme.textSecondary)
            }.frame(maxWidth: .infinity).padding(.vertical, 8)
            FuseSection("Premium 包含") {
                VStack(spacing: 8) {
                    FusePremiumBenefit(title: "完整分析与五类分享海报", detail: "口味、饭搭子、种草、本月与年度")
                    FusePremiumBenefit(title: "高级筛选与照片能力", detail: "沿用当前 Premium Feature Registry")
                    FusePremiumBenefit(title: "更丰富的食单与回顾", detail: "正式权益由 StoreKit 与服务端共同判定")
                }
            }
            VStack(spacing: 9) {
                Button("查看 App Store 方案") { }.font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                    .foregroundStyle(.white).background(TasteMapCoreTheme.brand, in: RoundedRectangle(cornerRadius: 15))
                Button("恢复购买") { }.font(.subheadline.weight(.semibold))
                Text("订阅、续期、退款与撤销仍由当前 StoreKit 2 / server entitlement 架构处理。")
                    .font(.caption2).foregroundStyle(TasteMapCoreTheme.textSecondary).multilineTextAlignment(.center)
            }
            HStack { Button("隐私政策") { }; Spacer(); Button("服务条款") { } }.font(.caption)
        }
    }
}

/// Candidate-only Premium hero. The compact Profile badge remains the approved
/// historical asset; this redraw is isolated to the Paywall region Lafayette
/// explicitly marked NEEDS REDESIGN.
private struct FusePremiumHamburgerV2: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(TasteMapCoreTheme.brandSoft.opacity(0.82))
            Circle()
                .stroke(TasteMapCoreTheme.brand.opacity(0.20), lineWidth: 1)
            Ellipse()
                .fill(.white.opacity(0.92))
                .frame(width: 105, height: 35)
                .offset(y: 35)
                .shadow(color: TasteMapCoreTheme.textPrimary.opacity(0.09), radius: 7, y: 5)

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 0.96, green: 0.73, blue: 0.31))
                    .frame(width: 88, height: 23)
                    .offset(y: 25)
                Capsule()
                    .fill(Color(red: 0.31, green: 0.16, blue: 0.11))
                    .frame(width: 92, height: 18)
                    .offset(y: 12)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(red: 0.98, green: 0.73, blue: 0.22))
                    .frame(width: 78, height: 16)
                    .rotationEffect(.degrees(-4))
                    .offset(y: 2)
                Capsule()
                    .fill(Color(red: 0.34, green: 0.63, blue: 0.36))
                    .frame(width: 96, height: 13)
                    .overlay {
                        HStack(spacing: 14) {
                            Circle().fill(Color(red: 0.90, green: 0.24, blue: 0.20)).frame(width: 10)
                            Circle().fill(Color(red: 0.90, green: 0.24, blue: 0.20)).frame(width: 10)
                            Circle().fill(Color(red: 0.90, green: 0.24, blue: 0.20)).frame(width: 10)
                        }
                    }
                    .offset(y: -8)
                UnevenRoundedRectangle(
                    topLeadingRadius: 44,
                    bottomLeadingRadius: 10,
                    bottomTrailingRadius: 10,
                    topTrailingRadius: 44,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.82, blue: 0.43), Color(red: 0.94, green: 0.61, blue: 0.20)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 94, height: 43)
                .offset(y: -29)
                HStack(spacing: 17) {
                    Capsule().fill(.white.opacity(0.78)).frame(width: 8, height: 3).rotationEffect(.degrees(20))
                    Capsule().fill(.white.opacity(0.78)).frame(width: 8, height: 3).rotationEffect(.degrees(-8))
                    Capsule().fill(.white.opacity(0.78)).frame(width: 8, height: 3).rotationEffect(.degrees(18))
                }
                .offset(y: -37)
            }
            .offset(y: -1)

            Image(systemName: "sparkle")
                .font(.caption.weight(.bold))
                .foregroundStyle(TasteMapCoreTheme.brand)
                .offset(x: -53, y: -46)
            Image(systemName: "sparkle")
                .font(.caption2.weight(.bold))
                .foregroundStyle(TasteMapCoreTheme.brand)
                .offset(x: 54, y: -34)
        }
        .accessibilityLabel("Premium 汉堡候选主视觉")
    }
}

private struct FusePremiumBenefit: View {
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(TasteMapCoreTheme.brand)
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.subheadline.weight(.semibold)); Text(detail).font(.caption).foregroundStyle(TasteMapCoreTheme.textSecondary) }
            Spacer()
        }.padding(11).tasteMapCoreCard(radius: 14)
    }
}

private struct FuseSettingsCandidate: View {
    var body: some View {
        FusePage("设置", subtitle: "Legacy grouped tools · Current Settings foundation") {
            FuseSettingsGroup(title: "账户") {
                FuseFormRow(icon: "person.crop.circle", title: "Lafayette", value: "tm_demo_qa")
                FuseFormRow(icon: "person.text.rectangle", title: "编辑资料", value: "")
                FuseFormRow(icon: "rectangle.portrait.and.arrow.right", title: "退出登录", value: "")
            }
            FuseSettingsGroup(title: "数据与备份") {
                FuseFormRow(icon: "square.and.arrow.up", title: "导出 Backup v1", value: "不含照片原图")
                FuseFormRow(icon: "arrow.down.doc", title: "导入数据", value: "正式预检与确认")
                FuseFormRow(icon: "arrow.triangle.2.circlepath", title: "同步", value: "正常 · 0 待处理")
            }
            FuseSettingsGroup(title: "隐私与权限") {
                FuseFormRow(icon: "hand.raised.fill", title: "隐私", value: "仅朋友可见")
                FuseFormRow(icon: "location.fill", title: "位置", value: "使用 App 时允许")
                FuseFormRow(icon: "photo.fill", title: "照片", value: "有限访问")
            }
            FuseSettingsGroup(title: "系统") {
                FuseFormRow(icon: "internaldrive", title: "存储", value: "86.4 MB")
                FuseFormRow(icon: "questionmark.circle", title: "帮助", value: "")
                FuseFormRow(icon: "info.circle", title: "关于 Taste Map", value: "1.0 (428)")
            }
            FuseEntry(title: "Premium Active", detail: "正式状态仍由 StoreKit / server entitlement 决定", kind: .food)
        }
    }
}

private struct FuseSettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View { FuseSection(title) { VStack(spacing: 0) { content }.tasteMapCoreCard(radius: 16) } }
}
#endif
