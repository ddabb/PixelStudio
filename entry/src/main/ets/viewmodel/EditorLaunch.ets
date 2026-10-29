/**
 * viewmodel/EditorLaunch.ets — 工程列表 → 编辑器跳转参数（M4 批）。
 * 路由参数静态持有（ArkTS 禁止 router.getParams 后的类型断言，静态类直传最稳）；
 * ProjectListPage 跳转前写入，EditorPage aboutToAppear 一次性读取。
 */

export class EditorLaunch {
  /** true = 新建工程（使用 newWidth/newHeight/projectName）；false = 打开 projectId。 */
  static fresh: boolean = true;
  static projectId: string = '';
  static projectName: string = '';
  static newWidth: number = 64;
  static newHeight: number = 64;

  static openNew(name: string, w: number, h: number): void {
    EditorLaunch.fresh = true;
    EditorLaunch.projectId = '';
    EditorLaunch.projectName = name;
    EditorLaunch.newWidth = w;
    EditorLaunch.newHeight = h;
  }

  static openExisting(id: string): void {
    EditorLaunch.fresh = false;
    EditorLaunch.projectId = id;
  }
}
