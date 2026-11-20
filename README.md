# tempest-cli-bin

Tempest CLI 的 AUR 二进制包（x86_64 / aarch64），上游发布在
<https://download.gotempest.app>。

## 自动更新

[`.github/workflows/aur-update.yml`](.github/workflows/aur-update.yml)
每 6 小时检查一次上游 APT 仓库，发现新版本后自动：

1. 从上游 `Packages` 索引读取版本号和两个架构的 SHA-256；
2. 更新 `PKGBUILD` 的 `pkgver`、`pkgrel=1` 和 checksum；
3. 在 Arch 容器中重新生成 `.SRCINFO`，并分别构建 x86_64 与 aarch64 包；
4. 提交 `upgpkg: tempest-cli-bin <版本>-1` 到 GitHub，并单独创建一个只含
   根目录文件的 AUR 提交推送到 AUR。

首次运行前需要完成下面的配置。

### 1. 准备 GitHub 仓库

本仓库的 `origin` 指向 GitHub，`aur` 指向 AUR。把仓库放到 GitHub 的默认分支
（本仓库是 `master`）即可；不需要保留 AUR 的提交历史，workflow 会自己 clone
AUR，再生成扁平的 AUR 提交。

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

## AUR 仓库的限制

AUR 的 git hook 不允许仓库出现子目录，所以：

- GitHub 仓库保留 `.github/`、`README.md` 和完整历史；
- 推送到 AUR 的提交只包含 `PKGBUILD`、`.SRCINFO`、`.gitignore`、
  `.nvchecker.toml` 这些根目录文件；
- 不要把 GitHub 的 `master` 直接推到 AUR（会被 hook 拒绝），AUR 由 workflow
  负责推送；
- 本地 `aur` remote 只用于查看 AUR 状态，不要 merge 或 push，因为两边历史是
  独立的。

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

# 推送到 GitHub
git push
```

## 注意

- AUR 只接收 `PKGBUILD`/`.SRCINFO` 等根目录文件，不接收二进制包；workflow
  在 Arch 容器里构建只是为了验证，构建产物不会上传。
- workflow 假定上游 Debian 版本形如 `X.Y.Z-1`，`PKGBUILD` 的 source URL 使用
  `${pkgver}-1`。如果上游改成 `-2` 等修订号，构建校验会失败并阻止推送，需要
  手动调整 URL 规则。
- AUR 主机公钥固定在 workflow 中（ed25519）。如果 AUR 轮换主机密钥，需要同步
  更新 `.github/workflows/aur-update.yml` 里的 `known_hosts`。
