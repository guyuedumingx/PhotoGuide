import SwiftUI

public struct PhotoGuideRootView: View {
  public init() {}

  public var body: some View {
    NavigationStack {
      HomeView()
        .toolbar(.hidden, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
  }
}

private struct HomeView: View {
  var body: some View {
    ZStack {
      PGTheme.canvas.ignoresSafeArea()
      AmbientGlow().allowsHitTesting(false)

      ScrollView {
        VStack(spacing: 30) {
          header.pgReveal(delay: 0.02, distance: 8)
          hero.pgReveal(delay: 0.07)
          featuredRecipe.pgReveal(delay: 0.13)
          browseHeader.pgReveal(delay: 0.18, distance: 8)
          quickRecipes.pgReveal(delay: 0.22)
          privacyNote.pgReveal(delay: 0.27, distance: 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 40)
      }
      .scrollIndicators(.hidden)
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "viewfinder")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.black)
        .frame(width: 38, height: 38)
        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

      VStack(alignment: .leading, spacing: 1) {
        Text("PhotoGuide")
          .font(.system(size: 18, weight: .bold, design: .rounded))
        Text(L("实时摄影教练"))
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(PGTheme.tertiaryText)
      }

      Spacer()

      NavigationLink {
        RecipeLibraryView()
          .toolbar(.hidden, for: .navigationBar)
      } label: {
        Image(systemName: "square.grid.2x2")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(.white.opacity(0.84))
          .frame(width: 42, height: 42)
          .pgGlassCircle()
      }
      .buttonStyle(PGPressButtonStyle())
      .accessibilityLabel(L("查看全部拍摄配方"))
      .accessibilityIdentifier("home.allRecipes")
    }
  }

  private var hero: some View {
    VStack(alignment: .leading, spacing: 13) {
      Text(L("把眼前这一幕\n拍得更好看"))
        .font(.system(size: 39, weight: .bold, design: .rounded))
        .minimumScaleFactor(0.82)
        .tracking(-1.0)
        .lineSpacing(0)

      Text(L("举起手机，我一次只告诉你下一步怎么调整。"))
        .font(.system(size: 16, weight: .regular))
        .foregroundStyle(PGTheme.secondaryText)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, 8)
  }

  private var featuredRecipe: some View {
    NavigationLink {
      RecipeDetailView(recipe: .environmentPortrait)
        .toolbar(.hidden, for: .navigationBar)
    } label: {
      FeaturedRecipeCard(recipe: .environmentPortrait)
    }
    .buttonStyle(PGPressButtonStyle())
    .accessibilityLabel(L("查看环境人像配方"))
    .accessibilityIdentifier("home.featured.environmentPortrait")
  }

  private var browseHeader: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(L("拍什么"))
        .font(.system(size: 20, weight: .bold, design: .rounded))
      Spacer()
      NavigationLink {
        RecipeLibraryView()
          .toolbar(.hidden, for: .navigationBar)
      } label: {
        HStack(spacing: 4) {
          Text(L("查看全部"))
          Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .bold))
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(PGTheme.secondaryText)
      }
      .buttonStyle(.plain)
    }
  }

  private var quickRecipes: some View {
    HStack(spacing: 12) {
      CompactRecipeCard(recipe: .soloPortrait)
      CompactRecipeCard(recipe: .travelScene)
    }
  }

  private var privacyNote: some View {
    HStack(spacing: 8) {
      Image(systemName: "lock.shield.fill")
      Text(L("基础视觉分析优先在设备上完成"))
    }
    .font(.system(size: 12, weight: .medium))
    .foregroundStyle(PGTheme.tertiaryText)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct RecipeLibraryView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var selectedCategory = RecipeCategory.all
  @Namespace private var categorySelection

  var body: some View {
    ZStack {
      PGTheme.canvas.ignoresSafeArea()
      AmbientGlow().allowsHitTesting(false)

      ScrollView {
        VStack(spacing: 24) {
          header.pgReveal(delay: 0.02, distance: 8)
          categoryStrip.pgReveal(delay: 0.07, distance: 8)
          recipeList.pgReveal(delay: 0.12)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 36)
      }
      .scrollIndicators(.hidden)
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        Button {
          dismiss()
        } label: {
          Image(systemName: "chevron.left")
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 42, height: 42)
            .pgGlassCircle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("返回"))

        Spacer()

        Text(L("拍摄配方"))
          .font(.system(size: 15, weight: .semibold))
          .accessibilityIdentifier("recipe.library.title")
          .foregroundStyle(.white.opacity(0.90))

        Spacer()
        Color.clear.frame(width: 42, height: 42)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text(L("先选你想拍出的感觉"))
          .font(.system(size: 30, weight: .bold, design: .rounded))
          .tracking(-0.55)
        Text(L("每个配方只保留最必要的实时提示。"))
          .font(.system(size: 15))
          .foregroundStyle(PGTheme.secondaryText)
      }
    }
  }

  private var categoryStrip: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        ForEach(RecipeCategory.allCases, id: \.self) { category in
          Button {
            if reduceMotion {
              selectedCategory = category
            } else {
              withAnimation(PGMotion.state) { selectedCategory = category }
            }
          } label: {
            Text(category.title)
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(selectedCategory == category ? .black : .white.opacity(0.72))
              .padding(.horizontal, 15)
              .frame(height: 36)
              .background {
                ZStack {
                  Capsule().fill(.white.opacity(0.055))
                  if selectedCategory == category {
                    Capsule()
                      .fill(PGTheme.accent)
                      .matchedGeometryEffect(id: "category.selection", in: categorySelection)
                  }
                }
              }
              .overlay(
                Capsule().stroke(
                  .white.opacity(selectedCategory == category ? 0 : 0.07), lineWidth: 0.7))
          }
          .buttonStyle(.plain)
        }
      }
    }
    .scrollIndicators(.hidden)
  }

  private var recipeList: some View {
    LazyVStack(spacing: 14) {
      ForEach(filteredRecipes) { recipe in
        if recipe.available {
          NavigationLink {
            RecipeDetailView(recipe: recipe)
              .toolbar(.hidden, for: .navigationBar)
          } label: {
            LibraryRecipeCard(recipe: recipe)
          }
          .buttonStyle(PGPressButtonStyle())
        } else {
          LibraryRecipeCard(recipe: recipe)
            .opacity(0.72)
        }
      }
    }
  }

  private var filteredRecipes: [PhotoRecipeCardModel] {
    let recipes = PhotoRecipeCardModel.catalog
    if selectedCategory == .all { return recipes }
    return recipes.filter { $0.category == selectedCategory }
  }
}

