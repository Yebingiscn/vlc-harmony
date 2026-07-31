/** 提交串流地址时的最小交互规则：空地址不反馈，其他地址暂不支持。 */
export function streamSubmissionMessage(uri: string): string {
  return uri.trim().length === 0 ? '' : '暂不支持';
}
