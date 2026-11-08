import SwiftData
import SwiftUI
import UIKit

struct CardEditorView: View {
    private enum Field: String, CaseIterable, Hashable {
        case account = "card.account"
        case customNetwork = "card.customNetwork"
        case productName = "card.productName"
        case nickname = "card.nickname"
        case lastFour = "card.lastFour"
        case notes = "card.notes"
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let card: Card?
    let accounts: [CreditCardAccount]
    let networks: [CardNetwork]

    @FocusState private var focusedField: Field?
    @State private var accountID: UUID
    @State private var networkSelection: CardNetworkSelection
    @State private var customNetworkName: String
    @State private var productName: String
    @State private var nickname: String
    @State private var lastFour: String
    @State private var status: CardStatus
    @State private var notes: String
    @State private var errorMessage: String?
    @State private var showingValidationErrors = false

    init(card: Card?, accounts: [CreditCardAccount], networks: [CardNetwork]) {
        self.card = card
        self.accounts = accounts
        self.networks = networks
        _accountID = State(initialValue: card?.account.id ?? accounts.first?.id ?? UUID())
        _networkSelection = State(initialValue: CardNetworkSelection.matching(card?.networks ?? []))
        _customNetworkName = State(initialValue: card?.networks.first(where: { !$0.isBuiltIn })?.displayName ?? "")
        _productName = State(initialValue: card?.productName ?? "")
        _nickname = State(initialValue: card?.nickname ?? "")
        _lastFour = State(initialValue: card?.lastFour ?? "")
        _status = State(initialValue: card?.status ?? .active)
        _notes = State(initialValue: card?.notes ?? "")
    }

