# 升级 Opik 上游版本 SOP（fork 定制维护）

本 fork 在上游 Opik 基础上维护两组定制，升级时需保留：

1. **飞书（Feishu）原生告警** — 作为第 4 种告警目的地
2. **阿里云托管 ClickHouse 适配** — `{cluster}` server-macro 参数化为 Liquibase 参数

目标：把每次升级从"现场推理一遍"降为"跑脚本 + 照 checklist"。

---

## 升级步骤

### 1. Rebase 到新版本

```bash
git fetch origin --tags
git worktree add ../opik-<新版本> -b release/<新版本>-feishu <新版本>
cd ../opik-<新版本>
git rebase --onto <新版本> <上一版本tag>
```

`rerere` 已启用（`git config rerere.enabled true`），`.gitignore`、docker registry 等重复冲突会自动套用上次解法。飞书后端/前端锚点通常无冲突（上游告警链路稳定）。

### 2. 参数化上游新增的 ClickHouse migration

```bash
scripts/customize_clickhouse_cluster.sh
```

幂等：把新增 migration 里的 `ON CLUSTER '{cluster}'` → `ON CLUSTER '${ANALYTICS_DB_CLUSTER_NAME}'`。已参数化的文件不受影响。输出 `Residual raw '{cluster}': 0` 即完成。

> 飞书 migration 无需处理——它在 `db-app-state/migrations-custom/` 独立编号空间，永不与上游冲突。

### 3. 验证定制完整性

```bash
# a. ClickHouse 参数化（上游 CI 脚本，已改造为同时接受 {cluster} 和 ${ANALYTICS_DB_CLUSTER_NAME}）
#    注意：脚本用 \s，需 GNU grep（Linux/CI）；macOS 本地会误报，以 CI 结果为准
scripts/check_clickhouse_migrations_cluster.sh

# b. migration 编号无冲突（飞书已脱离，只查上游 migrations/ 目录）
scripts/check_backend_migration_conflicts.sh

# c. 编译即飞书锚点验证：AlertType.FEISHU / AlertPayloadAdapter case / 前端三个 map
#    任何一处丢失都会编译失败
cd apps/opik-backend && mvn -q -DskipTests test-compile && mvn -q -Dtest=FeishuWebhookPayloadMapperTest test
cd ../opik-frontend && npm run build
```

### 4. 构建镜像（fork GitHub Action）

```bash
gh workflow run build_apps.yml -R rusherman/opik --ref release/<新版本>-feishu \
  -f is_release=false -f build_guardrails=true -f build_arm64=false -f is_adhoc=false
```

CI 已修复 comet 变体阻塞（`build_apps.yml` frontend `build_comet_image: false`），run 会整体 success 并产出**完整单一 tag** `<版本>-release-<分支名>-<run号>`（四个镜像都有 tag）。

### 5. 部署（原地升级现有库）

```bash
# 镜像 registry 必须用 ghcr.milu.moe 代理（ghcr.io 从阿里云张家口拉取极慢，会卡 100min+）
REG=ghcr.milu.moe/rusherman/opik; TAG=<上一步的完整tag>
kubectl --context <env> -n opik set image deploy/backend backend=$REG/opik-backend:$TAG
kubectl --context <env> -n opik set image deploy/frontend frontend=$REG/opik-frontend:$TAG
kubectl --context <env> -n opik set image deploy/python-backend python-backend=$REG/opik-python-backend:$TAG

# migration 必须手动跑：backend entrypoint 不跑 migration，set image 也不触发 helm migration hook
kubectl --context <env> exec <backend-pod> -- bash -c 'cd /opt/opik && bash run_db_migrations.sh'

# 验证：state 库 DATABASECHANGELOG 到最新 + 飞书 custom_001 已执行 + analytics 到最新
```

> 生产升级前先备份两库的 `DATABASECHANGELOG`。checksum 对齐依赖已执行的老 migration 内容不变——`customize_clickhouse_cluster.sh` 的参数化对所有版本一致，故 checksum 稳定。

---

## 定制清单（升级时必须存活）

| 定制 | 位置 | 升级维护 |
|---|---|---|
| 飞书后端枚举 | `api/AlertType.java` `FEISHU("feishu")` | 编译保护 |
| 飞书 payload 分发 | `webhooks/slack/AlertPayloadAdapter.java` `case FEISHU` | 穷举 switch，编译保护 |
| 飞书 payload 类 | `webhooks/feishu/*.java`（7 个 + 测试） | 新文件，无冲突 |
| 飞书前端 | `types/alerts.ts` + v1/v2 `helpers.ts`(三 map) + `DestinationSelector.tsx` + `icons/feishu.svg` | 两 map 严格穷举，TS 编译保护 |
| 飞书 DB migration | `db-app-state/migrations-custom/000001_add_feishu_alert_type.sql` | **独立目录，永不重编号** |
| ClickHouse 参数化 | 全 `db-app-analytics/migrations/*.sql` | `customize_clickhouse_cluster.sh` 幂等处理 |
| 迁移 catalog 隔离 | `run_db_migrations.sh` `--catalog` | rebase 保留 |
| 测试容器 cluster 参数 | `ClickHouseContainerUtils.java` | rebase 保留 |
| 部署默认值 | `docker-compose.yaml` / `helm values.yaml` `ANALYTICS_DB_CLUSTER_NAME` | rebase 保留 |
| CI comet 修复 | `build_apps.yml` frontend `build_comet_image: false` | rebase 保留 |
| CI cluster 检查 | `check_clickhouse_migrations_cluster.sh` 接受两种形式 | rebase 保留 |

---

## 彻底消除定制的方向（长期）

- **ClickHouse `{cluster}`**：若阿里云托管 ClickHouse 能配置自定义 macro（`<macros><cluster>实际集群名</cluster></macros>`），则整组参数化定制可删除，直接用上游 `{cluster}`。值得向阿里云工单确认。
- **上游 PR**：飞书告警 + ClickHouse cluster 参数化都是通用需求，合并进上游后对应 diff 消失。
