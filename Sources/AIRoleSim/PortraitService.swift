import Foundation

// MARK: - 角色写实肖像（免费真人头像库 randomuser.me，无需 Key）
// 每个角色根据名字与标签生成一张写实人像；可"换一张"。
// 用户也可以上传自己的图片（最高质量）。

enum PortraitService {

    struct Result: Codable {
        var status: String
        var gender: String
        var index: Int
        var detail: String?
    }

    static func json(_ r: Result) -> String {
        (try? JSONEncoder().encode(r)).flatMap { String(data: $0, encoding: .utf8) } ?? "{\"status\":\"error\"}"
    }

    /// 推断性别倾向（仅用于挑选头像风格，可随机）
    private static func inferGender(_ character: RoleProfile) -> String {
        let text = character.name + character.tags.joined() + character.persona
        let female = ["她", "女", "姐", "妹", "妈", "妻", "姑娘", "少女", "御姐", "女神"]
        let male = ["他", "男", "哥", "弟", "爸", "夫", "先生", "少年", "男神"]
        let f = female.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
        let m = male.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
        if f > m { return "women" }
        if m > f { return "men" }
        // 无倾向：按 id 稳定随机
        return abs(character.id.uuidString.hashValue) % 2 == 0 ? "women" : "men"
    }

    /// 生成一张真人肖像（基于角色 id 稳定选号；regenerate 时换号）
    static func generate(character: RoleProfile, regenerate: Bool = false) async -> (Data?, String) {
        let gender = inferGender(character)
        var seed = abs(character.id.uuidString.hashValue) % 100
        if regenerate { seed = Int.random(in: 0...99) }
        let idx = max(0, min(99, seed))

        let urlString = "https://randomuser.me/api/portraits/\(gender)/\(idx).jpg"
        guard let url = URL(string: urlString),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "randomuser.me" else {
            return (nil, json(Result(status: "error", gender: gender, index: idx, detail: "肖像地址无效")))
        }
        do {
            let (data, resp) = try await APIClient.dataWithRetry(URLRequest(url: url))
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200, data.count > 1000 else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                return (nil, json(Result(status: "error", gender: gender, index: idx, detail: "肖像服务不可用（HTTP \(code)）")))
            }
            return (data, json(Result(status: "ok", gender: gender, index: idx, detail: nil)))
        } catch {
            return (nil, json(Result(status: "error", gender: gender, index: idx, detail: error.localizedDescription)))
        }
    }
}
