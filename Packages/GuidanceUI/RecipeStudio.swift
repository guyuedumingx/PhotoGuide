import Combine
import Foundation
import PhotosUI
import RecipeKit
import SwiftUI
import UIKit

public enum RecipeAssetOrigin: String, Codable, Sendable {
  case generated
  case imported
  case custom
}

public struct StoredRecipeAsset: Identifiable, Codable, Sendable {
  public let id: String
  public let recipe: RecipeDTO
  public let origin: RecipeAssetOrigin
  public let createdAt: Date
  public let updatedAt: Date

  public init(id: String, recipe: RecipeDTO, origin: RecipeAssetOrigin, createdAt: Date = Date(), updatedAt: Date = Date()) {
    self.id = id
    self.recipe = recipe
    self.origin = origin
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

@MainActor
public final class RecipeAssetStore: ObservableObject {
  public static let shared = RecipeAssetStore()

  @Published public private(set) var userRecipes: [StoredRecipeAsset] = []
  @Published public private(set) var favoriteIDs: Set<String> = []

  private let defaults: UserDefaults
  private let recipesKey = "photoguide.recipe.assets.v2"
  private let legacyRecipesKey = "photoguide.recipe.assets.v1"
  private let favoritesKey = "photoguide.recipe.favorites.v1"

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    load()
  }

  public func isFavorite(_ id: String) -> Bool { favoriteIDs.contains(id) }

  public func toggleFavorite(_ id: String) {
    if favoriteIDs.contains(id) { favoriteIDs.remove(id) }
    else { favoriteIDs.insert(id) }
    persistFavorites()
  }

  @discardableResult
  public func save(_ recipe: RecipeDTO, origin: RecipeAssetOrigin) throws -> StoredRecipeAsset {
    let compiled = RecipeLoader().compile(recipe)
    guard compiled.isValid else {
      let message = compiled.validationIssues.filter { $0.severity == .error }.map(\.message).joined(separator: " · ")
      throw RecipeAssetError.invalidRecipe(message.isEmpty ? "Recipe validation failed." : message)
    }
    guard recipe.questionValidationErrors.isEmpty else {
      throw RecipeAssetError.invalidRecipe("Recipe contains an invalid question.")
    }
    guard !recipe.resolvedVisualQuestions.isEmpty else {
      throw RecipeAssetError.invalidRecipe("Recipe must contain at least one question.")
    }
    guard !recipe.resolvedVisualReferences.isEmpty else {
      throw RecipeAssetError.invalidRecipe("Recipe must contain at least one reference image.")
    }

    let normalized = normalizeUserID(recipe)
    let now = Date()
    if let index = userRecipes.firstIndex(where: { $0.id == normalized.id }) {
      let current = userRecipes[index]
      let updated = StoredRecipeAsset(id: normalized.id, recipe: normalized, origin: origin, createdAt: current.createdAt, updatedAt: now)
      userRecipes[index] = updated
      persistRecipes()
      return updated
    }

    let asset = StoredRecipeAsset(id: normalized.id, recipe: normalized, origin: origin, createdAt: now, updatedAt: now)
    userRecipes.insert(asset, at: 0)
    persistRecipes()
    return asset
  }

  @discardableResult
  public func importRecipe(data: Data) throws -> StoredRecipeAsset {
    let decoder = JSONDecoder()
    if let asset = try? decoder.decode(StoredRecipeAsset.self, from: data) {
      return try save(asset.recipe, origin: .imported)
    }
    return try save(try decoder.decode(RecipeDTO.self, from: data), origin: .imported)
  }

  public func delete(_ id: String) {
    userRecipes.removeAll { $0.id == id }
    favoriteIDs.remove(id)
    persistRecipes()
    persistFavorites()
  }

  public func recipe(id: String) -> RecipeDTO? { userRecipes.first(where: { $0.id == id })?.recipe }

  private func normalizeUserID(_ recipe: RecipeDTO) -> RecipeDTO {
    let collidesWithOfficial = RecipeLoader().catalog().contains { $0.source.id == recipe.id }
    let id = recipe.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || collidesWithOfficial
      ? "user.\(UUID().uuidString.lowercased())" : recipe.id
    guard id != recipe.id else { return recipe }
    return RecipeDTO(
      kind: recipe.kind, id: id, version: recipe.version, title: recipe.title, subtitle: recipe.subtitle,
      nodes: recipe.nodes, relations: recipe.relations, goals: recipe.goals, actions: recipe.actions,
      authorPolicy: recipe.authorPolicy, perception: recipe.perception, presentation: recipe.presentation,
      references: recipe.references, questions: recipe.questions, critic: recipe.critic)
  }

  private func load() {
    let data = defaults.data(forKey: recipesKey) ?? defaults.data(forKey: legacyRecipesKey)
    if let data, let assets = try? JSONDecoder().decode([StoredRecipeAsset].self, from: data) { userRecipes = assets }
    if let raw = defaults.array(forKey: favoritesKey) as? [String] { favoriteIDs = Set(raw) }
  }

  private func persistRecipes() {
    guard let data = try? JSONEncoder().encode(userRecipes) else { return }
    defaults.set(data, forKey: recipesKey)
  }

  private func persistFavorites() { defaults.set(Array(favoriteIDs).sorted(), forKey: favoritesKey) }
}

public enum RecipeAssetError: LocalizedError {
  case invalidRecipe(String)
  case unreadableImage