struct RecipeDetailView: View {
  @Environment(\.dismiss) private var dismiss
  let recipe: PhotoRecipeCardModel

  var body: some View {
    ZStack {
      PGTheme.canvas.ignoresSafeArea()
      ScrollView {
        VStack(spacing: 24) {
          hero.pgReveal(delay: 0.02, distance: 10)
          goalSummary.pgReveal(delay: 0.08, distance: 10)
          guidePreview.pgReveal(delay: 0.13, distance: 10)
          startButton.pgReveal(delay: 0.18, distance: 10)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 32)
      }
      .scrollIndicators(.hidden)
    }
  }

  private var hero: some View {
    ZStack(alignment: .top) {
      RoundedRectangle(cornerRadius: 30, style: .continuous)
        .fill(recipe.gradient)
        .frame(height: 360)

      RecipeSceneArtwork(kind: recipe.artwork)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

      LinearGradient(
        colors: [.black.opacity(0.16), .clear, .black.opacity(0.80)], startPoint: .top,
        endPoint: .bottom
      )
      .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

      HStack {
        Button {
          dismiss()
        } label: {
          Image(systemName: "chevron.left")
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 44, height: 44)
            .pgGlassCircle()
        }
        .buttonStyle(.plain)
        Spacer()
        Text(recipe.available ? L("实时指导") : L("即将推出"))
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(recipe.available ? .black : .white.opacity(0.76))
          .padding(.horizontal, 12)
          .frame(height: 34)
          .background(recipe.available ? PGTheme.accent : .black.opacity(0.34), in: Capsule())
      }
      .padding(16)

      VStack(alignment: .leading, spacing: 6) {
        Spacer()
        Text(recipe.title)
          .font(.system(size: 31, weight: .bold, design: .rounded))
          .tracking(-0.6)
        Text(recipe.subtitle)
          .font(.system(size: 15))
          .foregroundStyle(.white.opacity(0.70))
          .lineLimit(2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(22)
    }
    .frame(height: 360)
    .overlay(RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.08), lineWidth: 0.7))
  }

  private var goalSummary: some View {
    HStack(spacing: 0) {
      DetailMetric(icon: "person.crop.rectangle", title: L("人物"), subtitle: L("自然完整"))
      Divider().overlay(.white.opacity(0.08)).frame(height: 44)
      DetailMetric(icon: "mountain.2", title: L("环境"), subtitle: L("保留氛围"))
      Divider().overlay(.white.opacity(0.08)).frame(height: 44)
      DetailMetric(icon: "scope", title: L("指导"), subtitle: L("一次一步"))
    }
    .padding(.vertical, 16)
    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.07), lineWidth: 0.7))
  }

  private var guidePreview: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(L("拍摄时你会看到"))
        .font(.system(size: 18, weight: .bold, design: .rounded))

      HStack(spacing: 12) {
        Image(systemName: "arrow.right")
          .font(.system(size: 22, weight: .semibold))
          .foregroundStyle(PGTheme.accent)
          .frame(width: 42, height: 42)
          .background(PGTheme.accent.opacity(0.11), in: Circle())
        VStack(alignment: .leading, spacing: 3) {
          Text(L("往右一点"))
            .font(.system(size: 19, weight: .semibold))
          Text(L("让人物靠近右侧三分线"))
            .font(.system(size: 13))
            .foregroundStyle(PGTheme.secondaryText)
        }
        Spacer()
      }

      Text(L("不会给你堆参数，也不会锁住快门。做不到、想换方法、已经满意，都可以直接告诉它。"))
        .font(.system(size: 13))
        .foregroundStyle(PGTheme.tertiaryText)
        .lineSpacing(4)
    }
    .padding(18)
    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.065), lineWidth: 0.7))
  }

  @ViewBuilder
  private var startButton: some View {
    if recipe.available {
      NavigationLink {
        GuidanceCameraView()
          .toolbar(.hidden, for: .navigationBar)
      } label: {
        HStack {
          Text(L("开始拍摄"))
            .font(.system(size: 17, weight: .semibold))
          Spacer()
          Image(systemName: "camera.fill")
            .font(.system(size: 16, weight: .semibold))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 22)
        .frame(height: 58)
        .background(PGTheme.accent, in: Capsule())
      }
      .buttonStyle(PGPressButtonStyle())
      .accessibilityLabel(L("开始环境人像实时指导"))
      .accessibilityIdentifier("recipe.start.environmentPortrait")
    } else {
      Text(L("这个配方还在打磨中"))
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(PGTheme.tertiaryText)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(.white.opacity(0.045), in: Capsule())
    }
  }
}

