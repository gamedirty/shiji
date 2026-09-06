# 食记 shiji 🍱

面向健身人群的饮食计划 + 饮食记录 App，Flutter 跨平台（Android / iOS / Windows / macOS）。

界面参考 iOS 新版（Liquid Glass）风格：浅灰底、白色大圆角卡片、iOS 蓝、半透明毛玻璃底部导航 + 居中蓝色加号。

## 三个 Tab

| 位置 | 名称 | 功能 |
| --- | --- | --- |
| 左 | **饮食计划** | 周历选日期 → 按餐段（早餐/午餐/晚餐/加餐）查看当天的安排与记录，卡片展示热量 + 三大营养素，可标记"已吃"、调份量、删除；顶部有全天合计 |
| 中 | **＋** | 记录饮食：选日期、餐段，从「食材」或「组合餐」里挑选、调份数后加入；可连续添加多条 |
| 右 | **食材库** | 管理你的常用食材（健身人群常吃的就那几十种），以及由多个食材组成的「组合餐」 |

## 数据维度（重点）

三个层级，从基础到上层，互不混淆：

1. **食材 `Food`**（基础单位）
   - 名字、图标、三大营养素（蛋白质/碳水/脂肪，按 **每 100g** 记录）
   - 热量按 4/4/9 千卡自动估算，不用手填
   - **一份的克数** `servingGrams`：标准食材默认 100g；固定包装商品可把整包设为一份（例如 360g/盒、一根 60g 的蛋白棒）
2. **组合餐 `MealTemplate`**（一餐 = 多个食材按"份"组合）
   - 例如「鸡胸肉能量碗」= 鸡胸肉 1.5 份 + 米饭 1 份 + 西兰花 1 份 + 橄榄油 1 份
   - 自动算出整餐合计营养，可一键作为一条记录加入某天某餐
3. **饮食记录 `DiaryEntry`**（某天、某餐段的一条条目）
   - 引用一个食材或一个组合餐 × 份数；未来日期 = 计划，勾"已吃" = 完成记录

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

数据以 JSON 存在本地（`shared_preferences`），无需数据库与网络权限；删除应用即清空。首次启动自动写入示例数据（含今天的示例记录，可直接删改）。

## 后续可扩展

- 每日热量/三大营养素目标与完成度环形图
- 体重记录与趋势
- 数据导出/备份（CSV / 云同步）
- 食材条码扫描、自定义分类标签
- 饮水记录
