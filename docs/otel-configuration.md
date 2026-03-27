# Opik OpenTelemetry 配置指南

## 架构概览

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐
│   Frontend   │     │  Java Backend    │     │ Python Backend   │
│   (Nginx)    │     │  (Dropwizard)    │     │  (Gunicorn)      │
│              │     │                  │     │                  │
│  ngx_otel    │     │  OTel JavaAgent  │     │ opentelemetry-   │
│  module      │     │  + Extension     │     │ instrument       │
└──────┬───────┘     └────────┬─────────┘     └────────┬─────────┘
       │ gRPC:4317            │ HTTP:4318              │ HTTP:4318
       └──────────────┬───────┴────────────────────────┘
                      ▼
            ┌──────────────────┐
            │  OTel Collector  │
            │  (contrib)       │
            │  0.139.0         │
            └────────┬─────────┘
                     │
          ┌──────────┼──────────┐
          ▼          ▼          ▼
     SLS Traces  SLS Metrics  SLS Logs
```

## 1. 开启 OTel 的前提条件

以下三个条件**全部满足**时，OTel 才会生效：

| 条件 | 环境变量 | 示例值 |
|------|---------|--------|
| 功能开关 | `OPIK_OTEL_SDK_ENABLED` | `true` |
| Agent 版本 | `OTEL_VERSION` | `2.16.0` |
| Collector 地址 | `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://otel-collector:4318` |

任一条件不满足，entrypoint.sh 会跳过 Agent 加载，日志输出 `Skipping download of the Open Telemetry Java Agent`。

## 2. OTel Collector 部署

### 镜像

```
docker.1ms.run/otel/opentelemetry-collector-contrib:0.139.0
```

> 必须使用 `contrib` 版本，因为依赖 `alibabacloud_logservice` exporter。

### K8s 资源

| 资源 | 名称 | 用途 |
|------|------|------|
| Deployment | `otel-collector` | Collector 实例 |
| Service | `otel-collector` | 暴露 gRPC(4317) 和 HTTP(4318) 端口 |
| ConfigMap | `otel-collector-config` | Collector pipeline 配置 |
| Secret | `otel-sls-credentials` | 阿里云 SLS 认证信息 |

### Service 端口

| 端口 | 协议 | 用途 |
|------|------|------|
| 4317 | gRPC | Frontend (Nginx) 使用 |
| 4318 | HTTP | Java Backend / Python Backend 使用 |

### Collector 配置 (ConfigMap)

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: "0.0.0.0:4317"
      http:
        endpoint: "0.0.0.0:4318"

exporters:
  debug:
    verbosity: detailed

  alibabacloud_logservice/sls-trace:
    endpoint: "${SLS_ENDPOINT}"
    project: "${SLS_PROJECT}"
    logstore: "${SLS_LOGSTORE_TRACES}"
    access_key_id: "${SLS_ACCESS_KEY_ID}"
    access_key_secret: "${SLS_ACCESS_KEY_SECRET}"

  alibabacloud_logservice/sls-metric:
    endpoint: "${SLS_ENDPOINT}"
    project: "${SLS_PROJECT}"
    logstore: "${SLS_LOGSTORE_METRICS}"
    access_key_id: "${SLS_ACCESS_KEY_ID}"
    access_key_secret: "${SLS_ACCESS_KEY_SECRET}"

  alibabacloud_logservice/sls-log:
    endpoint: "${SLS_ENDPOINT}"
    project: "${SLS_PROJECT}"
    logstore: "${SLS_LOGSTORE_LOGS}"
    access_key_id: "${SLS_ACCESS_KEY_ID}"
    access_key_secret: "${SLS_ACCESS_KEY_SECRET}"

processors:
  batch:
    timeout: 5s
    send_batch_size: 1024

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [debug, alibabacloud_logservice/sls-trace]
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [debug, alibabacloud_logservice/sls-metric]
    logs:
      receivers: [otlp]
      processors: [batch]
      exporters: [debug, alibabacloud_logservice/sls-log]
