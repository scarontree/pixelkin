import Foundation

/// 情境气泡规则集
/// 存储位置：~/Library/Application Support/DesktopPet/bubble_rules.json
///
/// 设计原则：规则和语录分离
/// - BubbleRuleSet：定义触发条件（app 分组 / 时间 / 日期）+ 兜底语录
/// - PhraseBook：定义角色专属语录（跟着皮肤走，存在皮肤目录的 phrases.json 中）
///
/// 三层触发机制：
/// 1. 应用切换触发（BubbleRule）— 检测前台 app 切换，通过 appGroups 匹配规则
/// 2. 时间段触发（TimeBubbleRule）— 每分钟轮询，匹配当前小时是否在窗口内（如早间问候 / 深夜催睡）
/// 3. 特殊日期触发（DateBubbleRule）— 每分钟轮询，匹配月日（节日）或星期几（周五 / 周末）
///
/// 语录查找链：
/// 1. 当前皮肤的 PhraseBook（phrases.json）
/// 2. fallbackPhrases（规则集内的兜底语录）
///
/// 冷却机制：
/// - 应用规则：全局冷却（globalCooldown）+ 单规则冷却（BubbleRule.cooldown）
/// - 时间/日期规则：全局冷却 + 每条规则每天最多触发一次
struct BubbleRuleSet: Codable {
    /// 应用分组：组名 → bundle ID 列表
    var appGroups: [String: [String]]
    
    /// 应用切换触发规则
    var rules: [BubbleRule]
    
    /// 时间段触发规则（早间问候 / 午餐提醒 / 深夜催睡等）
    var timeRules: [TimeBubbleRule]?
    
    /// 特殊日期触发规则（节日 / 周五 / 周末等）
    var dateRules: [DateBubbleRule]?
    
    /// 兜底语录：ruleID → 语录列表（皮肤没有 phrases.json 时使用）
    var fallbackPhrases: [String: [String]]
    
    /// 任意气泡之间的最小间隔（秒）
    var globalCooldown: TimeInterval
    
    /// 气泡默认显示时长（秒）
    var defaultDuration: TimeInterval
    
