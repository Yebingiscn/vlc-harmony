/** 更多首页只展示最近可见的六条本地媒体，完整内容由历史页承载。 */
export function historyPreview<T>(items: T[], limit: number = 6): T[] {
  return items.slice(0, limit);
}
