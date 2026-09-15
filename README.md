# 食记 shiji 🍱

面向健身人群的饮食计划 + 饮食记录 App，Flutter 跨平台（Android / iOS / Windows / macOS）。

界面参考 iOS 新版（Liquid Glass）风格：浅灰底、白色大圆角卡片、iOS 蓝、半透明毛玻璃底部导航 + 居中蓝色加号。

## 三个 Tab

| 位置 | 名称 | 功能 |
| --- | --- | --- |
| 左 | **饮食计划** | 周历选日期 → 按餐段（早餐/午餐/晚餐/加餐）查看当天的安排与记录，卡片展示热量 + 三大营养素，可标记"已吃"、调份量、删除；顶部有全天合计 |
| 中 | **＋** | 添加饮食：选日期、餐段，从「食材」或「组合餐」里挑选、按克数调整后，明确选择**加入计划**或**记为已吃**；可连续添加多条 |
| 右 | **食材库** | 管理你的常用食材（健身人群常吃的就那几十种），以及由多个食材组成的「组合餐」 |

## 数据维度（重点）

三个层级，从基础到上层，互不混淆：

1. **食材 `Food`**（基础单位）
   - 名字、图标、三大营养素（蛋白质/碳水/脂肪，按 **每 100g** 记录）
   - 热量按 4/4/9 千卡自动估算（估算值），不用手填
   - **一份的克数** `servingGrams`：只是输入时的快捷单位；固定包装商品可把整包设为一份（例如 360g/盒、一根 60g 的蛋白棒）
2. **组合餐 `MealTemplate`**（一餐 = 多个食材按**克数**组合）
   - 例如「鸡胸肉能量碗」= 鸡胸肉 150g + 米饭 200g + 西兰花 100g + 橄榄油 10g
   - 配方持久化绝对克数：之后修改食材的"一份"克数不会改变配方
   - 自动算出整餐合计营养，可一键加入某天某餐
3. **饮食记录 `DiaryEntry`**（某天、某餐段的一条条目）
   - **计划与已吃是两种状态**（`planned / consumed / skipped`）：添加时明确选择，不靠日期猜测
   - **记录是快照**：创建时固化名称、克数与营养，之后修改甚至删除食材/组合餐都不影响历史
   - 全天汇总只统计「已吃」；计划单独展示（"还有 N 千卡未吃"）
4. **每日目标 `NutritionTargets`**
   - 热量 + 蛋白质/碳水/脂肪四项目标，点首页汇总卡调整
   - 汇总卡展示已摄入对比目标、还可吃多少、三大营养素完成度

## 运行

```bash
flutter pub get

# Windows 预览
flutter run -d windows

# macOS 预览
flutter run -d macos

# Android / iOS
flutter run -d <device-id>   # flutter devices 查看

# 静态检查与测试
flutter analyze
flutter test
```

## 项目结构

```
lib/
├── main.dart                  # 入口，注入 AppStore
├── app.dart                   # MaterialApp、中文本地化
├── theme.dart                 # iOS 风格配色与主题
├── models.dart                # Food / MealTemplate / DiaryEntry / Nutrition
├── data/
│   ├── store.dart             # 全局状态 + SharedPreferences(JSON) 持久化
│   └── seed.dart              # 首次启动示例数据（20 种食材、3 个组合餐）
├── screens/
│   ├── home_shell.dart        # 主框架 + 毛玻璃底部导航
│   ├── plan_screen.dart       # Tab1 饮食计划（周历、餐段筛选、记录卡片）
│   ├── add_entry_sheet.dart   # 中间 + 的记录饮食弹层
│   ├── foods_screen.dart      # Tab3 食材库（食材 / 组合餐 分段）
│   ├── food_edit_screen.dart  # 食材编辑页
│   └── meal_edit_screen.dart  # 组合餐编辑页
└── widgets/
    └── common_widgets.dart    # 营养条、周历、emoji 徽章、对话框等
```

## 数据存储

数据以 JSON 存在本地（`shared_preferences`），无需数据库与网络权限；删除应用即清空。所有写入都会等待落盘完成；首次启动只预置食材与组合餐示例，**不伪造任何饮食记录**。

「食材库 → 备份/恢复」可把全部数据导出为 JSON 文本（剪贴板），或从剪贴板备份恢复。

## 后续可扩展

- 计划复用：复制昨天 / 套用日模板 / 重复到指定日期
- 体重记录与趋势
- 数据导出为文件 / 云同步
- 食材条码扫描、自定义分类标签、生熟状态
- 饮水记录