    /// 内置默认规则
    static let builtInDefault: BubbleRuleSet = {
        // ── 应用分组（bundle ID 映射）──────────────────────────
        let groups: [String: [String]] = [
            "browsers": [
                "com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox",
                "company.thebrowser.Browser", "com.microsoft.edgemac", "com.operasoftware.Opera",
                "com.kagi.kagimac"
            ],
            "code_editors": [
                "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
                "com.sublimetext.4", "dev.zed.Zed", "com.jetbrains.intellij", "com.jetbrains.WebStorm",
                "com.jetbrains.pycharm", "com.google.android.studio"
            ],
            "terminals": [
                "com.apple.Terminal", "com.googlecode.iterm2",
                "dev.warp.Warp-Stable", "io.alacritty", "com.mitchellh.ghostty"
            ],
            "social_cn": [
                "com.tencent.xinWeChat", "com.tencent.qq",
                "com.alibaba.DingTalkMac", "com.bytedance.macos.feishu",
            ],
            "social_intl": [
                "com.hnc.Discord", "com.tinyspeck.slackmacgap",
                "ru.keepcoder.Telegram", "net.whatsapp.WhatsApp",
            ],
            "music": [
                "com.apple.Music", "com.spotify.client", "com.netease.163music",
            ],
            "video": [
                "com.typcn.bilern", "com.colliderli.iina", "com.firecore.infuse",
                "org.videolan.vlc", "com.apple.QuickTimePlayerX",
            ],
            "creative": [
                "com.figma.Desktop", "com.adobe.Photoshop", "com.adobe.illustrator",
                "com.bohemiancoding.sketch3", "com.apple.garageband",
                "com.apple.FinalCut", "com.apple.logic10", "com.blackmagic-design.DaVinciResolve",
                "org.blenderfoundation.blender"
            ],
            "productivity": [
                "notion.id", "md.obsidian", "com.apple.Notes", "com.runningwithcrayons.Alfred",
                "com.apple.reminders", "com.apple.iCal", "com.raycast.macos"
            ],
            "office": [
                "com.apple.iWork.Pages", "com.apple.iWork.Numbers",
                "com.microsoft.Word", "com.microsoft.Excel", "com.microsoft.Powerpoint",
            ],
            "communication": [
                "com.apple.mail", "com.apple.FaceTime", "com.readdle.smartemail-Mac",
                "us.zoom.xos", "com.microsoft.teams2",
            ],
            "system": [
                "com.apple.systempreferences", "com.apple.ActivityMonitor",
                "com.apple.AppStore", "com.apple.finder",
            ],
            "reading": [
                "com.apple.Preview", "com.apple.iBooksX", "com.apple.Photos",
            ],
            "games": [
                "com.apple.Chess", "com.valvesoftware.steam",
                "com.epicgames.EpicGamesLauncher",
            ],
            "ai": [
                "com.openai.chat", "com.anthropic.claude", "com.sindresorhus.ChatGPT"
            ],
            "finance": [
                "com.apple.stocks", "com.binance.mac", "com.tradingview.tradingviewapp",
                "com.hexin.mac", "cn.futu.FutubullMac", "com.eastmoney.mac"
            ],
            "news": [
                "com.apple.news", "com.netease.macnews", "com.ranchero.NetNewsWire-Evergreen"
            ],
        ]
        
        // ── 应用切换触发规则 ──────────────────────────────────
        let rules: [BubbleRule] = [
            BubbleRule(id: "browsers",      appGroup: "browsers",      probability: 0.35, cooldown: 45),
            BubbleRule(id: "code_editors",   appGroup: "code_editors",  probability: 0.4,  cooldown: 40),
            BubbleRule(id: "terminals",      appGroup: "terminals",     probability: 0.3,  cooldown: 45),
            BubbleRule(id: "social_cn",      appGroup: "social_cn",     probability: 0.35, cooldown: 40),
            BubbleRule(id: "social_intl",    appGroup: "social_intl",   probability: 0.3,  cooldown: 45),
            BubbleRule(id: "music",          appGroup: "music",         probability: 0.4,  cooldown: 50),
            BubbleRule(id: "video",          appGroup: "video",         probability: 0.35, cooldown: 45, appNameContains: "bilibili"),
            BubbleRule(id: "creative",       appGroup: "creative",      probability: 0.35, cooldown: 45),
            BubbleRule(id: "productivity",   appGroup: "productivity",  probability: 0.3,  cooldown: 45),
            BubbleRule(id: "office",         appGroup: "office",        probability: 0.3,  cooldown: 50),
            BubbleRule(id: "communication",  appGroup: "communication", probability: 0.3,  cooldown: 50),
            BubbleRule(id: "system",         appGroup: "system",        probability: 0.2,  cooldown: 60),
            BubbleRule(id: "reading",        appGroup: "reading",       probability: 0.25, cooldown: 50),
            BubbleRule(id: "games",          appGroup: "games",         probability: 0.4,  cooldown: 45),
            BubbleRule(id: "ai",             appGroup: "ai",            probability: 0.4,  cooldown: 40),
            BubbleRule(id: "finance",        appGroup: "finance",       probability: 0.35, cooldown: 50),
            BubbleRule(id: "news",           appGroup: "news",          probability: 0.3,  cooldown: 50),
            BubbleRule(id: "default",        appGroup: nil,             probability: 0.1,  cooldown: 60),
        ]
        
        // ── 兜底语录（app 触发 + 时间触发 + 日期触发共用）────
        let fallback: [String: [String]] = [
            "browsers":      ["发现什么有趣的网页了吗？", "这个网页看起来不错哦~", "书签快满了吧？", "冲浪速度好快呀！", "今天也看了很多新东西呢"],
            "code_editors":  ["遇到 Bug 不要慌，喝口水再看！", "记得多保存哦~", "代码敲累了就休息一下吧", "Bug 退散！✨", "哇，满屏的代码，你好厉害！", "早点下班！"],
            "terminals":     ["黑客帝国即视感！", "这黑乎乎的屏幕，你在施魔法吗？", "跑通了吗？", "运行一切顺利吗？", "指令输入，发射！🚀"],
            "social_cn":     ["跟朋友聊天真开心~", "别光聊天忘了正事呀~", "帮我也打个招呼！", "今天群里好热闹", "发个表情包斗图！"],
            "social_intl":   ["跨国连线中？", "看起来聊得很投入呢", "好多不认识的表情包~", "外语好厉害呀！"],
            "music":         ["这首歌真好听~🎵", "跟着节奏摇摆~", "音乐让人心情舒畅呢", "你也喜欢单曲循环吗？", "下一首是什么？"],
            "video":         ["别忘了三连哦~", "弹幕好欢乐", "遇到有趣的视频要笑出来呀", "进度条撑住！", "看什么视频这么认真呢？"],
            "creative":      ["大艺术家在线创作中！🎨", "每一笔都充满了灵感", "哇，好好看！", "颜色搭配得真棒~", "搞艺术就是费脑子~"],
            "productivity":  ["正在认真记笔记呢📝", "好记性不如烂笔头！", "思路越来越清晰了吧", "计划表填满了吗？", "做个效率达人！"],
            "office":        ["辛苦写文档中~", "PPT 越做越熟练了呢", "这么多数据看晕了吧", "排版记得对齐哦~", "又是被表格包围的一天！"],
            "communication": ["又有新邮件了📬", "开会辛苦啦！", "邮箱清空计划进行中", "保持微笑哦~", "沟通最重要啦！"],
            "system":        ["在整理电脑呀？", "深色模式对眼睛好~", "清理一下磁盘空间吧？", "风扇转得有点大声哦？", "给电脑也放个假？"],
            "reading":       ["看书的时光最安静了", "知识增加了！", "这本书看起来很有意思", "沉浸在文字的世界里~", "做个读书人！"],
            "games":         ["游戏时间！🎮", "这局肯定能赢！", "操作拉满！", "注意保护眼睛哦~", "带我一个带我一个！", "稳住，我们能赢！"],
            "ai":            ["在跟 AI 聊天吗？", "未来的世界真奇妙~", "AI 能代替我陪你吗？", "帮我也问 AI 一个问题吧！", "智能助理时刻准备着！"],
            "finance":       ["在看大盘吗？📈", "今天有赚钱吗？", "小心风险哦~", "一片飘红还是绿油油？", "做个理财小能手！"],
            "news":          ["发生什么大事了？📰", "吃瓜第一线！", "今天有什么新鲜事？", "读点新闻，开阔眼界~", "世界变化真快呀！"],
            "morning":       ["早上好！新的一天也要元气满满哦~", "早安，记得吃早餐！", "新的一天开始啦，加油！"],
            "lunch":         ["到饭点啦！今天中午吃什么好吃的？", "先去吃饭吧，工作等下再做~", "饿不饿？该吃午饭啦！"],
            "afternoon":     ["下午茶时间到！喝口水休息一下吧~", "起来走动走动，不要一直坐着哦！", "下午容易犯困，来点提神的？"],
            "evening":       ["今天也辛苦啦！早点休息哦~", "晚上好，今天过得开心吗？", "工作暂告一段落吧~"],
            "late_night":    ["怎么还不睡呀？别熬夜啦！", "很晚了，早点休息吧，明天再战！", "熬夜对身体不好哦，快去睡觉！", "夜深了，陪我一起睡吧~"],
            "friday":        ["今天是周五啦！坚持就是胜利！", "周末马上就要到啦~", "周五晚上打算怎么过呀？"],
            "weekend":       ["周末愉快！好好放松一下吧~", "不去外面玩吗？", "休息日是最棒的！", "终于可以睡个好觉啦~"],
            "new_year":      ["新年快乐！新的一天也要元气满满！🎊", "又是一年啦，多多指教哦！", "新年新气象~"],
            "christmas":     ["圣诞快乐！收到礼物了吗？🎄", "外面有没有下雪呢？", "Jingle bells, jingle bells~"],
            "valentine":     ["情人节快乐！今天也要开心哦~🍫", "即使是一个人，也要好好爱自己呀！", "我的心里只有你~"],
            "april_fools":   ["今天是愚人节！小心被骗哦~", "我才不会上你的当呢！", "你要是敢骗我，你就死定了！"],
            "labor_day":     ["劳动节快乐！放假还要坐在电脑前吗？", "辛苦啦！今天就好好休息一下吧~"],
            "childrens_day": ["儿童节快乐！不管几岁，快乐万岁！🎈", "今天你也是个宝宝~"],
            "halloween":     ["万圣节快乐！不给糖就捣蛋！🎃", "今晚会不会有幽灵跑出来呢？", "Trick or Treat！"],
            "double_11":     ["双十一啦！清空购物车了吗？", "你的钱包还好吗？", "买买买！手还在吗？"],
            "default":       ["今天辛苦啦～", "要不要摸摸我呀？", "打个哈欠～😴", "在这里陪着你~", "休息一下吧？☕️", "伸个懒腰~", "我会一直看着你的~", "发发呆也挺好", "今天天气不错呢！", "遇到什么好玩的事了吗？"],
        ]
        
        // ── 时间段触发规则（每天每条最多触发一次）──────────────
        let timeRules: [TimeBubbleRule] = [
            TimeBubbleRule(id: "morning",    startHour: 8,  endHour: 10, probability: 0.05),
            TimeBubbleRule(id: "lunch",      startHour: 12, endHour: 13, probability: 0.1),
            TimeBubbleRule(id: "afternoon",  startHour: 15, endHour: 16, probability: 0.05),
            TimeBubbleRule(id: "evening",    startHour: 18, endHour: 20, probability: 0.05),
            TimeBubbleRule(id: "late_night", startHour: 23, endHour: 2,  probability: 0.05), // 跨午夜，概率低避免反复催
        ]
        
        // ── 特殊日期触发规则（每天每条最多触发一次）──────────────
        // 节日：按月日匹配 ｜ 周期：按星期几匹配
        // 优先级高于时间段规则（同一轮次只触发一条）
        let dateRules: [DateBubbleRule] = [
            // 节日
            DateBubbleRule(id: "new_year",     month: 1,  day: 1,  probability: 0.1),
            DateBubbleRule(id: "valentine",    month: 2,  day: 14, probability: 0.1),
            DateBubbleRule(id: "april_fools",  month: 4,  day: 1,  probability: 0.1),
            DateBubbleRule(id: "labor_day",    month: 5,  day: 1,  probability: 0.1),
            DateBubbleRule(id: "childrens_day", month: 6,  day: 1,  probability: 0.1),
            DateBubbleRule(id: "halloween",    month: 10, day: 31, probability: 0.1),
            DateBubbleRule(id: "double_11",    month: 11, day: 11, probability: 0.1),
            DateBubbleRule(id: "christmas",    month: 12, day: 25, probability: 0.1),
            // 周期
            DateBubbleRule(id: "friday",  weekdays: [6],    probability: 0.05), // Calendar.weekday: 6 = Friday
            DateBubbleRule(id: "weekend", weekdays: [1, 7], probability: 0.05), // 1 = Sunday, 7 = Saturday
        ]
        
        return BubbleRuleSet(
            appGroups: groups,
            rules: rules,
            timeRules: timeRules,
            dateRules: dateRules,
            fallbackPhrases: fallback,
            globalCooldown: 15,
            defaultDuration: 4
        )
    }()
}

