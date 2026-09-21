import Foundation
import PhotosUI
import RecipeKit
import SwiftUI
import UniformTypeIdentifiers
import UIKit

public struct PhotoGuideRootView: View {
  @ObservedObject private var store = RecipeAssetStore.shared
  @AppStorage("photoguide.activeRecipeID.v1") private var activeRecipeID = ""
  @State private var showRecipeMenu = false

  public init() {}

  public var body: some View {
    GuidanceCameraView(
      recipe: activeRecipe,
      onMenu: { showRecipeMenu = true },
      onSelectRecipe: { recipe in activeRecipeID = recipe.id })
      .id(activeRecipeIdentity)
      .preferredColorScheme(.dark)
      .sheet(isPresented: $showRecipeMenu) {
        RecipeMenuView(
          activeRecipeID: activeRecipe.id,
          onSelect: { recipe in
            activeRecipeID = recipe.id
            showRecipeMenu = false
          })
          .presentationDetents([.large])
          .presentationDragIndicator(.visible)
          .presentationCornerRadius(30)
          .presentationBackground(PGTheme.canvas)
      }
  }

  private var activeRecipe: RecipeDTO {
    if let user = store.recipe(id: activeRecipeID),
      !user.resolvedVisualReferences.isEmpty, !user.resolvedVisualQuestions.isEmpty
    {
      return user
    }
    return Self.cameraShellRecipe
  }

  private var activeRecipeIdentity: String {
    if let asset = store.userRecipes.first(where: { $0.id == activeRecipe.id }) {
      return "\(asset.id):\(asset.updatedAt.timeIntervalSince1970)"
    }
    return activeRecipe.id
  }

  private static let cameraShellRecipe = RecipeDTO(
    id: "camera.shell",
    title: "PhotoGuide",
    subtitle: L("选择一个 Recipe 开始比较"),
    perception: .init(subjectStrategy: .scene, anchorStrategy: RecipeAnchorStrategy.none, allowsManualSubjectSelection: false),
    presentation: .init(domain: .general, icon: "viewfinder", tags: []),
    references: nil,
    questions: nil,
    critic: nil)
}

private struct RecipeMenuView: View {
  @Environment(\.dismiss) private var dismiss
  let activeRecipeID: String
  let onSelect: (RecipeDTO) -> Void

  var body: some View {
    NavigationStack {
      ZStack {
        PGTheme.canvas.ignoresSafeArea()
        VStack(spacing: 14) {
          menuHeader
          NavigationLink {
            RecipeSquareView(activeRecipeID: activeRecipeID, onSelect: onSelect)
          } label: {
            RecipeMenuRow(
              icon: "square.grid.2x2.fill",
              title: L("Recipe 广场"),
              subtitle: L("浏览和选择拍摄方法"))
          }
          NavigationLink {
            MyRecipesView(activeRecipeID: activeRecipeID, onSelect: onSelect)
          } label: {
            RecipeMenuRow(
              icon: "person.crop.square.filled.and.at.rectangle",
              title: L("我的 Recipe"),
              subtitle: L("收藏、导入和自己创建的 Recipe"))
          }
          NavigationLink {
            CreateRecipeView(onSaved: onSelect)
          } label: {
            RecipeMenuRow(
              icon: "plus.square.fill",
              title: L("创建 Recipe"),
              subtitle: L("用参考图或从空白开始"))
          }
          Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
      }
      .toolbar(.hidden, for: .navigationBar)
    }
    .foregroundStyle(.white)
  }

  private var menuHeader: some View {
    HStack(alignment: .center) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Recipe")
          .font(.system(size: 30, weight: .bold, design: .rounded))
        Text(L("选择、管理或创建你的拍摄方法"))
          .font(.system(size: 13.5))
          .foregroundStyle(PGTheme.secondaryText)
      }
      Spacer()
      Button { dismiss() } label: {
        Image(systemName: "xmark")
          .font(.system(size: 14, weight: .bold))
          .frame(width: 42, height: 42)
          .pgGlassCircle()
      }
      .buttonStyle(PGPressButtonStyle())
      .accessibilityLabel(L("关闭"))
    }
    .padding(.bottom, 8)
  }
}

private struct RecipeMenuRow: View {
  let icon: String
  let title: String
  let subtitle: String

  var body: some View {
    HStack(spacing: 16) {
      Image(systemName: icon)
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(PGTheme.accent)
        .frame(width: 48, height: 48)
        .background(PGTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 17, weight: .semibold, design: .rounded))
        Text(subtitle)
          .font(.system(size: 12.5))
          .foregroundStyle(PGTheme.secondaryText)
          .lineLimit(2)
      }
      Spacer()
      Image(systemName: "chevron.right")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(PGTheme.tertiaryText)
    }
    .padding(15)
    .frame(maxWidth: .infinity)
    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.07), lineWidth: 0.7))
  }
}