  public var errorDescription: String? {
    switch self {
    case .invalidRecipe(let message): message
    case .unreadableImage: "The selected image could not be read."
    }
  }
}

/// Until DJev is connected, reference-image creation builds a structurally valid
/// Recipe with the image embedded and a small generic comparison question set.
/// DJev later replaces only the question-generation implementation.
@MainActor
struct ReferenceImageRecipeGenerator {
  func generate(from image: UIImage) async throws -> RecipeDTO {
    guard image.size.width > 0, image.size.height > 0,
      let data = image.pgRecipeReferenceJPEG(maxDimension: 1280, quality: 0.78)
    else { throw RecipeAssetError.unreadableImage }

    return RecipeFactory.questionRecipe(
      id: "user.generated.\(UUID().uuidString.lowercased())",
      title: L("参考图 Recipe"),
      subtitle: L("由参考图创建，可继续编辑"),
      domain: .general,
      icon: "photo.badge.plus",
      tags: [L("参考图"), L("自定义")],
      references: [.init(id: "reference.1", imageData: data)],
      questions: RecipeFactory.defaultQuestions)
  }
}

private extension UIImage {
  func pgRecipeReferenceJPEG(maxDimension: CGFloat, quality: CGFloat) -> Data? {
    let scale = min(1, maxDimension / max(size.width, size.height))
    let target = CGSize(width: max(size.width * scale, 1), height: max(size.height * scale, 1))
    let renderer = UIGraphicsImageRenderer(size: target)
    let normalized = renderer.image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    return normalized.jpegData(compressionQuality: quality)
  }
}

struct RecipeEditorChoice: Identifiable, Equatable {
  let id: UUID
  var key: String
  var label: String
  var issue: String

  init(id: UUID = UUID(), key: String, label: String, issue: String = "") {
    self.id = id; self.key = key; self.label = label; self.issue = issue
  }
}

struct RecipeEditorQuestion: Identifiable, Equatable {
  let id: UUID
  var key: String
  var title: String
  var prompt: String
  var type: RecipeQuestionType
  var choices: [RecipeEditorChoice]
  var scoreMin: Double
  var scoreMax: Double
  var expectedMin: Double
  var expectedMax: Double
  var belowIssue: String
  var aboveIssue: String
  var expectedBoolean: Bool
  var mismatchIssue: String