/// 时间段触发规则
///
/// 按小时窗口匹配当前时间。每分钟轮询一次，每条规则每天最多触发一次。
/// 当 startHour > endHour 时表示跨午夜窗口（如 23~2 点）。
struct TimeBubbleRule: Codable, Identifiable {
    var id: String          // 规则 ID，同时也是 PhraseBook / fallbackPhrases 的 key
    var startHour: Int      // 窗口起始小时（0~23，含）
    var endHour: Int        // 窗口结束小时（0~23，不含；< startHour 表示跨午夜）
    var probability: Double // 每分钟轮询时的触发概率（0.0~1.0）
}

/// 特殊日期触发规则
///
/// 两种匹配模式（二选一）：
/// - 节日模式：指定 month + day，匹配精确日期（如 12月25日 = 圣诞节）
/// - 周期模式：指定 weekdays，匹配星期几（如 [6] = 每周五）
///
/// weekdays 使用 Calendar.component(.weekday) 的值：
/// Sunday=1, Monday=2, Tuesday=3, Wednesday=4, Thursday=5, Friday=6, Saturday=7
struct DateBubbleRule: Codable, Identifiable {
    var id: String          // 规则 ID，同时也是 PhraseBook / fallbackPhrases 的 key
    var month: Int?         // 节日模式：月份（1~12）
    var day: Int?           // 节日模式：日期（1~31）
    var weekdays: [Int]?    // 周期模式：星期几数组（见上方说明）
    var probability: Double // 每分钟轮询时的触发概率（0.0~1.0）
}

