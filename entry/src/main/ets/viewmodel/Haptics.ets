/**
 * viewmodel/Haptics.ets — 触感反馈助手（1.1.0 手感层）。
 * tick = 轻点反馈（落笔/切工具/选档/开关）；confirm = 结果确认反馈（取色/插入）。
 * 模拟器/无马达设备静默降级：同步异常与 Promise 拒绝一律吞掉，绝不影响交互主流程。
 * 权限：ohos.permission.VIBRATE（normal 级 system_grant，无运行时弹窗）。
 */

import { vibrator } from '@kit.SensorServiceKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'Haptics';
const TICK_MS = 12;
const CONFIRM_MS = 25;

export class Haptics {
  /** 轻点反馈：落笔、工具切换、档位选择、面板开关等高频轻量动作。 */
  static tick(): void {
    Haptics.vibrate(TICK_MS);
  }

  /** 确认反馈：吸管取色成功、文本插入等结果性动作。 */
  static confirm(): void {
    Haptics.vibrate(CONFIRM_MS);
  }

  private static vibrate(durationMs: number): void {
    try {
      vibrator.startVibration({
        type: 'time',
        duration: durationMs
      }, {
        usage: 'touch'
      }).catch(() => {
        // 模拟器/无马达设备拒绝属预期，静默降级。
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'vibrate unavailable duration=%{public}d', durationMs);
    }
  }
}
