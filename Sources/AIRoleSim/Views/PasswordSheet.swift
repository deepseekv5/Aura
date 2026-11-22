import SwiftUI
import CryptoKit

/// 屏幕读取密码弹窗：setup（设置密码）/ unlock（解锁）/ reset（重设）
struct PasswordSheet: View {
    enum Mode {
        case setup, unlock, reset
    }

    let mode: Mode
    @ObservedObject var store: AppStore
    let pendingEnable: Bool?
    let onDone: () -> Void

    @State private var currentInput = ""
    @State private var newInput = ""
    @State private var confirmInput = ""
    @State private var errorText: String?

    private var title: String {
        switch mode {
        case .setup: return "设置屏幕读取密码"
        case .unlock: return "解锁屏幕读取"
        case .reset: return "重设屏幕读取密码"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            if mode == .reset {
                SecureField("当前密码", text: $currentInput)
                    .textFieldStyle(.roundedBorder)
            }
            if mode != .unlock {
                SecureField("新密码（至少 4 位）", text: $newInput)
                    .textFieldStyle(.roundedBorder)
                SecureField("确认新密码", text: $confirmInput)
                    .textFieldStyle(.roundedBorder)
            } else {
                SecureField("密码", text: $currentInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
            }

            if let e = errorText {
                Text(e)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消") { onDone() }
                    .keyboardShortcut(.cancelAction)
                Button(mode == .unlock ? "解锁" : "保存") { submit() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
        }
        .padding(18)
        .frame(width: 380)
    }

    private var subtitle: String {
        switch mode {
        case .setup:
            return "开启屏幕读取前需要设置密码。此后每次启动 Aura，都需输入该密码解锁屏幕读取。"
        case .unlock:
            return "屏幕读取已锁定。输入密码后，本次运行期间生效。"
        case .reset:
            return "先输入当前密码，再设置新密码。"
        }
    }

    private var canSubmit: Bool {
        switch mode {
        case .setup:
            return newInput.count >= 4 && newInput == confirmInput
        case .unlock:
            return !currentInput.isEmpty
        case .reset:
            return currentInput.count >= 4 && newInput.count >= 4 && newInput == confirmInput
        }
    }

    private func submit() {
        switch mode {
        case .setup:
            let salt = PasswordStore.makeSalt()
            store.settings.screenPasswordSalt = salt
            store.settings.screenPasswordHash = PasswordStore.hash(newInput, salt: salt)
            store.settings.screenEnabled = true
            store.screenUnlocked = true
            onDone()
        case .unlock:
            let hash = PasswordStore.hash(currentInput, salt: store.settings.screenPasswordSalt)
            if hash == store.settings.screenPasswordHash {
                store.screenUnlocked = true
                errorText = nil
                onDone()
            } else {
                errorText = "密码不正确"
            }
        case .reset:
            let oldHash = PasswordStore.hash(currentInput, salt: store.settings.screenPasswordSalt)
            guard oldHash == store.settings.screenPasswordHash else {
                errorText = "当前密码不正确"
                return
            }
            let salt = PasswordStore.makeSalt()
            store.settings.screenPasswordSalt = salt
            store.settings.screenPasswordHash = PasswordStore.hash(newInput, salt: salt)
            store.screenUnlocked = true
            onDone()
        }
    }
}