private struct FeaturedRecipeCard: View {
  let recipe: PhotoRecipeCardModel

  var body: some View {
    ZStack(alignment: .bottom) {
      RoundedRectangle(cornerRadius: 30, style: .continuous)
        .fill(recipe.gradient)
        .frame(height: 310)
      RecipeSceneArtwork(kind: recipe.artwork)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
      LinearGradient(
        colors: [.clear, .black.opacity(0.74)], startPoint: .center, endPoint: .bottom
      )
      .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

      HStack(alignment: .bottom) {
        VStack(alignment: .leading, spacing: 6) {
          Text(recipe.title)
            .font(.system(size: 29, weight: .bold, design: .rounded))
          Text(recipe.subtitle)
            .font(.system(size: 14))
            .foregroundStyle(.white.opacity(0.68))
        }
        Spacer()
        Image(systemName: "arrow.up.right")
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(.black)
          .frame(width: 48, height: 48)
          .background(PGTheme.accent, in: Circle())
      }
      .padding(22)
    }
    .overlay(RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.08), lineWidth: 0.7))
  }
}

private struct CompactRecipeCard: View {
  let recipe: PhotoRecipeCardModel

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Image(systemName: recipe.icon)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(PGTheme.accent)
        Spacer()
        Text(recipe.available ? "" : L("即将推出"))
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(PGTheme.tertiaryText)
      }
      VStack(alignment: .leading, spacing: 4) {
        Text(recipe.title)
          .font(.system(size: 17, weight: .semibold))
        Text(recipe.shortSubtitle)
          .font(.system(size: 12))
          .foregroundStyle(PGTheme.secondaryText)
      }
    }
    .padding(17)
    .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.07), lineWidth: 0.7))
  }
}

