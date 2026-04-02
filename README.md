# OneKube Offline Installer

这是一个基于 Sealos 的 Kubernetes 离线安装器项目，目标是把 Kubernetes 集群交付收敛成一套可维护、可复用、可在 GitHub Actions 中自动构建的双架构离线包。

## 项目特性

- 同时支持 `amd64` 和 `arm64`
- 支持生成自解压 `.run` 安装包
- 保留原有 `sealos run` 部署方案，不大改安装方式
- 公共变量与公共逻辑已经抽离，后续升级只需要改一处
- 支持在 GitHub Actions 中自动构建并上传离线包产物

## 目录结构

- `common/`
  - `component-versions.env`: 统一维护组件版本和镜像名
  - `build-common.sh`: 公共构建逻辑
  - `install-common.sh`: 公共安装逻辑
- `amd64/`
  - `versions.env`: amd64 架构变量入口
  - `build.sh`: amd64 构建入口
  - `install.sh`: amd64 安装入口，也是 `.run` 包头
- `arm64/`
  - `versions.env`: arm64 架构变量入口
  - `build.sh`: arm64 构建入口
  - `install.sh`: arm64 安装入口，也是 `.run` 包头
- `.github/workflows/`
  - `build-k8s-offline.yml`: GitHub Actions 构建脚本

## 默认版本矩阵

默认版本统一维护在：

```bash
common/component-versions.env
```

当前默认值：

- `Sealos v5.1.1`
- `Kubernetes-Docker v1.31.11`
- `Helm v3.19.2`
- `Cilium 1.18.1`

版本选择原则：

- 优先选择较新的稳定版本
- 同时确认 `registry.cn-shanghai.aliyuncs.com/labring` 中真实存在对应镜像标签
- 不为了“追最新”破坏现有 Sealos 离线部署兼容性

## 维护方式

日常升级版本，主要只改一个文件：

```bash
common/component-versions.env
```

这会同时影响：

- `amd64/versions.env`
- `arm64/versions.env`
- 构建阶段生成的 `image.json`
- `.run` 安装包内部使用的版本元数据

## 本地构建

### 1. 只校验脚本结构并复用现有镜像 tar

适合先验证脚本逻辑：

```bash
cd amd64
chmod +x build.sh install.sh
./build.sh --skip-binary-download --skip-image-prepare
```

### 2. 完整构建离线安装包

适合正式交付：

```bash
cd amd64
chmod +x build.sh install.sh
./build.sh --force
```

构建产物：

- `dist/k8s-sealos-linux-amd64.run`
- `dist/k8s-sealos-linux-amd64.run.sha256`

`arm64` 同理。

## GitHub Actions 构建

项目已经提供：

```bash
.github/workflows/build-k8s-offline.yml
```

工作流能力：

- 在 `push`、`pull_request`、`workflow_dispatch` 时自动构建
- 同时构建 `amd64` 和 `arm64`
- 上传 `.run` 和 `.sha256` 作为 workflow artifact
- 如果是 tag 触发，还会自动创建 GitHub Release 并上传产物

### 推荐发布方式

如果准备正式发版，建议：

```bash
git tag v0.1.0
git push origin v0.1.0
```

这样 GitHub Actions 会直接把双架构产物挂到 Release。

## 安装方式

### 查看默认版本

```bash
./k8s-sealos-linux-amd64.run show-defaults
```

### 安装前检查

```bash
./k8s-sealos-linux-amd64.run precheck \
  --masters 10.0.0.11,10.0.0.12,10.0.0.13 \
  --nodes 10.0.0.21,10.0.0.22 \
  --passwd 'your-password' \
  --yes
```

### 安装集群

```bash
./k8s-sealos-linux-amd64.run install \
  --masters 10.0.0.11,10.0.0.12,10.0.0.13 \
  --nodes 10.0.0.21,10.0.0.22 \
  --passwd 'your-password' \
  --yes
```

### 重置集群

```bash
./k8s-sealos-linux-amd64.run reset \
  --masters 10.0.0.11,10.0.0.12,10.0.0.13 \
  --nodes 10.0.0.21,10.0.0.22 \
  --passwd 'your-password' \
  --yes
```

## 常用参数

- `--data-root`: Sealos 数据目录，默认 `/data`
- `--cri-data`: 运行时数据目录，默认 `/data/containerd`
- `--registry`: 镜像前缀
- `--skip-image-load`: 跳过离线镜像导入
- `--skip-binary-install`: 跳过二进制安装
- `--skip-precheck`: 跳过安装前检查
- `--dry-run`: 只打印最终 sealos 命令，不真正执行
- `--debug`: 打开脚本和 Sealos 调试信息
- `--`: 后续参数直接透传给 `sealos`

示例：

```bash
./k8s-sealos-linux-amd64.run install \
  --masters 10.0.0.11 \
  --passwd 'your-password' \
  --yes \
  -- --single
```

## 安装后的状态文件

安装脚本会写入：

- `/etc/k8s-sealos/cluster.env`

这个文件记录：

- 当前版本矩阵
- Sealos 运行目录
- 数据目录
- 当前 master / node 参数
