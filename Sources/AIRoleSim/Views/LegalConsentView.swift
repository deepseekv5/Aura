import SwiftUI

/// 首次启动法律协议同意弹窗（用户服务协议 + 隐私政策）
/// 依据《个人信息保护法》第 14 条：处理个人信息前须取得个人明确同意。
struct LegalConsentView: View {
    /// 用户点击同意后回调
    let onAgree: () -> Void
    @State private var tab = 0
    @State private var agreed = false
    @State private var scrollToEnd = false

    var body: some View {
        VStack(spacing: 0) {
            // 顶部品牌
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.shield")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("开始使用 Aura 之前")
                        .font(.system(size: 16, weight: .semibold))
                    Text("请阅读并同意以下条款")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Picker("", selection: $tab) {
                Text("用户服务协议").tag(0)
                Text("隐私政策").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 22)

            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 10) {
                        Group {
                            if tab == 0 {
                                ToastTextView(text: legalText)
                            } else {
                                ToastTextView(text: privacyText)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .padding(20)
                    .onChange(of: tab) { _, _ in
                        proxy.scrollTo("top", anchor: .top)
                    }
                }
            }
            .frame(height: 300)

            Divider()

            VStack(spacing: 10) {
                Toggle(isOn: $agreed) {
                    Text("我已阅读并同意《用户服务协议》和《隐私政策》")
                        .font(.system(size: 12))
                }
                .toggleStyle(.checkbox)

                HStack {
                    Text("所有数据仅存于你的设备本地")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("同意并继续") { onAgree() }
                        .buttonStyle(.glassProminent)
                        .disabled(!agreed)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .frame(width: 540, height: 520)
    }

    // 内嵌协议摘要（完整版见仓库 TERMS.md / PRIVACY.md）
    private var legalText: String {
        """
        Aura 用户服务协议（摘要 · 完整版见项目仓库 TERMS.md）

        第一条 服务说明
        Aura 是一款 macOS 本地 AI 角色对话工具。本软件不提供大模型推理服务，你需自行配置第三方 OpenAI 兼容 API。本软件为开源软件，按"现状"提供。

        第二条 用户资格
        你须为年满 18 周岁、具有完全民事行为能力的自然人，并承诺遵守中华人民共和国法律法规。

        第三条 用户内容与责任
        你对输入和生成的全部内容承担全部责任，不得用于生成违法违规内容；AI 生成内容可能存在事实错误，请自行核实。

        第四条 个人信息
        对话记录、角色配置、记忆数据、API 密钥等仅存储于你的本地设备，本软件无服务器、不主动上传数据。配置第三方 API 后，对话内容将发送至你所选服务商。

        第五条 知识产权
        源代码采用 MIT 许可证。你生成的内容权益归你所有，但不得侵害第三方权益。

        第六条 免责声明
        本软件按"现状"提供，不对第三方 API 的费用、中断、内容违规等负责；不替代医疗、法律、投资等专业服务。

        第七条 协议变更
        更新时可能修订本协议，继续使用即视为接受。

        第八条 争议解决
        适用中华人民共和国法律，协商不成提交有管辖权法院。

        —— 点击下方勾选框表示你已完整阅读并同意上述条款。
        """
    }

    private var privacyText: String {
        """
        Aura 隐私政策（摘要 · 完整版见项目仓库 PRIVACY.md）

        1. 信息收集与存储
        本软件为纯本地应用，无服务器。角色配置、对话记录、长期记忆、API 配置（权限 0600）、密码哈希、图片等均仅存于本机 ~/Library/Application Support/AIRoleSim/，你可随时删除。

        2. 系统权限（均需单独授权，可随时撤销）
        麦克风/语音识别：仅用于语音听写；屏幕录制：仅在你要求时截取，受应用内密码保护；通讯录：仅用于按姓名查找号码拨号；音乐控制：仅用于播放歌曲。

        3. 网络传输
        本软件不会将你的数据发送到运营者服务器（没有服务器）。配置第三方 API 后对话内容发送至你所选服务商；天气/新闻/搜索仅发送必要的城市名或关键词；生图发送绘图提示词。

        4. 敏感个人信息
        本软件不主动收集敏感个人信息，请勿在对话中主动输入。

        5. 未成年人
        不面向未满 14 周岁儿童。

        6. 你的权利
        你享有查阅、复制、更正、删除等权利——数据全在本地，直接管理本地文件即可行使。

        7. 第三方服务
        第三方 API 与公共服务的数据处理受各自隐私政策约束。

        —— 继续使用即表示你已阅读并同意本隐私政策。
        """
    }
}

private struct ToastTextView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11.5, design: .monospaced))
            .lineSpacing(5)
            .textSelection(.enabled)
            .foregroundStyle(.primary.opacity(0.85))
    }
}