private struct LibraryRecipeCard: View {
  let recipe: PhotoRecipeCardModel

  var body: some View {
    HStack(spacing: 16) {
      ZStack {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .fill(recipe.gradient)
        Image(systemName: recipe.icon)
          .font(.system(size: 26, weight: .semibold))
          .foregroundStyle(.white.opacity(0.78))
      }
      .frame(width: 92, height: 106)

      VStack(alignment: .leading, spacing: 7) {
        HStack {
          Text(recipe.title)
            .font(.system(size: 19, weight: .semibold))
          if !recipe.available {
            Text(L("即将推出"))
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(PGTheme.tertiaryText)
              .padding(.horizontal, 8)
              .frame(height: 22)
              .background(.white.opacity(0.055), in: Capsule())
          }
        }
        Text(recipe.subtitle)
          .font(.system(size: 13))
          .foregroundStyle(PGTheme.secondaryText)
          .lineLimit(2)
        Text(recipe.tags.joined(separator: "  ·  "))
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(PGTheme.tertiaryText)
      }
      Spacer(minLength: 0)
      if recipe.available {
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(.white.opacity(0.38))
      }
    }
    .padding(12)
    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.065), lineWidth: 0.7))
  }
}

private struct DetailMetric: View {
  let icon: String
  let title: String
  let subtitle: String

  var body: some View {
    VStack(spacing: 5) {
      Image(systemName: icon)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(PGTheme.accent)
      Text(title)
        .font(.system(size: 12, weight: .semibold))
      Text(subtitle)
        .font(.system(size: 10))
        .foregroundStyle(PGTheme.tertiaryText)
    }
    .frame(maxWidth: .infinity)
  }
}

private struct AmbientGlow: View {
  var body: some View {
    ZStack {
      Circle()
        .fill(PGTheme.accent2.opacity(0.10))
        .frame(width: 360, height: 360)
        .blur(radius: 95)
        .offset(x: 170, y: -320)
      Circle()
        .fill(PGTheme.accent.opacity(0.08))
        .frame(width: 320, height: 320)
        .blur(radius: 100)
        .offset(x: -170, y: 300)
    }
    .ignoresSafeArea()
  }
}

enum RecipeCategory: String, CaseIterable {
  case all
  case portrait
  case travel
  case night

  var title: String {
    switch self {
    case .all: L("全部")
    case .portrait: L("人像")
    case .travel: L("旅行")
    case .night: L("夜景")
    }
  }
}

enum RecipeArtworkKind {
  case environmentPortrait
  case soloPortrait
  case travelScene
  case nightPortrait
}

struct PhotoRecipeCardModel: Identifiable {
  let id: String
  let title: String
  let subtitle: String
  let shortSubtitle: String
  let icon: String
  let category: RecipeCategory
  let tags: [String]
  let available: Bool
  let artwork: RecipeArtworkKind
  let gradient: LinearGradient

