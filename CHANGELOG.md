# 更新记录

## 0.2.0

- 修复操作日志共享 `AddAll`、`RemoveAll` 输入数组的问题；追加时复制批次内容。
- 修复 `operations()` 和 `operation_at()` 暴露内部批次数组的问题；读取结果与原日志分离。
- 修复 `replay_prefix()` 将失败返回为成功检查点的问题。
- 修复 `split_at()` 在前缀失败后仍用旧检查点建立后缀的问题；保留失败位置与原因。
- `cardinality_history()` 改为返回 `Result[Array[Int], JournalRangeError]`，失败时停止，
  不再重复上一次基数并继续生成统计。这是一项公开 API 变更。
- `JournalRangeError` 新增 `OperationFailed(Int, RoaringError)`，索引为当前日志的零基位置。
- 新增 5 组日志回归测试，覆盖批次所有权、读取与拆分隔离、失败前缀和编码一致性。
- 黑盒测试显式限定被测包名称；固定 CI 工具链，并增加 Release 测试、接口及格式检查。

日志编码版本保持不变。迁移方式和失败语义见 README 的“日志与回放”部分。