  init(
    id: UUID = UUID(), key: String = "", title: String = "", prompt: String = "",
    type: RecipeQuestionType = .choice,
    choices: [RecipeEditorChoice] = [
      .init(key: "too_low", label: L("偏低"), issue: L("与参考图相比偏低")),
      .init(key: "matched", label: L("接近参考图")),
      .init(key: "too_high", label: L("偏高"), issue: L("与参考图相比偏高")),
    ],
    scoreMin: Double = 0, scoreMax: Double = 100, expectedMin: Double = 80, expectedMax: Double = 100,
    belowIssue: String = L("与参考图的相似度偏低"), aboveIssue: String = "",
    expectedBoolean: Bool = true, mismatchIssue: String = L("与参考图不一致")
  ) {
    self.id = id; self.key = key; self.title = title; self.prompt = prompt; self.type = type
    self.choices = choices; self.scoreMin = scoreMin; self.scoreMax = scoreMax
    self.expectedMin = expectedMin; self.expectedMax = expectedMax; self.belowIssue = belowIssue
    self.aboveIssue = aboveIssue; self.expectedBoolean = expectedBoolean; self.mismatchIssue = mismatchIssue
  }

  init(dto: RecipeQuestionDTO) {
    self.init(
      key: dto.id, title: dto.title, prompt: dto.prompt, type: dto.type,
      choices: (dto.choices ?? []).map { .init(key: $0.id, label: $0.label, issue: $0.issue ?? "") },
      scoreMin: dto.scoreMin ?? 0, scoreMax: dto.scoreMax ?? 100,
      expectedMin: dto.expectedMin ?? 80, expectedMax: dto.expectedMax ?? 100,
      belowIssue: dto.belowIssue ?? "", aboveIssue: dto.aboveIssue ?? "",
      expectedBoolean: dto.expectedBoolean ?? true, mismatchIssue: dto.mismatchIssue ?? "")
  }