```

> **注意**：`debug` exporter 用于排查阶段，会在 collector 日志中输出所有收到的数据。生产环境稳定后建议从 exporters 列表中移除以减少日志量。

### SLS Secret 配置

Secret `otel-sls-credentials` 包含以下 key：

| Key | 说明 |
|-----|------|
| `SLS_ENDPOINT` | SLS 接入点，如 `cn-zhangjiakou.log.aliyuncs.com` |
| `SLS_PROJECT` | SLS Project 名称 |
| `SLS_LOGSTORE_TRACES` | Trace 数据的 Logstore |
| `SLS_LOGSTORE_METRICS` | Metrics 数据的 Logstore |
| `SLS_LOGSTORE_LOGS` | Logs 数据的 Logstore |
| `SLS_ACCESS_KEY_ID` | 阿里云 AccessKey ID |
| `SLS_ACCESS_KEY_SECRET` | 阿里云 AccessKey Secret |

## 3. Java Backend 配置

### 环境变量

| 环境变量 | 值 | 说明 |
|---------|------|------|
| `OPIK_OTEL_SDK_ENABLED` | `true` | 开启 OTel Agent |
| `OTEL_VERSION` | `2.16.0` | OTel Java Agent 版本 |
| `OTEL_SERVICE_NAME` | `opik-backend` | 服务名称，用于 SLS 中筛选 |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://otel-collector:4318` | Collector HTTP 端口 |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `http/protobuf` | **必须设置**，与 4318 端口匹配 |
| `OTEL_PROPAGATORS` | `tracecontext,baggage,b3` | 上下文传播协议 |
| `OTEL_EXPERIMENTAL_EXPORTER_OTLP_RETRY_ENABLED` | `true` | 启用导出重试 |
| `OTEL_EXPERIMENTAL_RESOURCE_DISABLED_KEYS` | `process.command_args` | 隐藏进程启动参数（含敏感信息） |
| `OTEL_EXPORTER_OTLP_METRICS_DEFAULT_HISTOGRAM_AGGREGATION` | `BASE2_EXPONENTIAL_BUCKET_HISTOGRAM` | Histogram 聚合方式 |
| `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE` | `delta` | Metrics 时间性偏好 |
| `OTEL_JAVAAGENT_DOWNLOAD_URL` | Maven Central URL | Agent JAR 下载地址（国内需用此地址） |
| `OTEL_JAVAAGENT_DEBUG` | `false` | Agent 调试日志，排查时可设为 `true` |

### 启动流程 (entrypoint.sh)

1. 检查 `OPIK_OTEL_SDK_ENABLED=true` 且 `OTEL_VERSION` 和 `OTEL_EXPORTER_OTLP_ENDPOINT` 非空
2. 从 `OTEL_JAVAAGENT_DOWNLOAD_URL` 下载 Agent JAR 到 `/tmp/opentelemetry-javaagent.jar`
3. 如果 `/opt/opik/opik-telemetry-extension.jar` 存在，作为 Agent 扩展加载
4. 通过 `-javaagent` 参数启动 Java 进程

### Telemetry Extension

打包在镜像内的 `opik-telemetry-extension.jar` 提供：
- Workspace 维度的 metric view（所有 instrument 类型均包含 workspace 属性）
- 自定义 histogram bucket 边界（通过 `OTEL_BUCKET_HISTOGRAM_BOUNDARIES` 配置）
- HTTP 请求时长 metric 的毫秒到秒单位转换

### 自动采集的 Span 类型

OTel Java Agent 自动 instrument 以下组件，无需代码改动：

| 组件 | Span 类型 | 关键属性 |
|------|----------|---------|
| Jetty HTTP Server | SERVER | `http.route`, `url.path`, `http.request.method`, `http.response.status_code` |
| MySQL (JDBC) | CLIENT | `db.system=mysql`, `db.statement`, `db.name` |
| ClickHouse | CLIENT | `db.system=clickhouse`, `db.statement`, `db.name` |
| Redis (Redisson) | CLIENT | `db.system=redis`, `db.statement`, `db.operation` |
| Apache HttpClient | CLIENT | `url.full`, `http.request.method`, `http.response.status_code` |
| Quartz Scheduler | INTERNAL | `thread.name` |

### 关键注意事项

> **`OTEL_EXPORTER_OTLP_PROTOCOL` 必须设置为 `http/protobuf`**
>
> OTel Java Agent 默认使用 gRPC 协议。如果 `OTEL_EXPORTER_OTLP_ENDPOINT` 指向 HTTP 端口 4318，
> 但不设置此变量，Agent 会用 gRPC 协议发送到 HTTP 端口，导致 **trace 导出静默失败**，
> 不会报错，但 SLS 中看不到任何 trace 数据。

> **国内环境必须设置 `OTEL_JAVAAGENT_DOWNLOAD_URL`**
>
> 默认从 GitHub Releases 下载 Agent JAR（约 22MB），国内网络不可达。
> 推荐使用 Maven Central：
> ```
> https://repo1.maven.org/maven2/io/opentelemetry/javaagent/opentelemetry-javaagent/${OTEL_VERSION}/opentelemetry-javaagent-${OTEL_VERSION}.jar
> ```

## 4. Python Backend 配置

### 环境变量

| 环境变量 | 值 | 说明 |
|---------|------|------|
| `OPIK_OTEL_SDK_ENABLED` | `true` | 开启 OTel instrumentation |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://otel-collector:4318` | Collector HTTP 端口 |
| `OTEL_VERSION` | `2.16.0` | 标记版本（供日志参考） |

### 启动流程 (entrypoint.sh)

当 `OPIK_OTEL_SDK_ENABLED=true` 时：
1. 设置 `OTEL_RESOURCE_ATTRIBUTES="service.name=opik-python-backend,service.version=${OPIK_VERSION}"`
2. 启用 Python 日志自动 instrument：`OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED=true`
3. 启用日志关联：`OTEL_PYTHON_LOG_CORRELATION=true`
4. 使用 `opentelemetry-instrument` 命令包裹 gunicorn 启动