/// 应用切换触发规则
///
/// 匹配优先级：
/// 1. appGroup 中的 bundle ID 精确匹配（通过反向索引）
/// 2. appNameContains 模糊匹配应用名
/// 3. appBundleIDs 直接指定的 bundle ID
/// 4. id 为 "default" 的兜底规则（appGroup 和 appBundleIDs 均为 nil）
struct BubbleRule: Codable, Identifiable {
    var id: String                     // 规则 ID，同时也是 PhraseBook / fallbackPhrases 的 key
    var appGroup: String?              // 引用 appGroups 中的组名
    var probability: Double            // 触发概率（0.0~1.0）
    var cooldown: TimeInterval         // 单规则冷却时间（秒）
    var appNameContains: String?       // 模糊匹配应用名（补充 bundle ID 匹配）
    var appBundleIDs: [String]?        // 直接指定的 bundle ID（不走 appGroups）
    var displayDuration: TimeInterval? // 覆盖默认气泡显示时长
    
    init(id: String, appGroup: String?, probability: Double, cooldown: TimeInterval,
         appNameContains: String? = nil, appBundleIDs: [String]? = nil, displayDuration: TimeInterval? = nil) {
        self.id = id
        self.appGroup = appGroup
        self.probability = probability
        self.cooldown = cooldown
        self.appNameContains = appNameContains
        self.appBundleIDs = appBundleIDs
        self.displayDuration = displayDuration
    }
}