  func dto(index: Int) -> RecipeQuestionDTO {
    let fallback = "question_\(index + 1)"
    let cleanKey = key.lowercased().replacingOccurrences(of: " ", with: "_").trimmingCharacters(in: .whitespacesAndNewlines)
    let id = cleanKey.isEmpty ? fallback : cleanKey
    let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? id : title.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    switch type {
    case .choice:
      return .choice(
        id: id, title: cleanTitle, prompt: cleanPrompt,
        options: choices.enumerated().map { offset, option in
          let optionID = option.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "option_\(offset + 1)" : option.key
          let issue = option.issue.trimmingCharacters(in: .whitespacesAndNewlines)
          return .init(id: optionID, label: option.label, issue: issue.isEmpty ? nil : issue)
        })
    case .score:
      return .score(
        id: id, title: cleanTitle, prompt: cleanPrompt,
        range: min(scoreMin, scoreMax)...max(scoreMin, scoreMax),
        expected: min(expectedMin, expectedMax)...max(expectedMin, expectedMax),
        belowIssue: belowIssue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : belowIssue,
        aboveIssue: aboveIssue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : aboveIssue)
    case .boolean:
      return .boolean(
        id: id, title: cleanTitle, prompt: cleanPrompt,
        expected: expectedBoolean, mismatchIssue: mismatchIssue.trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }
}

@MainActor
final class RecipeEditorModel: ObservableObject {
  @Published var title: String
  @Published var subtitle: String
  @Published var domain: RecipeDomain
  @Published var tags: String
  @Published var references: [RecipeReferenceDTO]
  @Published var questions: [RecipeEditorQuestion]

  let existingID: String?

  init(recipe: RecipeDTO? = nil) {
    existingID = recipe?.id
    title = recipe?.title ?? ""
    subtitle = recipe?.subtitle ?? ""
    domain = recipe?.resolvedPresentation.domain ?? .general
    tags = recipe?.resolvedPresentation.tags.joined(separator: ", ") ?? ""
    references = recipe?.references ?? []
    if let questions = recipe?.questions, !questions.isEmpty {
      self.questions = questions.map(RecipeEditorQuestion.init)
    } else {
      self.questions = RecipeFactory.defaultQuestions.map(RecipeEditorQuestion.init)
    }
  }

  var canSave: Bool {
    !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !references.isEmpty
      && !questions.isEmpty
      && questions.enumerated().allSatisfy { $0.element.dto(index: $0.offset).validate() == nil }
  }

  func addReference(_ image: UIImage) throws {
    guard let data = image.pgRecipeReferenceJPEG(maxDimension: 1280, quality: 0.78) else { throw RecipeAssetError.unreadableImage }
    references.append(.init(id: "reference.\(UUID().uuidString.lowercased())", imageData: data))
  }

  func removeReference(_ id: String) { references.removeAll { $0.id == id } }
  func addQuestion() { questions.append(.init()) }
  func removeQuestion(_ id: UUID) { questions.removeAll { $0.id == id } }

  func moveQuestion(_ id: UUID, offset: Int) {
    guard let index = questions.firstIndex(where: { $0.id == id }) else { return }
    let target = index + offset
    guard questions.indices.contains(target) else { return }
    questions.swapAt(index, target)
  }

  func makeRecipe() -> RecipeDTO {
    RecipeFactory.questionRecipe(
      id: existingID ?? "user.custom.\(UUID().uuidString.lowercased())",
      title: title.trimmingCharacters(in: .whitespacesAndNewlines),
      subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
      domain: domain,
      icon: Self.icon(for: domain),
      tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
      references: references,
      questions: questions.enumerated().map { $0.element.dto(index: $0.offset) })
  }

  private static func icon(for domain: RecipeDomain) -> String {
    switch domain {
    case .portrait: "person.crop.rectangle"
    case .travel: "figure.walk"
    case .food: "fork.knife"
    case .nature: "camera.macro"
    case .product: "cube.transparent"
    case .pet: "pawprint.fill"
    case .architecture: "building.2"
    case .landscape: "mountain.2"
    case .general: "viewfinder"
    }
  }
}

struct RecipeEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var store = RecipeAssetStore.shared
  @StateObject private var model: RecipeEditorModel
  @State private var selectedReference: PhotosPickerItem?
  @State private var saveError: String?

  let origin: RecipeAssetOrigin
  let onSaved: ((RecipeDTO) -> Void)?

  init(
    recipe: RecipeDTO? = nil,
    origin: RecipeAssetOrigin = .custom,
    onSaved: ((RecipeDTO) -> Void)? = nil
  ) {
    _model = StateObject(wrappedValue: RecipeEditorModel(recipe: recipe))
    self.origin = origin
    self.onSaved = onSaved
  }

  var body: some View {
    NavigationStack {
      ZStack {
        PGTheme.canvas.ignoresSafeArea()
        ScrollView {
          VStack(spacing: 18) {
            identityCard
            referencesCard
            questionsCard
            if let saveError {
              Text(saveError).font(.system(size: 12.5)).foregroundStyle(PGTheme.warning).frame(maxWidth: .infinity, alignment: .leading)
            }
            saveButton
          }
          .padding(18).padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
      }
      .navigationTitle(model.existingID == nil ? L("新建 Recipe") : L("编辑 Recipe"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarLeading) { Button(L("取消")) { dismiss() } } }
    }
    .preferredColorScheme(.dark)
    .onChange(of: selectedReference) { _, item in
      guard let item else { return }
      Task {
        do {
          guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            throw RecipeAssetError.unreadableImage
          }
          try model.addReference(image)
          saveError = nil
        } catch { saveError = error.localizedDescription }
        selectedReference = nil
      }
    }
  }

  private var identityCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      recipeField(L("名称"), text: $model.title, prompt: L("例如：我的咖啡探店"))
      recipeField(L("一句话说明"), text: $model.subtitle, prompt: L("这套 Recipe 想复刻什么风格"))
      HStack {
        Text(L("类型")).font(.system(size: 12, weight: .semibold)).foregroundStyle(PGTheme.secondaryText)
        Spacer()
        Picker(L("类型"), selection: $model.domain) {
          ForEach(RecipeDomain.allCases, id: \.self) { domain in Text(domainTitle(domain)).tag(domain) }
        }.labelsHidden().tint(PGTheme.accent)
      }
      recipeField(L("标签"), text: $model.tags, prompt: L("咖啡, 45度, 暖色"))
    }.pgRecipePanel()
  }

