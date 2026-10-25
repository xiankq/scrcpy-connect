# 本地任务

任务保存在 `.scratch/<feature>/`：规格为spec.md，实施项为issues/NN-slug.md。编号从01起，在对应feature内解析；“发布/获取ticket”就是写入/读取该文件。

工单顶部Status使用[分诊角色](triage-labels.md)，讨论写在Comments。

Wayfinder使用map.md记录Notes、Decisions-so-far、Fog。子任务Type为research/prototype/grilling/task；Blocked by列依赖编号，依赖均resolved后可领取。按编号选首个未阻塞且未领取项，领取写claimed，完成写resolved并附Answer，在map中链接结论。这两个状态与分诊角色分开。
