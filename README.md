# MoonBit Roaring

MoonBit Roaring 是用 MoonBit 编写的压缩整数集合库。它按高 16 位分块，用数组、位图或连续区间存储数据，供搜索过滤、权限集合和人群分析使用。

## 项目用途

这些场景经常需要对整数 ID 求交、并、差以及进行排序位置查询。Roaring 按分块选择存储形式，以适应不同的数据分布。

## 安装与使用

在 MoonBit 项目中添加已发布的库：

```sh
moon add cauchyQ/moonbit-roaring@0.3.0
```

在 `moon.pkg` 中导入 `"cauchyQ/moonbit-roaring" @roaring`：

```moonbit
let left = @roaring.RoaringBitmap::from_array([1, 2, 3, 70_000]).unwrap()
let right = @roaring.RoaringBitmap::from_array([2, 3, 80_000]).unwrap()
assert_eq(left.intersection(right).to_array(), [2, 3])
```

运行检查和示例：

```text
moon check --deny-warn
moon test --deny-warn
moon bench --release --deny-warn
moon run cmd/main
moon run cmd/scenarios
```

场景示例检查搜索交集、继承权限与拒绝规则、人群交集、高位 ID、错误基线拒绝和 portable 快照恢复。示例还生成 10,000 个稀疏 ID，删除 100 个并验证补丁及快照恢复；预期剩余 9,900 个 ID。

## 接口与边界

- `RoaringBitmap` 的 `from_range`、`add_range`、`remove_range` 使用半开区间。单次构造或添加超过 1,000,000 个元素会返回错误；删除范围没有这一限制。`to_ranges` 会拒绝无法表示的最大 `Int` 后继端点。
- `add_all`、`remove_all` 先校验完整批次；`from_ranges`、`add_ranges`、`remove_ranges` 接受区间批次并处理重叠。
- `cursor().next()` 按升序逐容器读取；`RoaringBuilder` 暂存值、批次和有界范围，在 `finish` 时统一构建。`union_all`、`intersection_all` 和 `xor_all` 支持多位图运算。
- `encode_words`／`decode_words` 是本库带版本的整数词格式；`encode_run_words`／`decode_run_words` 面向连续区间，解码最多展开 1,000,000 个元素。这两种格式不是 CRoaring 二进制格式。
- 交、并、差和异或先按高位块归并；点查询、极值、`rank`、`select` 和范围导航在块或容器层处理。`stats`、`block_stats` 提供只读统计。
- `diff_to` 可生成包含新增和删除集合的不可变 `RoaringPatch`，支持应用、反转和检查变更值。

## 日志与回放：0.2.0 修复说明

`RoaringOperationLog` 以检查点和有序操作记录表示集合历史。追加操作时会复制
`AddAll`、`RemoveAll` 的整数数组；`operations()` 和 `operation_at()` 也返回
独立副本。修改调用方数组或读取接口返回的数组，不会改变原日志、其编码或派生分支。

日志允许保存尚未执行的操作。`replay()` 按顺序执行，遇到非法操作就返回错误，
不会把部分执行结果当作完整结果。历史接口遵守同样的规则：

- `replay_prefix(count)` 只执行指定前缀；有效前缀可以成功，前缀中的操作失败则返回错误。
- `split_at(count)` 先回放前缀，成功后才建立后缀检查点；失败前缀不能被回退成旧检查点。
- `cardinality_history()` 返回 `Result[Array[Int], JournalRangeError]`，遇到失败立即停止。
- `OperationFailed(index, cause)` 保留相对于当前日志的零基操作位置及原始 `RoaringError`；
  请求位置越界时仍返回 `InvalidIndex`。

例如 `[Add(1), Add(-1), Add(2)]` 的前两项回放和 `split_at(2)` 都应失败。
只回放第一项可以成功；此时拆出的后缀仍包含失败操作，不能成功完整回放。
失败操作不会改变原日志和检查点。

**从 0.1.0 迁移：** `cardinality_history()` 原先直接返回数组，现在需要处理 `Ok` / `Err`。
对于已知有效的测试数据，可使用 `log.cardinality_history().unwrap()`；业务代码应处理
`OperationFailed`。如果对 `JournalRangeError` 做穷尽匹配，也需要补上新增的错误分支。
日志整数词编码的版本和标签没有改变，本次未引入新的编码格式。

`journal_regression_test.mbt` 覆盖输入与输出数组隔离、分支和拆分隔离、失败位置、
非法批次、无效前缀、历史统计和编码往返。全部测试在普通及 Release 模式下运行。
CI 固定编译器 `v0.10.19+bee578715`。

测试包括边界检查和确定性的 64 组性质用例，覆盖交换律、幂等性、抵消及编码往返。`roaring_bench.mbt` 提供可复现的稠密块基准；结果反映本机和工具链，不能视作跨机器性能承诺。

## 互操作与项目来源

原有 `RoaringBitmap` 的 portable 适配器使用 [`xcc-ordinary/moonbit-roaring` 0.1.0](https://github.com/xcc-ordinary/moonbit-roaring)（Apache-2.0）。该适配器只接受非负 `Int` 范围，转换时会展开元素；`portable_test.mbt` 包含由 CRoaring 的 Python 绑定生成的固定样本。

安装 `pyroaring==1.2.0` 后运行 `python verify_croaring.py`，可用 CRoaring 读取 MoonBit 输出；反向测试使用 CRoaring 生成的样本。

`UInt32Bitmap` 提供无符号接口，使用四个分区和 UInt64 基数；支持半开 UInt64 区间，终点可为 `2^32`。portable 编码按容器处理，转换缓冲区最多容纳一个 65,536 元素的容器；已有 1,000,001 个元素的往返测试。完整 `2^32` 集合尚未完成压力测试，无符号接口尚未提供日志功能。

`UInt32Snapshot` 使用数据集名称、版本和 SHA-256 内容摘要校验补丁。`UInt32SnapshotPatch::serialize` 输出版本化的 `URP1` 格式，包含新增和删除位图；`decode_uint32_patch` 验证帧结构和数据集。格式说明见 [PATCH_FORMAT.md](PATCH_FORMAT.md)。

运行 `moon bench --release --deny-warn` 可对比全量与增量更新（包括摘要成本）；结果见 [BENCHMARKS.md](BENCHMARKS.md)，同类库对照见 [COMPARISON.md](COMPARISON.md)。

本项目参考 Roaring Bitmap 和 [CRoaring](https://github.com/RoaringBitmap/CRoaring) 的公开设计，并使用独立生成的 CRoaring 样本验证互操作。CRoaring 采用 Apache-2.0 许可证。

原有接口接受非负 `Int`；`UInt32Bitmap` 支持无符号值。`serialize_portable_compact()` 在有利时输出 Run 容器；`serialize_portable()` 保留无 Run 的规范编码，供 URP1 摘要使用。CI 覆盖 Wasm、Wasm GC 和 JavaScript；Native 后端尚未在 CI 中验证。

## 许可证

Apache-2.0，完整文本见 [LICENSE](LICENSE)。
