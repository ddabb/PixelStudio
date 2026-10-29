/**
 * viewmodel/AppCtx.ets — UIAbilityContext 静态持有（M4 批）。
 * systemShare.ShareController.show 等接口要求精确的 UIAbilityContext 类型，
 * 组件侧 getHostContext() 只返回宽 Context；由 EntryAbility 注入一次，全局读取。
 */

import { common } from '@kit.AbilityKit';

export class AppCtx {
  static uiContext: common.UIAbilityContext | undefined = undefined;
}