private struct RecipeSquareView: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var store = RecipeAssetStore.shared
  let activeRecipeID: String
  let onSelect: (RecipeDTO) -> Void

  private var squareRecipes: [RecipeDTO] {
    // The remote marketplace is intentionally not faked. Until it is connected,
    // the square exposes question-core Recipes already present on the device.
    let local = store.userRecipes.map(\.recipe)
    return local.filter { !$0.resolvedVisualReferences.isEmpty && !$0.resolvedVisualQuestions.isEmpty }
  }

  var body: some View {
    RecipeListPage(
      title: L("Recipe 广场"),
      subtitle: L("选择一个 Recipe，立即回到相机"),
      recipes: squareRecipes,
      activeRecipeID: activeRecipeID,
      emptyTitle: L("广场还没有可用 Recipe"),
      emptyDetail: L("创建或导入后会出现在这里；不会用旧格式 Recipe 冒充新的参考图比较流程。"),
      onBack: { dismiss() },
      onSelect: onSelect,
      onEdit: nil,
      onDelete: nil)
  }
}

private struct MyRecipesView: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var store = RecipeAssetStore.shared
  @State private var editingAsset: StoredRecipeAsset?
  @State private var deleteCandidate: StoredRecipeAsset?

  let activeRecipeID: String
  let onSelect: (RecipeDTO) -> Void

  private var assets: [StoredRecipeAsset] {
    store.userRecipes
      .filter { !$0.recipe.resolvedVisualReferences.isEmpty && !$0.recipe.resolvedVisualQuestions.isEmpty }
      .sorted { lhs, rhs in
        let lhsFavorite = store.isFavorite(lhs.id)
        let rhsFavorite = store.isFavorite(rhs.id)
        if lhsFavorite != rhsFavorite { return lhsFavorite }
        return lhs.updatedAt > rhs.updatedAt
      }
  }

  private var recipes: [RecipeDTO] { assets.map(\.recipe) }

  var body: some View {
    RecipeListPage(
      title: L("我的 Recipe"),
      subtitle: L("你创建、导入和保存的 Recipe"),
      recipes: recipes,
      activeRecipeID: activeRecipeID,
      emptyTitle: L("还没有 Recipe"),
      emptyDetail: L("从创建页加入参考图和问题，就可以直接用于相机。"),
      onBack: { dismiss() },
      onSelect: onSelect,
      onEdit: { recipe in
        editingAsset = assets.first(where: { $0.id == recipe.id })
      },
      onDelete: { recipe in
        deleteCandidate = assets.first(where: { $0.id == recipe.id })
      })
      .sheet(item: $editingAsset) { asset in
        RecipeEditorView(recipe: asset.recipe, origin: asset.origin)
      }
      .confirmationDialog(
        L("删除 Recipe？"),
        isPresented: Binding(
          get: { deleteCandidate != nil },
          set: { if !$0 { deleteCandidate = nil } }),
        titleVisibility: .visible
      ) {
        Button(L("删除"), role: .destructive) {
          guard let asset = deleteCandidate else { return }
          store.delete(asset.id)
          deleteCandidate = nil
          UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        Button(L("取消"), role: .cancel) { deleteCandidate = nil }
      } message: {
        Text(L("删除后无法恢复。"))
      }
  }
}

private struct RecipeListPage: View {
  @ObservedObject private var store = RecipeAssetStore.shared
  let title: String
  let subtitle: String
  let recipes: [RecipeDTO]
  let activeRecipeID: String
  let emptyTitle: String
  let emptyDetail: String
  let onBack: () -> Void
  let onSelect: (RecipeDTO) -> Void
  let onEdit: ((RecipeDTO) -> Void)?
  let onDelete: ((RecipeDTO) -> Void)?