  static let environmentPortrait = PhotoRecipeCardModel(
    id: "environment-portrait",
    title: L("环境人像"),
    subtitle: L("人物自然，景色也有存在感"),
    shortSubtitle: L("人物 · 景色"),
    icon: "person.and.background.dotted",
    category: .portrait,
    tags: [L("三分构图"), L("人物比例"), L("环境关系")],
    available: true,
    artwork: .environmentPortrait,
    gradient: LinearGradient(
      colors: [
        Color(red: 0.20, green: 0.29, blue: 0.31), Color(red: 0.055, green: 0.065, blue: 0.075),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing))

  static let soloPortrait = PhotoRecipeCardModel(
    id: "solo-portrait",
    title: L("单人人像"),
    subtitle: L("干净背景里，让人物更有表现力"),
    shortSubtitle: L("干净 · 自然"),
    icon: "person.fill",
    category: .portrait,
    tags: [L("姿态"), L("留白"), L("人物突出")],
    available: false,
    artwork: .soloPortrait,
    gradient: LinearGradient(
      colors: [
        Color(red: 0.22, green: 0.20, blue: 0.26), Color(red: 0.07, green: 0.06, blue: 0.08),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing))

  static let travelScene = PhotoRecipeCardModel(
    id: "travel-scene",
    title: L("旅行风景"),
    subtitle: L("保留空间层次，让景色更耐看"),
    shortSubtitle: L("层次 · 氛围"),
    icon: "mountain.2.fill",
    category: .travel,
    tags: [L("地平线"), L("前景"), L("主体锚点")],
    available: false,
    artwork: .travelScene,
    gradient: LinearGradient(
      colors: [
        Color(red: 0.17, green: 0.25, blue: 0.30), Color(red: 0.055, green: 0.07, blue: 0.08),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing))

  static let nightPortrait = PhotoRecipeCardModel(
    id: "night-portrait",
    title: L("夜景人像"),
    subtitle: L("控制高光和人物亮度，保住夜色氛围"),
    shortSubtitle: L("光线 · 氛围"),
    icon: "moon.stars.fill",
    category: .night,
    tags: [L("曝光"), L("高光"), L("稳定")],
    available: false,
    artwork: .nightPortrait,
    gradient: LinearGradient(
      colors: [
        Color(red: 0.12, green: 0.14, blue: 0.26), Color(red: 0.03, green: 0.035, blue: 0.06),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing))

  static let catalog = [environmentPortrait, soloPortrait, travelScene, nightPortrait]
}

private struct RecipeSceneArtwork: View {
  let kind: RecipeArtworkKind

  var body: some View {
    GeometryReader { geo in
      ZStack {
        switch kind {
        case .environmentPortrait:
          Image(systemName: "mountain.2.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.white.opacity(0.12))
            .frame(width: geo.size.width * 0.95)
            .position(x: geo.size.width * 0.55, y: geo.size.height * 0.40)
          Image(systemName: "person.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.white.opacity(0.34))
            .frame(width: 76)
            .position(x: geo.size.width * 0.69, y: geo.size.height * 0.53)
          thirdsLine(in: geo.size, xRatio: 0.67)
        case .soloPortrait:
          Circle()
            .fill(.white.opacity(0.06))
            .frame(width: 210, height: 210)
            .position(x: geo.size.width * 0.50, y: geo.size.height * 0.39)
          Image(systemName: "person.crop.square.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.white.opacity(0.24))
            .frame(width: 118)
            .position(x: geo.size.width * 0.52, y: geo.size.height * 0.48)
        case .travelScene:
          Image(systemName: "mountain.2.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.white.opacity(0.13))
            .frame(width: geo.size.width * 1.04)
            .position(x: geo.size.width * 0.52, y: geo.size.height * 0.46)
          Path { path in
            path.move(to: CGPoint(x: 0, y: geo.size.height * 0.58))
            path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height * 0.58))
          }
          .stroke(.white.opacity(0.14), lineWidth: 0.8)
        case .nightPortrait:
          ForEach(0..<8, id: \.self) { index in
            Circle()
              .fill(.white.opacity(index.isMultiple(of: 2) ? 0.12 : 0.07))
              .frame(width: CGFloat(18 + (index % 3) * 8))
              .blur(radius: 4)
              .position(
                x: geo.size.width * CGFloat(0.10 + Double(index) * 0.11),
                y: geo.size.height * CGFloat(0.22 + Double(index % 3) * 0.14))
          }
          Image(systemName: "person.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.white.opacity(0.22))
            .frame(width: 88)
            .position(x: geo.size.width * 0.58, y: geo.size.height * 0.55)
        }
      }
    }
  }

  private func thirdsLine(in size: CGSize, xRatio: CGFloat) -> some View {
    Path { path in
      let x = size.width * xRatio
      path.move(to: CGPoint(x: x, y: 20))
      path.addLine(to: CGPoint(x: x, y: size.height - 24))
    }
    .stroke(.white.opacity(0.18), style: StrokeStyle(lineWidth: 0.8, dash: [6, 7]))
  }
}