  private var referencesCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(L("参考图")).font(.system(size: 17, weight: .bold, design: .rounded))
          Text(L("DJev 只比较当前帧和这些参考图。至少保留一张。"))
            .font(.system(size: 12)).foregroundStyle(PGTheme.secondaryText)
        }
        Spacer()
        PhotosPicker(selection: $selectedReference, matching: .images) {
          Image(systemName: "plus").font(.system(size: 13, weight: .bold)).frame(width: 34, height: 34)
            .background(PGTheme.accent.opacity(0.11), in: Circle())
        }.foregroundStyle(PGTheme.accent)
      }

      if model.references.isEmpty {
        Text(L("添加一张参考图后才能保存 Recipe"))
          .font(.system(size: 13)).foregroundStyle(PGTheme.warning)
      } else {
        ScrollView(.horizontal) {
          HStack(spacing: 10) {
            ForEach(model.references) { reference in
              ZStack(alignment: .topTrailing) {
                Group {
                  if let data = reference.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                  } else { Color.white.opacity(0.04) }
                }
                .frame(width: 104, height: 132).clipShape(RoundedRectangle(cornerRadius: 16))
                Button { model.removeReference(reference.id) } label: {
                  Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 25, height: 25)
                    .background(.black.opacity(0.55), in: Circle())
                }.buttonStyle(.plain).padding(6)
              }
            }
          }
        }.scrollIndicators(.hidden)
      }
    }.pgRecipePanel()
  }

  private var questionsCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(L("判断问题")).font(.system(size: 17, weight: .bold, design: .rounded))
          Text(L("只定义比较问题和差距文本；不定义动作。列表顺序就是拍摄时的展示顺序。"))
            .font(.system(size: 12)).foregroundStyle(PGTheme.secondaryText)
        }
        Spacer()
        Button(action: model.addQuestion) {
          Image(systemName: "plus").font(.system(size: 13, weight: .bold)).frame(width: 34, height: 34)
            .background(PGTheme.accent.opacity(0.11), in: Circle())
        }.foregroundStyle(PGTheme.accent)
      }

      ForEach($model.questions) { $question in
        questionEditor($question)
      }
    }.pgRecipePanel()
  }

  private func questionEditor(_ question: Binding<RecipeEditorQuestion>) -> some View {
    let questionIndex = model.questions.firstIndex(where: { $0.id == question.wrappedValue.id }) ?? 0
    let isFirst = questionIndex == 0
    let isLast = questionIndex == max(model.questions.count - 1, 0)

    return VStack(alignment: .leading, spacing: 11) {
      HStack(spacing: 8) {
        TextField(L("问题 ID"), text: question.key).textInputAutocapitalization(.never).autocorrectionDisabled()
        Picker("", selection: question.type) {
          Text("Choice").tag(RecipeQuestionType.choice)
          Text("Score").tag(RecipeQuestionType.score)
          Text("Yes/No").tag(RecipeQuestionType.boolean)
        }.labelsHidden().tint(PGTheme.accent)
        Button { model.moveQuestion(question.wrappedValue.id, offset: -1) } label: {
          Image(systemName: "arrow.up").font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(.plain)
        .disabled(isFirst)
        .opacity(isFirst ? 0.28 : 1)
        .accessibilityLabel(L("上移问题"))

        Button { model.moveQuestion(question.wrappedValue.id, offset: 1) } label: {
          Image(systemName: "arrow.down").font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(.plain)
        .disabled(isLast)
        .opacity(isLast ? 0.28 : 1)
        .accessibilityLabel(L("下移问题"))
        Button(role: .destructive) { model.removeQuestion(question.wrappedValue.id) } label: {
          Image(systemName: "trash").font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.plain)
        .disabled(model.questions.count <= 1)
        .opacity(model.questions.count <= 1 ? 0.28 : 1)
      }
      .font(.system(size: 13.5, weight: .semibold))

      TextField(L("显示名称"), text: question.title)
      TextField(L("问 DJev 的问题，例如：当前拍摄角度与参考图相比？"), text: question.prompt, axis: .vertical).lineLimit(2...4)

      switch question.wrappedValue.type {
      case .choice: choiceEditor(question)
      case .score: scoreEditor(question)
      case .boolean: booleanEditor(question)
      }
    }
    .font(.system(size: 13))
    .padding(13)
    .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(PGTheme.hairline, lineWidth: 0.6))
  }

  private func choiceEditor(_ question: Binding<RecipeEditorQuestion>) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(L("Choice：问题文本留空的选项代表“接近参考图”"))
        .font(.system(size: 11.5)).foregroundStyle(PGTheme.tertiaryText)
      ForEach(question.choices) { $option in
        VStack(spacing: 7) {
          HStack {
            TextField("value", text: $option.key).textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField(L("选项"), text: $option.label)

            Button(role: .destructive) {
              let optionID = option.id
              question.wrappedValue.choices.removeAll { $0.id == optionID }
            } label: {
              Image(systemName: "trash")
                .font(.system(size: 11.5, weight: .semibold))
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(question.wrappedValue.choices.count <= 2)
            .opacity(question.wrappedValue.choices.count <= 2 ? 0.28 : 1)
            .accessibilityLabel(L("删除选项"))
          }
          TextField(L("若选中它，显示什么问题；目标选项留空"), text: $option.issue, axis: .vertical).lineLimit(1...3)
        }
        .padding(9).background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
      }
      Button(L("添加选项")) { question.wrappedValue.choices.append(.init(key: "", label: "")) }
        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(PGTheme.accent)
    }
  }

  private func scoreEditor(_ question: Binding<RecipeEditorQuestion>) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(L("分数范围")); Spacer()
        TextField("0", value: question.scoreMin, format: .number).frame(width: 54).multilineTextAlignment(.trailing)
        Text("–")
        TextField("100", value: question.scoreMax, format: .number).frame(width: 54).multilineTextAlignment(.trailing)
      }
      HStack {
        Text(L("目标范围")); Spacer()
        TextField("80", value: question.expectedMin, format: .number).frame(width: 54).multilineTextAlignment(.trailing)
        Text("–")
        TextField("100", value: question.expectedMax, format: .number).frame(width: 54).multilineTextAlignment(.trailing)
      }
      TextField(L("低于目标时显示的问题"), text: question.belowIssue)
      TextField(L("高于目标时显示的问题（可留空）"), text: question.aboveIssue)
    }
  }

  private func booleanEditor(_ question: Binding<RecipeEditorQuestion>) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      Toggle(L("期望答案为 Yes"), isOn: question.expectedBoolean).tint(PGTheme.accent)
      TextField(L("答案不符合时显示的问题"), text: question.mismatchIssue, axis: .vertical).lineLimit(1...3)
    }
  }

  private var saveButton: some View {
    Button {
      do {
        let asset = try store.save(model.makeRecipe(), origin: origin)
        onSaved?(asset.recipe)
        dismiss()
      } catch { saveError = error.localizedDescription }
    } label: {
      HStack { Text(L("保存 Recipe")).font(.system(size: 16.5, weight: .semibold)); Spacer(); Image(systemName: "checkmark") }
        .foregroundStyle(.black).padding(.horizontal, 20).frame(height: 56).background(PGTheme.accent, in: Capsule())
    }
    .buttonStyle(PGPressButtonStyle()).disabled(!model.canSave).opacity(model.canSave ? 1 : 0.42)
  }

  private func recipeField(_ title: String, text: Binding<String>, prompt: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(PGTheme.secondaryText)
      TextField(prompt, text: text).font(.system(size: 15, weight: .medium)).padding(.horizontal, 13).frame(height: 45)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(PGTheme.hairline, lineWidth: 0.6))
    }
  }

  private func domainTitle(_ domain: RecipeDomain) -> String {
    switch domain {
    case .portrait: L("人像"); case .travel: L("旅行"); case .food: L("美食"); case .nature: L("自然")
    case .product: L("静物"); case .pet: L("宠物"); case .architecture: L("建筑"); case .landscape: L("风景"); case .general: L("通用")
    }
  }
}

private extension View {
  func pgRecipePanel() -> some View {
    self.padding(16).frame(maxWidth: .infinity, alignment: .leading)
      .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 22).stroke(PGTheme.hairline, lineWidth: 0.7))
  }
}
