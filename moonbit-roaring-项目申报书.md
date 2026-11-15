# MoonBit Roaring：压缩整数集合基础库

**基本信息**

- 参赛者：cauchyQ；联系方式：13009453635
- 项目方向：MoonBit 基础数据结构 / 搜索与分析基础设施
- GitHub：[https://github.com/cauchyQ/moonbit-roaring](https://github.com/cauchyQ/moonbit-roaring)
- Gitlink：[https://gitlink.org.cn/cauchyQ/moonbit-roaring](https://gitlink.org.cn/cauchyQ/moonbit-roaring)
- 项目性质：参考成熟算法思想的独立 MoonBit 实现

**项目简介与生态定位**

MoonBit Roaring 面向“很多整数 ID 的集合运算”这一基础需求：搜索过滤、权限集和分析人群圈选都需要反复计算交、并、差。排序数组处理稠密数据成本高，整块位图又会浪费稀疏数据的空间。本库按 ID 的高 16 位分块，在有序数组、定长位图和连续区间三种容器间选择表示，并提供不可变集合 API。它不是数据库、全文检索服务或 Bloom Filter；目标是让这些上层组件能在 MoonBit 中复用一个可验证的精确集合索引。

**完整使用场景**

1. 搜索服务将标签和关键词映射为文档 ID 集合，取多条件交集得到候选文档，并用 `rank/select` 做稳定分页或抽样。
2. 权限模块保存角色可访问的资源 ID，先合并继承角色，再减去显式拒绝集合，得到最终授权范围。
3. 分析任务把实验分组、时间窗事件分别保存为 ID 集合，通过交并差圈选重叠人群；稳定编码可作为缓存键或跨进程传输内容。

**交付范围与工程边界**

- 提供三类容器、成员查询、基数、`rank/select`、前驱/后继，以及容器级并、交、差、异或；支持安全半开区间、原子批量增删、聚合运算和惰性升序游标。
- 提供规范化构建器、稳定整数词编码和 Run 编码/解码、补丁与快照、操作日志/回放、集合关系分析与查询计划诊断；编码严格校验版本、长度、顺序和物化上限。
- 提供可运行 CLI、GitHub Actions 的检查/测试/Release 构建、基准和覆盖核心代数与边界的测试。当前仓库含 4000 行 MoonBit 源码与 21 个有意义提交。
- 明确不做数据库、网络同步、全文检索、SIMD 优化、CRoaring 二进制格式兼容，也不宣称完整无符号 32 位 API；公开接口仅接受非负 MoonBit `Int`。

**实现路径与参考说明**

集合运算先按高 16 位归并，只对同块容器执行局部运算；位图对位图直接按字运算，其余情况在规范化后选择紧凑容器。范围构造、解码和批处理均先验证输入，再生成新值，避免部分更新和非规范状态。项目参考 Roaring Bitmap/CRoaring 公开的数据结构设计（[CRoaring](https://github.com/RoaringBitmap/CRoaring)，Apache-2.0），但 MoonBit 源码、测试、API、编码格式和示例均独立编写，未复制其源代码、测试数据、二进制格式或 SIMD 实现；本项目采用 Apache-2.0。
