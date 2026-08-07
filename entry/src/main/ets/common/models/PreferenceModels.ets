/**
 * PreferenceModels —— VLC 偏好设置数据定义(对齐 androidx Preference 体系)。
 * 通用引擎 PreferencesPage 据此渲染:PreferenceScreen(key→取 screen) → groups → items(逐类型行)。
 * 字段 title/summary/icon 为 Resource/可选;type 决定 PreferenceRow 的渲染分支。
 */

/** 偏好项控件类型(对应 Android preference 子类)。 */
export type PreferenceType =
  | 'toggle'        // CheckBoxPreference / SwitchPreference —— 右侧 Toggle
  | 'list'          // ListPreference —— 点击弹单选,右侧当前值 + 右箭头
  | 'nav'           // PreferenceScreen / Preference —— 跳转下级,右侧右箭头
  | 'numberpicker'  // NumberPickerPreference —— 点击弹数字选择器,右侧右箭头
  | 'seekbar'       // SeekBarPreference —— 行内 Slider
  | 'checkbox'      // 多选/单选项(CheckBox 行内显示) —— 右侧 Checkbox
  | 'multiselect'   // MultiSelectListPreference —— 点击弹多选对话框,右侧右箭头
  | 'text'          // EditTextPreference —— 点击弹文本输入,右侧右箭头
  | 'color'         // ColorPreferenceCompat —— 点击弹颜色选择,右侧色块 + 右箭头
  | 'click'         // 纯点击项(无控件,无右控件),整行可点
  | 'info';         // 仅展示 summary 的不可交互说明条

/** 单条偏好项(对应一个 preference 节点)。 */
export class PreferenceItem {
  /** Settings SharedPreferences key(逐字常量)。 */
  key: string;
  /** 标题文案(Resource 或字面量)。 */
  title: ResourceStr;
  /** 摘要文案(可选)。 */
  summary?: ResourceStr;
  /** 控件类型。 */
  type: PreferenceType;
  /** 默认值(boolean/string/number)。 */
  defaultValue: boolean | string | number;
  /** 单选/多选可选项显示文案(与 entryValues 同序)。 */
  options?: ResourceStr[];
  /** 单选/多选可选项值(与 options 同序)。 */
  optionValues?: string[];
  /** 多选默认选中值集合(entryValues 子集)。 */
  defaultSelected?: string[];
  /** 行首图标(可选)。 */
  icon?: Resource;
  /** seekbar 最小值。 */
  min?: number;
  /** seekbar 最大值。 */
  max?: number;
  /** seekbar 步长。 */
  step?: number;
  /** 依赖开关 key:父开关为 off 时本行 disabled 置灰。 */
  dependency?: string;
  /** 跳转目标子 screen key(nav/click 类型,点击 push 进 PreferencesPage)。 */
  targetScreen?: string;
  /** 直接跳转的外部路由名(如 'ParentalControl')。非空时优先于 targetScreen。 */
  routeName?: string;
  /** 数字选择器最小值(numberpicker)。 */
  numberMin?: number;
  /** 数字选择器最大值(numberpicker)。 */
  numberMax?: number;
  /** 文本输入最大长度(text)。 */
  maxLength?: number;

  constructor(init: PreferenceItemInit) {
    this.key = init.key ?? '';
    this.title = init.title ?? '';
    this.summary = init.summary;
    this.type = init.type ?? 'toggle';
    this.defaultValue = init.defaultValue ?? false;
    this.options = init.options;
    this.optionValues = init.optionValues;
    this.defaultSelected = init.defaultSelected;
    this.icon = init.icon;
    this.min = init.min;
    this.max = init.max;
    this.step = init.step;
    this.dependency = init.dependency;
    this.targetScreen = init.targetScreen;
    this.routeName = init.routeName;
    this.numberMin = init.numberMin;
    this.numberMax = init.numberMax;
    this.maxLength = init.maxLength;
  }
}

/** PreferenceItem 构造初始值(全可选,命名接口以满足 arkts 字面量校验)。 */
export interface PreferenceItemInit {
  key?: string;
  title?: ResourceStr;
  summary?: ResourceStr;
  type?: PreferenceType;
  defaultValue?: boolean | string | number;
  options?: ResourceStr[];
  optionValues?: string[];
  defaultSelected?: string[];
  icon?: Resource;
  min?: number;
  max?: number;
  step?: number;
  dependency?: string;
  targetScreen?: string;
  routeName?: string;
  numberMin?: number;
  numberMax?: number;
  maxLength?: number;
}

/** 偏好分组(对应 PreferenceCategory)。 */
export class PreferenceGroup {
  /** 分组标题。 */
  title: ResourceStr;
  /** 组内偏好项。 */
  items: PreferenceItem[];

  constructor(title: ResourceStr, items: PreferenceItem[]) {
    this.title = title;
    this.items = items;
  }
}

/** 偏好屏(对应一个 R.xml.preferences_xxx → 一个子设置页)。 */
export class PreferenceScreen {
  /** 唯一 key(注册表 key,如 'ui_category' / 'preferences_video')。 */
  key: string;
  /** 页面/ActionBar 标题。 */
  title: ResourceStr;
  /** 分组列表。 */
  groups: PreferenceGroup[];

  constructor(key: string, title: ResourceStr, groups: PreferenceGroup[]) {
    this.key = key;
    this.title = title;
    this.groups = groups;
  }
}

/** 全量偏好项扁平化条目(供偏好搜索页遍历所有 screen 的 items)。 */
export class PreferenceSearchEntry {
  key: string;
  title: ResourceStr;
  summary: ResourceStr;
  /** 所属 screen key(点击跳转目标)。 */
  screenKey: string;
  /** 所属分类文案。 */
  category: ResourceStr;

  constructor(init: PreferenceSearchEntryInit) {
    this.key = init.key ?? '';
    this.title = init.title ?? '';
    this.summary = init.summary ?? '';
    this.screenKey = init.screenKey ?? '';
    this.category = init.category ?? '';
  }
}

/** PreferenceSearchEntry 构造初始值(命名接口)。 */
export interface PreferenceSearchEntryInit {
  key?: string;
  title?: ResourceStr;
  summary?: ResourceStr;
  screenKey?: string;
  category?: ResourceStr;
}