  var body: some View {
    ZStack {
      PGTheme.canvas.ignoresSafeArea()
      ScrollView {
        VStack(spacing: 16) {
          pageHeader
          if recipes.isEmpty { emptyState.padding(.top, 52) }
          else {
            ForEach(recipes, id: \.id) { recipe in
              RecipeSelectionCard(
                recipe: recipe,
                selected: recipe.id == activeRecipeID,
                favorite: store.isFavorite(recipe.id),
                onSelect: { onSelect(recipe) },
                onFavorite: {
                  store.toggleFavorite(recipe.id)
                  UISelectionFeedbackGenerator().selectionChanged()
                },
                onEdit: onEdit.map { edit in { edit(recipe) } },
                onDelete: onDelete.map { delete in { delete(recipe) } })
                .accessibilityIdentifier("recipe.row.\(recipe.id)")
            }
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 36)
      }
      .scrollIndicators(.hidden)
    }
    .toolbar(.hidden, for: .navigationBar)
    .foregroundStyle(.white)
  }

  private var pageHeader: some View {
    HStack(spacing: 14) {
      Button(action: onBack) {
        Image(systemName: "chevron.left")
          .font(.system(size: 15, weight: .bold))
          .frame(width: 42, height: 42)
          .pgGlassCircle()
      }
      .buttonStyle(PGPressButtonStyle())
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.system(size: 24, weight: .bold, design: .rounded))
        Text(subtitle).font(.system(size: 12.5)).foregroundStyle(PGTheme.secondaryText)
      }
      Spacer()
    }
  }

  private var emptyState: some View {
    VStack(spacing: 12) {
      Image(systemName: "square.grid.2x2")
        .font(.system(size: 28, weight: .medium))
        .foregroundStyle(PGTheme.accent)
        .frame(width: 64, height: 64)
        .background(PGTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      Text(emptyTitle).font(.system(size: 18, weight: .semibold, design: .rounded))
      Text(emptyDetail)
        .font(.system(size: 13))
        .foregroundStyle(PGTheme.secondaryText)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 300)
    }
    .frame(maxWidth: .infinity)
  }
}

private struct RecipeSelectionCard: View {
  let recipe: RecipeDTO
  let selected: Bool
  let favorite: Bool
  let onSelect: () -> Void
  let onFavorite: () -> Void
  let onEdit: (() -> Void)?
  let onDelete: (() -> Void)?

  var body: some View {
    HStack(spacing: 10) {
      Button(action: onSelect) {
        HStack(spacing: 14) {
          ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .fill(PGTheme.accent.opacity(selected ? 0.16 : 0.08))
            if let data = recipe.resolvedVisualReferences.first?.imagePayload,
              let image = UIImage(data: data)
            {
              Image(uiImage: image)
                .resizable()
                .scaledToFill()
            } else {
              Image(systemName: recipe.resolvedPresentation.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(selected ? PGTheme.accent : .white.opacity(0.76))
            }
          }
          .frame(width: 58, height: 58)
          .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .stroke(selected ? PGTheme.accent.opacity(0.42) : .white.opacity(0.06), lineWidth: 0.8))

          VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
              Text(L(recipe.title))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .lineLimit(1)
              if selected {
                Text(L("使用中"))
                  .font(.system(size: 9.5, weight: .bold))
                  .foregroundStyle(.black)
                  .padding(.horizontal, 7)
                  .frame(height: 20)
                  .background(PGTheme.accent, in: Capsule())
              }
            }
            Text(L(recipe.subtitle))
              .font(.system(size: 12.5))
              .foregroundStyle(PGTheme.secondaryText)
              .lineLimit(1)
            Text("\(recipe.resolvedVisualReferences.count) \(L("参考图")) · \(recipe.resolvedVisualQuestions.count) \(L("问题"))")
              .font(.system(size: 10.5, weight: .medium))
              .foregroundStyle(PGTheme.tertiaryText)
          }
          Spacer(minLength: 4)
          Image(systemName: selected ? "checkmark.circle.fill" : "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(selected ? PGTheme.accent : PGTheme.tertiaryText)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(PGPressButtonStyle())
      .accessibilityLabel(L(recipe.title))

      VStack(spacing: 7) {
        Button(action: onFavorite) {
          Image(systemName: favorite ? "star.fill" : "star")
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(favorite ? PGTheme.accent : PGTheme.tertiaryText)
            .frame(width: 34, height: 34)
            .background(.white.opacity(0.045), in: Circle())
        }
        .buttonStyle(PGPressButtonStyle())
        .accessibilityLabel(favorite ? L("取消收藏") : L("收藏"))
        .accessibilityIdentifier("recipe.favorite.\(recipe.id)")

        if onEdit != nil || onDelete != nil {
          Menu {
            if let onEdit {
              Button(action: onEdit) {
                Label(L("编辑"), systemImage: "square.and.pencil")
              }
            }
            if let onDelete {
              Button(role: .destructive, action: onDelete) {
                Label(L("删除"), systemImage: "trash")
              }
            }
          } label: {
            Image(systemName: "ellipsis")
              .font(.system(size: 13.5, weight: .semibold))
              .foregroundStyle(PGTheme.tertiaryText)
              .frame(width: 34, height: 30)
              .background(.white.opacity(0.045), in: Circle())
          }
          .accessibilityLabel(L("管理"))
          .accessibilityIdentifier("recipe.manage.\(recipe.id)")
        }
      }
    }
    .padding(13)
    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(selected ? PGTheme.accent.opacity(0.22) : .white.opacity(0.065), lineWidth: 0.8))
  }
}