### 补充配置建议

Python Backend 目前未设置 `OTEL_EXPORTER_OTLP_PROTOCOL`。Python OTel SDK 默认使用 `http/protobuf`，
与 4318 端口兼容，因此目前可正常工作。但建议显式设置以避免未来版本行为变化：

```yaml
OTEL_EXPORTER_OTLP_PROTOCOL: "http/protobuf"
```

## 5. Frontend (Nginx) 配置

### 环境变量

| 环境变量 | 推荐值 | 说明 |
|---------|--------|------|
| `OTEL_TRACE` | `on` | **必须设为 `on`**，见下方重要说明 |
| `OTEL_COLLECTOR_HOST` | `otel-collector` | Collector 地址 |
| `OTEL_COLLECTOR_PORT` | `4317` | 使用 gRPC 端口 |

### 开启方式

将 `OTEL_TRACE` 设为 `on`：

```yaml
OTEL_TRACE: "on"
```

开启后 Nginx 通过 `ngx_otel_module.so` 模块：
- 自动为每个请求生成 trace
- 传播 W3C Trace Context（`otel_trace_context propagate`），trace-flags=01（sampled）
- 在 access log 中注入 `$otel_trace_id`
- 服务名为 `opik-frontend`

### 关键注意事项

> **`OTEL_TRACE` 必须设为 `on`，否则 Backend 的 HTTP 请求 trace 会丢失**
>
> Nginx 的 `ngx_otel_module` 配置中同时包含 `otel_trace` 和 `otel_trace_context propagate`。
> 当 `otel_trace off` 时，Nginx 仍然会通过 `otel_trace_context propagate` 向 Backend 发送
> `traceparent` header，但其中 **trace-flags=00（not sampled）**。
>
> OTel Java Agent 遵守 W3C Trace Context 规范，收到 `trace-flags=00` 后会认为上游已决定不采样，
> 从而 **跳过所有 span 的生成**。这会导致所有通过 Nginx 反向代理的 HTTP 请求在 Backend 中没有任何 trace 数据，
> 而直接访问 Backend 的请求（如 healthcheck、定时任务、直接 curl）则正常。
>
> 症状：SLS 中只能看到 Quartz 定时任务、Redis、ClickHouse 的 span，看不到 HTTP SERVER span。

## 6. 排查指南

### 确认 Agent 是否加载

查看 backend 启动日志：
```bash
kubectl logs -n opik <backend-pod> | grep "otel.javaagent"
```

预期输出：
```
[otel.javaagent ...] INFO io.opentelemetry.javaagent.tooling.VersionLogger - opentelemetry-javaagent - version: 2.16.0
```

如果看到 `Skipping download of the Open Telemetry Java Agent`，检查三个前提条件。

### 确认 Collector 是否收到数据

```bash
kubectl logs -n opik <collector-pod> --since=30s | grep "Traces"
```

预期输出：
```
info Traces {"otelcol.signal": "traces", "resource spans": N, "spans": M}
```

如果无输出，检查 backend 到 collector 的网络连通性：
```bash
kubectl exec -n opik <backend-pod> -- curl -v http://otel-collector:4318/v1/traces -X POST -H "Content-Type: application/x-protobuf" -d ""
```

### 开启 Agent 调试日志

```bash
kubectl set env deployment/backend -n opik OTEL_JAVAAGENT_DEBUG=true
```

查看详细日志：
```bash
kubectl logs -n opik <backend-pod> | grep "otel.javaagent"
```

排查完成后关闭：
```bash
kubectl set env deployment/backend -n opik OTEL_JAVAAGENT_DEBUG=false
```

### 常见问题

| 现象 | 原因 | 解决 |
|------|------|------|
| SLS 中无 trace 数据 | 未设置 `OTEL_EXPORTER_OTLP_PROTOCOL` | 设为 `http/protobuf` |
| Agent JAR 下载超时 | GitHub 不可达 | 设置 `OTEL_JAVAAGENT_DOWNLOAD_URL` 为 Maven Central |
| Collector 启动失败 | SLS 凭证错误 | 检查 Secret `otel-sls-credentials` |
| 只有 metrics 无 traces | 协议不匹配（gRPC 发到 HTTP 端口） | 确认 protocol 与端口匹配 |
| 前端页面操作无 trace，直接 curl 有 | Nginx `OTEL_TRACE=off` 导致 `traceparent` 中 trace-flags=00 | **设 `OTEL_TRACE=on`**（见第 5 节） |
| 只有 Quartz/Redis/DB span，无 HTTP SERVER span | 同上，Nginx 传播了 not-sampled 的 trace context | **设 `OTEL_TRACE=on`**（见第 5 节） |
| 前端请求无 trace | `OTEL_TRACE=off` | 设为 `on` |
