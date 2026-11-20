# tempest-cli-bin

Tempest CLI 的 AUR 二进制包（x86_64 / aarch64），上游发布在
<https://download.gotempest.app>。

## 自动更新

[`.github/workflows/aur-update.yml`](.github/workflows/aur-update.yml)
每 6 小时检查一次上游 APT 仓库，发现新版本后自动：

1. 从上游 `Packages` 索引读取版本号和两个架构的 SHA-256；
2. 更新 `PKGBUILD` 的 `pkgver`、`pkgrel=1` 和 checksum；
3. 在 Arch 容器中重新生成 `.SRCINFO`，并分别构建 x86_64 与 aarch64 包；
4. 提交 `upgpkg: tempest-cli-bin <版本>-1`，推送到 AUR 和 GitHub 仓库。

首次运行前需要完成下面的配置。

### 1. 在 GitHub 上创建镜像仓库

当前仓库的 `origin` 是 AUR。请把它推送到一个 GitHub 仓库（也可以直接用
GitHub 的 “Import repository” 导入），并确认默认分支是 `master`。
workflow 会运行在 GitHub 仓库里，然后同时推送到 AUR 和 GitHub。

注意：GitHub 仓库必须保留 AUR 的提交历史（即 AUR 的 `master` 是 GitHub
分支的祖先）。不要在一个全新的空仓库里重新初始化，否则第一次推送 AUR 时会
因为 unrelated histories 被拒绝。

### 2. 生成 AUR 专用的 SSH key

不要把日常使用的私钥交给 Actions。生成一把无口令的专用 key：

```bash
ssh-keygen -t ed25519 -C "aur-ci@$(hostname)" -f aur-ci -N ""
```

把 `aur-ci.pub` 的内容添加到 AUR 账户的 SSH Public Key：

<https://aur.archlinux.org/account/>

该 AUR 账户必须对 `tempest-cli-bin` 有推送权限（包维护者或 co-maintainer）。

### 3. 配置 GitHub Secret

在 GitHub 仓库的 **Settings → Secrets and variables → Actions → New repository
secret** 中添加：

| Secret | 内容 |
| --- | --- |
| `AUR_SSH_PRIVATE_KEY` | `aur-ci` 私钥文件的完整内容 |

### 4. 允许 workflow 推送

在 **Settings → Actions → General → Workflow permissions** 中选择
**Read and write permissions**。如果 `master` 开了分支保护，需要允许
GitHub Actions bot 推送，或对 bot 放行。

### 5. 手动跑一次

在 **Actions → Update AUR package → Run workflow** 中手动触发。也可以先用
`dry_run` 勾选运行，只检查并显示 diff，不会提交或推送。

## 本地使用

`.nvchecker.toml` 保留给本地 `nvchecker` 使用；CI 直接读取同一个上游
`Packages` 索引，逻辑等价。

```bash
# 只检查上游是否有新版本
bash .github/scripts/update-pkgbuild.sh --check

# 本地更新 PKGBUILD（不构建、不提交）
bash .github/scripts/update-pkgbuild.sh

# 构建校验（两个架构）
makepkg -f
CARCH=aarch64 makepkg -f

# 手动运行 nvchecker（需要安装 nvchecker）
nvchecker -c .nvchecker.toml
nvtake -c .nvchecker.toml tempest-cli-bin
```

## 注意

- AUR 只托管 `PKGBUILD`/`.SRCINFO`，不接收二进制包；workflow 在 Arch 容器里
  构建只是为了验证，构建产物不会上传。
- workflow 假定上游 Debian 版本形如 `X.Y.Z-1`，`PKGBUILD` 的 source URL 使用
  `${pkgver}-1`。如果上游改成 `-2` 等修订号，构建校验会失败并阻止推送，需要
  手动调整 URL 规则。
- AUR 主机公钥固定在 workflow 中（ed25519）。如果 AUR 轮换主机密钥，需要同步
  更新 `.github/workflows/aur-update.yml` 里的 `known_hosts`。