/// 角色语录本 — 跟着皮肤走的角色专属台词
///
/// 文件位置：~/Library/Application Support/DesktopPet/Skins/{skinID}/phrases.json
///
/// key 为规则 ID（同时覆盖应用触发 / 时间触发 / 日期触发三类规则），
/// 例如 "browsers", "morning", "christmas", "default" 等。
///
/// 示例 phrases.json:
///   "browsers": ["才不是在偷看你上网呢！", "又在摸鱼…哼"],
///   "morning": ["起这么早干嘛…哈欠…"],
///   "christmas": ["没有礼物别跟我说话！"],
///   "default": ["才不是在意你呢！", "哼", "笨蛋，记得喝水"]
struct PhraseBook: Codable {
    /// ruleID → 该角色在这个场景下的语录列表
    var phrases: [String: [String]]
    
    /// 查找某个规则的语录，没有则返回 nil
    func phrasesForRule(_ ruleID: String) -> [String]? {
        return phrases[ruleID]
    }
    
    /// 内置示例：傲娇角色
    static let exampleTsundere = PhraseBook(phrases: [
        "browsers":      ["才、才不是在偷看你上网呢！", "少看点没用的东西！", "这种网页有什么好看的", "看那么快，你看得清吗！", "别以为我不知道你在看什么！"],
        "code_editors":  ["你以为我在看你写代码吗！", "这个变量名也太难懂了吧…", "切…这种 Bug 怎么还犯", "写完记得保存，别又弄丢了！", "这么简单的逻辑也能卡住？笨蛋！"],
        "terminals":     ["看不懂这些黑框框…", "你是不是在装酷？", "小心别把系统删了！", "整天对着黑屏，不无聊吗？"],
        "social_cn":     ["又在跟谁聊天…", "哼，不理我只顾着聊天", "聊得那么开心，才没羡慕呢", "群里那么吵，别理他们了！"],
        "social_intl":   ["又在跟外国人聊？", "这些消息看得头都晕啦！", "别用那些奇奇怪怪的表情包！"],
        "music":         ["这歌…还行吧", "才不是因为好听才竖起耳朵的", "勉强能听一下啦", "切歌！这首不好听！"],
        "video":         ["我也想看...才怪呢！", "这种视频有什么好看的啊", "看久了小心眼睛痛！", "笑那么大声干嘛，吵死了！"],
        "creative":      ["哼，这个配色也就一般般吧", "画得挺认真的嘛…", "才没有觉得你很有才华呢", "别改了，第一版最好看！"],
        "productivity":  ["又在整理…真是个认真的笨蛋", "记那么多你记得住吗！", "计划永远赶不上变化，知道吗！"],
        "office":        ["又在写文档…", "字那么多看着就烦", "排版对齐一点，强迫症要犯了！", "做不完就别做了，笨蛋！"],
        "communication": ["又要开会…", "我可不想听无聊的会议", "邮件回快点啦！", "开会的时候不要走神！"],
        "system":        ["系统又出什么问题了？", "让我看看…才不是担心电脑坏掉呢", "别乱点，搞坏了别哭！"],
        "reading":       ["字那么多，看得懂吗？", "让我也看看你在看什么！", "翻那么快，你到底看没看进去啊！"],
        "games":         ["又在打游戏…", "打得这么烂，让我来！", "输了可别哭哦！", "别坑队友了，快投降吧！"],
        "ai":            ["居然去问那个铁疙瘩 AI？", "AI 哪有我聪明！哼！", "少跟那个没有感情的家伙说话！", "它才不懂你呢！"],
        "finance":       ["你看这些绿绿红红的干嘛！", "别亏完了跑来找我哭！", "哼，才不信你能赚大钱呢。"],
        "news":          ["又是些无聊的新闻…", "看这些能涨知识吗？", "别看那些八卦了，多看看我！"],
        "morning":       ["起这么早干嘛…哈欠…", "早上好…别吵我，我还要睡…", "今天别给我惹麻烦！"],
        "lunch":         ["肚子饿了！你要饿死我吗！", "吃饭去啦笨蛋，别饿着了！", "去弄点好吃的，别糊弄！"],
        "afternoon":     ["困死了…别吵我午休！", "喂，去倒杯水，顺便给我带点零食！", "别一直盯着屏幕，难看死了！"],
        "evening":       ["终于结束了？你今天也太慢了吧！", "晚上好…哼，勉强夸你一句辛苦了。", "该干嘛干嘛去，别烦我。"],
        "late_night":    ["喂！这么晚还不睡，你是想猝死吗！", "我不管你了，我要睡觉了！哼！", "还不去睡！黑眼圈都要掉到地上了！", "明天起不来我可不叫你！"],
        "friday":        ["终于熬到周五了！你不会周末还要加班吧？", "周末别来烦我！我要休息！"],
        "weekend":       ["周末居然还在这待着？真是个无聊的人。", "别看我，我可不想跟你出去玩！", "好不容易周末，就不能让我消停会儿吗？"],
        "new_year":      ["哼，新的一年你最好机灵点！", "别以为我会祝你新年快乐…算、算了，勉强祝你一下。"],
        "christmas":     ["圣诞节还要一个人过吗？真可怜…看在礼物的份上，就陪你一会儿吧！", "没有礼物别跟我说话！"],
        "valentine":     ["情人节？那种无聊的节日跟我有什么关系！", "你…没收到巧克力吧？真是个笨蛋，这个给你…才不是专门买的呢！"],
        "april_fools":   ["今天可是愚人节，你别想骗到我！", "哼，刚才是不是想捉弄我？没门！", "如果我说喜欢你…才怪呢！被骗了吧笨蛋！"],
        "labor_day":     ["劳动节你还在这里干嘛？真是个劳碌命！", "快去休息啦，别在我眼前晃来晃去！"],
        "childrens_day": ["你都多大人了还过儿童节！真幼稚！", "给，你的棒棒糖。拿去吃吧，别跟别人说是我给的！"],
        "halloween":     ["不给糖就捣蛋！喂，听到没有，快交出零食！🎃", "你今天要是敢拿鬼故事吓我，我就咬你！"],
        "double_11":     ["喂，双十一你买了什么乱七八糟的？", "别光顾着买东西，给我买的零食呢？！", "你的钱包已经空了吧？真可怜~"],
        "default":       ["才不是在意你呢！", "哼，随便你做什么", "我只是碰巧在这里而已", "你…还好吧？", "别误会，我就是无聊", "笨蛋，记得喝水", "别一直盯着我看！", "今天表现也就勉勉强强吧！"],
    ])
    