    private var editSnapshot: String {
        editorSnapshot(accountID, networkSelection, customNetworkName, productName, nickname, lastFour, status, notes)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                Form {
                    Section("卡片") {
                        Picker("信用卡账户", selection: $accountID) {
                            ForEach(accounts, id: \.id) { account in
                                Text(CardPilotUI.accountName(account)).tag(account.id)
                            }
                        }
                        .id(Field.account)
                        fieldError(.account)
                        Text("卡组织组合")
                            .font(.subheadline.weight(.semibold))
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(CardNetworkSelection.singleChoices) { choice in
                                NetworkChoiceTile(choice: choice, selection: $networkSelection, customName: customNetworkName)
                            }
                        }
                        Text("双标卡")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(CardNetworkSelection.dualChoices) { choice in
                                NetworkChoiceTile(choice: choice, selection: $networkSelection, customName: customNetworkName)
                            }
                        }
                        NetworkChoiceTile(choice: .other, selection: $networkSelection, customName: customNetworkName)
                        if networkSelection == .other {
                            TextField("卡组织名称", text: $customNetworkName)
                                .focused($focusedField, equals: .customNetwork)
                                .id(Field.customNetwork)
                            fieldError(.customNetwork)
                        }
                        TextField("卡产品名称", text: $productName)
                            .focused($focusedField, equals: .productName)
                            .id(Field.productName)
                        fieldError(.productName)
                        TextField("昵称（可选）", text: $nickname)
                            .focused($focusedField, equals: .nickname)
                        TextField("末四位", text: $lastFour)
                            .keyboardType(.numberPad)
                            .textContentType(.none)
                            .focused($focusedField, equals: .lastFour)
                            .id(Field.lastFour)
                        fieldError(.lastFour)
                        if dynamicTypeSize.isAccessibilitySize {
                            statusPicker.pickerStyle(.inline)
                        } else {
                            statusPicker
                        }
                        TextField("备注（可选）", text: $notes, axis: .vertical)
                            .focused($focusedField, equals: .notes)
                            .accessibilityIdentifier("card.notes")
                    }
                    Text("不要录入完整卡号或 CVV。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let errorMessage {
                        InlineErrorView(message: errorMessage)
                    }
                }
                .scrollDismissesKeyboard(.immediately)
                // Leave room for the numeric accessory as the Form settles;
                // its last input row can otherwise extend under the toolbar.
                .safeAreaPadding(.bottom, focusedField == .lastFour ? 16 : 0)
                .accessibilityIdentifier("card.editor.form")
                .onChange(of: focusedField) { _, field in
                    guard field == .lastFour else { return }
                    revealLastFour(using: scrollProxy)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)) { _ in
                    revealLastFour(using: scrollProxy)
                }
                .navigationTitle(card == nil ? "添加卡片" : "编辑卡片")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { EditorCancelButton() }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { save(using: scrollProxy) } }
                    if focusedField == .lastFour {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("收起键盘") { focusedField = nil }
                                .frame(minWidth: 44, minHeight: 44)
                                .accessibilityIdentifier("card.keyboard.dismiss")
                                .onGeometryChange(for: CGRect.self) { geometry in
                                    geometry.frame(in: .global)
                                } action: { frame in
                                    // Focus and keyboard notifications can precede
                                    // the accessory's final position.
                                    guard !frame.isEmpty else { return }
                                    revealLastFour(using: scrollProxy)
                                }
                        }
                    }
                }
            }
        }
        .protectEdits(snapshot: editSnapshot)
    }

    private var statusPicker: some View {
        Picker("状态", selection: $status) {
            Text("使用中").tag(CardStatus.active)
            Text("停用").tag(CardStatus.inactive)
        }
        .accessibilityIdentifier("card.editor.status")
    }

    private func revealLastFour(using scrollProxy: ScrollViewProxy) {
        guard focusedField == .lastFour else { return }
        Task { @MainActor in
            await Task.yield()
            guard focusedField == .lastFour else { return }
            scrollProxy.scrollTo(Field.lastFour, anchor: .top)
        }
    }

    private func validationMessage(for field: Field) -> String? {
        switch field {
        case .account:
            return accounts.contains(where: { $0.id == accountID }) ? nil : "请选择账户。"
        case .customNetwork:
            guard networkSelection == .other else { return nil }
            return customNetworkName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "请填写卡组织名称。" : nil
        case .productName:
            return productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "卡产品名称不能为空。" : nil
        case .lastFour:
            let normalized = lastFour.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.utf8.count == 4 && normalized.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 })
                ? nil : "末四位必须是 4 位数字。"
        case .nickname, .notes:
            return nil
        }
    }

    @ViewBuilder
    private func fieldError(_ field: Field) -> some View {
        if showingValidationErrors, let message = validationMessage(for: field) {
            InlineErrorView(message: message)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("\(field.rawValue).error")
        }
    }

    private func save(using scrollProxy: ScrollViewProxy) {
        focusedField = nil
        errorMessage = nil
        showingValidationErrors = true
        if let field = Field.allCases.first(where: { validationMessage(for: $0) != nil }) {
            Task { @MainActor in
                await Task.yield()
                guard validationMessage(for: field) != nil else { return }
                scrollProxy.scrollTo(field, anchor: .top)
            }
            return
        }
        guard let account = accounts.first(where: { $0.id == accountID }) else { return }
        let normalizedLastFour = lastFour.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let selectedNetworks = resolveNetworks() else { return }
        let target = card ?? Card(
            account: account,
            productName: productName,
            networks: selectedNetworks,
            lastFour: normalizedLastFour,
            status: status,
            notes: notes
        )
        target.account = account
        target.networks = selectedNetworks
        target.productName = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        target.lastFour = normalizedLastFour
        target.status = status
        target.notes = notes
        do {
            try target.validate()
            if card == nil { modelContext.insert(target) }
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = "卡片未保存：\(error.localizedDescription)"
        }
    }

    private func resolveNetworks() -> [CardNetwork]? {
        if networkSelection == .other {
            let name = customNetworkName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                errorMessage = "请填写卡组织名称。"
                return nil
            }
            if let existing = networks.first(where: { !$0.isBuiltIn && $0.displayName.caseInsensitiveCompare(name) == .orderedSame }) {
                return [existing]
            }
            let custom = CardNetwork(code: "custom.\(UUID().uuidString.lowercased())", displayName: name)
            modelContext.insert(custom)
            return [custom]
        }
        let selected = networkSelection.codes.compactMap { code in networks.first { $0.code == code } }
        guard selected.count == networkSelection.codes.count else {
            errorMessage = "内置卡组织尚未准备好，请重启应用后再试。"
            return nil
        }
        return selected
    }
}