private struct CreateRecipeView: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var store = RecipeAssetStore.shared
  @State private var selectedPhotoItem: PhotosPickerItem?
  @State private var generatedRecipe: RecipeDTO?
  @State private var showBlankEditor = false
  @State private var showImporter = false
  @State private var isGenerating = false
  @State private var errorText: String?
  let onSaved: (RecipeDTO) -> Void

  var body: some View {
    ZStack {
      PGTheme.canvas.ignoresSafeArea()
      VStack(spacing: 18) {
        header
        Text(L("Recipe 只需要参考图和按作者顺序排列的问题。DJev 以后只回答 Choice、Score 或 Yes/No。"))
          .font(.system(size: 13.5))
          .foregroundStyle(PGTheme.secondaryText)
          .lineSpacing(3)
          .frame(maxWidth: .infinity, alignment: .leading)

        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
          CreateRecipeRow(
            icon: "photo.badge.plus",
            title: L("从参考图开始"),
            subtitle: L("加入一张示例图，再编辑比较问题"))
        }
        .buttonStyle(PGPressButtonStyle())

        Button { showBlankEditor = true } label: {
          CreateRecipeRow(
            icon: "square.and.pencil",
            title: L("空白 Recipe"),
            subtitle: L("自己加入参考图和问题"))
        }
        .buttonStyle(PGPressButtonStyle())

        Button { showImporter = true } label: {
          CreateRecipeRow(
            icon: "square.and.arrow.down",
            title: L("导入 JSON"),
            subtitle: L("导入别人分享的 Recipe"))
        }
        .buttonStyle(PGPressButtonStyle())

        if isGenerating { ProgressView().tint(PGTheme.accent).padding(.top, 8) }
        if let errorText {
          Text(errorText).font(.system(size: 12.5)).foregroundStyle(PGTheme.warning)
        }
        Spacer()
      }
      .padding(.horizontal, 20)
      .padding(.top, 8)
      .padding(.bottom, 24)
    }
    .toolbar(.hidden, for: .navigationBar)
    .foregroundStyle(.white)
    .onChange(of: selectedPhotoItem) { _, item in
      guard let item else { return }
      isGenerating = true
      errorText = nil
      Task {
        defer { isGenerating = false }
        do {
          guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data)
          else { throw RecipeAssetError.unreadableImage }
          generatedRecipe = try await ReferenceImageRecipeGenerator().generate(from: image)
        } catch { errorText = error.localizedDescription }
      }
    }
    .sheet(isPresented: $showBlankEditor) {
      RecipeEditorView(origin: .custom, onSaved: { recipe in onSaved(recipe) })
    }
    .sheet(
      isPresented: Binding(
        get: { generatedRecipe != nil },
        set: { if !$0 { generatedRecipe = nil } })
    ) {
      if let generatedRecipe {
        RecipeEditorView(recipe: generatedRecipe, origin: .generated, onSaved: { recipe in onSaved(recipe) })
      }
    }
    .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
      do {
        let url = try result.get()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let asset = try store.importRecipe(data: Data(contentsOf: url))
        errorText = nil
        onSaved(asset.recipe)
      } catch { errorText = error.localizedDescription }
    }
  }

  private var header: some View {
    HStack(spacing: 14) {
      Button { dismiss() } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 15, weight: .bold))
          .frame(width: 42, height: 42)
          .pgGlassCircle()
      }
      .buttonStyle(PGPressButtonStyle())
      VStack(alignment: .leading, spacing: 2) {
        Text(L("创建 Recipe"))
          .font(.system(size: 24, weight: .bold, design: .rounded))
        Text(L("Reference + Questions"))
          .font(.system(size: 12.5))
          .foregroundStyle(PGTheme.secondaryText)
      }
      Spacer()
    }
  }

}

private struct CreateRecipeRow: View {
  let icon: String
  let title: String
  let subtitle: String

  var body: some View {
    HStack(spacing: 15) {
      Image(systemName: icon)
        .font(.system(size: 19, weight: .semibold))
        .foregroundStyle(PGTheme.accent)
        .frame(width: 48, height: 48)
        .background(PGTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.system(size: 16.5, weight: .semibold, design: .rounded))
        Text(subtitle).font(.system(size: 12.5)).foregroundStyle(PGTheme.secondaryText)
      }
      Spacer()
      Image(systemName: "chevron.right")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(PGTheme.tertiaryText)
    }
    .padding(14)
    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.065), lineWidth: 0.7))
  }
}