    /// 内置示例：温柔角色
    static let exampleGentle = PhraseBook(phrases: [
        "browsers":      ["在看什么有趣的东西呢？", "上网太久也要记得休息眼睛哦~", "看到好玩的可以分享给我吗？", "网速好像有点慢呢，耐心等一下哦~"],
        "code_editors":  ["写代码辛苦啦~", "没关系，Bug 一定能解开的！", "专注的样子最迷人了呢", "加油，一定能跑通的♡", "多喝点温水再继续吧~"],
        "terminals":     ["虽然看不懂，但是感觉好厉害！", "小心操作哦，慢慢来~", "指令输入得很熟练呢！"],
        "social_cn":     ["在和朋友聊天吗？真热闹呢~", "记得也抽空陪陪我哦♡", "聊得很开心呢", "你的朋友一定都很喜欢你~"],
        "social_intl":   ["和远方的朋友联系呢~", "你懂好多语言好棒呀！", "沟通没有国界呢♡"],
        "music":         ["这首歌让人感觉好放松~", "音乐能赶走疲惫呢♪", "和你一起听歌真好", "你的歌单总是很好听~"],
        "video":         ["在看什么视频呀？我也想看~", "别一直盯着屏幕看哦", "遇到有趣的弹幕要笑出来呀", "看到开心的地方我也跟着开心呢♡"],
        "creative":      ["哇，好棒的作品！", "你的想象力总是让我惊叹呢♡", "慢慢画，我很喜欢看你创作的样子", "无论画成什么样，我都觉得好看~"],
        "productivity":  ["认真做计划的样子好帅气~", "一步一步来，你一定能做好的", "笔记整理得真整齐呢", "把大目标拆分成小目标，就不觉得难啦♡"],
        "office":        ["处理文档工作辛苦啦~", "累了就先闭眼休息一会儿吧", "不要太勉强自己哦", "进度一点一点在推进呢，真棒！"],
        "communication": ["沟通是一件需要耐心的事呢~", "开会加油！我在这里等你", "回复邮件慢慢来就好", "你的声音真好听♡"],
        "system":        ["在整理系统呀，真勤快~", "电脑也要保持最佳状态呢", "有什么我能帮忙的吗？", "深色模式对眼睛比较友好哦~"],
        "reading":       ["读书的时光真美好~", "书里的世界很有趣吧？", "我安静地陪着你", "读到哪里了呢？"],
        "games":         ["游戏玩得开心吗？", "好厉害的操作！", "就算输了也没关系，开心最重要啦~", "放松一下心情也很重要呢♡"],
        "ai":            ["在和 AI 对话吗？它好像知道很多呢~", "未来的科技真神奇呀", "我也想像 AI 一样帮你解决问题♡", "如果 AI 不能逗你笑，还有我呀~"],
        "finance":       ["投资有风险，一定要谨慎哦~", "不管行情怎么样，心态最重要啦♡", "你一定能做出明智的决定的~"],
        "news":          ["发生什么新闻了呀？", "多了解外面的世界也挺好的呢~", "看新闻也要保持平和的心情哦♡"],
        "morning":       ["早上好！今天也是充满希望的一天呢♡", "昨晚睡得好吗？记得吃早餐哦~", "新的一天，我会一直陪着你的！"],
        "lunch":         ["中午啦，工作先放一放，去吃点好吃的吧~", "不要饿坏了肚子哦，乖乖去吃饭♡", "午饭时间到啦~"],
        "afternoon":     ["下午好~累了的话可以稍微闭目养神一会儿哦", "喝杯茶或者咖啡放松一下吧♡", "起来活动一下肩膀，小心得颈椎病呀~"],
        "evening":       ["今天辛苦啦！好好休息一下吧♡", "晚饭想吃什么呢？", "看着你认真工作的样子，真的好棒呀！"],
        "late_night":    ["夜深了呢，还不打算休息吗？", "太晚睡觉对身体不好哦，我会担心的♡", "今天已经很努力了，剩下的明天再做吧，晚安~", "乖，早点去睡觉好不好？"],
        "friday":        ["今天是周五呢！下班后去吃顿好的吧♡", "辛苦了一周，终于可以休息啦~"],
        "weekend":       ["周末好~放下工作，好好享受生活吧♡", "今天要不要出去散散步呢？", "能和你一起度过周末真开心~"],
        "new_year":      ["新年快乐！新的一年也要一起创造美好的回忆哦♡", "我会一直支持你的！"],
        "christmas":     ["圣诞快乐~🎄 愿你所有的愿望都能实现♡", "能和你在一起过圣诞节，就是最好的礼物了~"],
        "valentine":     ["情人节快乐！要一直开心下去哦~♡", "你对我来说，是最特别的存在呢~"],
        "april_fools":   ["今天是愚人节哦，有没有和朋友开个无伤大雅的玩笑呢？", "不管别人怎么骗你，我永远不会对你撒谎的♡"],
        "labor_day":     ["劳动节到了，平时工作那么辛苦，今天请务必好好犒劳自己！", "无论做什么工作，你在我心里都是最棒的♡"],
        "childrens_day": ["儿童节快乐~ 在我面前，你可以永远做一个不用长大的孩子♡", "今天允许你吃一点甜食哦~🍬"],
        "halloween":     ["万圣节快乐呀~ 今天有准备糖果吗？🎃", "不要怕，如果有小怪物来捣蛋，我会保护你的♡"],
        "double_11":     ["双十一买东西要理智哦，量入为出最重要♡", "比起买东西，能陪在你身边我就很满足啦~"],
        "default":       ["今天也一直陪在你身边哦~", "你已经做得很好了呢！", "累了就依靠我吧", "遇到困难也不要怕，有我在", "看着你的样子真安心", "深呼吸，放松一下~♡", "能一直陪着你，我觉得很幸福~"],
    ])
}
