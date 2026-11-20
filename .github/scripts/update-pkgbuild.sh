#!/usr/bin/env bash
# 检查上游 APT 仓库中的 tempest-cli 新版本，并据此更新 PKGBUILD。
#
# - 版本号和两个架构的 SHA-256 均取自上游 Packages 索引，与 .nvchecker.toml 同源。
# - 只在版本确实变新时写文件，可以安全地重复运行。
# - 这里不构建；构建校验由 workflow 在 Arch 容器中完成。
#
# 用法:
#   bash .github/scripts/update-pkgbuild.sh          # 检测并更新
#   bash .github/scripts/update-pkgbuild.sh --check  # 只检测，不写文件
#
# GitHub Actions 输出:
#   updated=true|false
#   pkgver=<更新后或当前的版本>
set -euo pipefail

APT_BASE="${APT_BASE:-https://download.gotempest.app/apt/dists/stable/main}"
UPSTREAM_PKG="${UPSTREAM_PKG:-tempest-cli}"
AUR_PKG="${AUR_PKG:-tempest-cli-bin}"

CHECK_ONLY=false
if [[ "${1:-}" == "--check" ]]; then
    CHECK_ONLY=true
fi

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

emit() {
    local updated="$1" pkgver="$2"
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        {
            printf 'updated=%s\n' "$updated"
            printf 'pkgver=%s\n' "$pkgver"
        } >>"$GITHUB_OUTPUT"
    fi
}

[[ -f PKGBUILD ]] || die "PKGBUILD not found; run this script from the repository root"

current_pkgver="$(sed -n 's/^pkgver=//p' PKGBUILD | head -n1)"
[[ -n "$current_pkgver" ]] || die "cannot read pkgver from PKGBUILD"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

fetch_index() {
    local arch="$1" out="$2"
    curl -fsSL --retry 5 --retry-delay 3 \
        "${APT_BASE}/binary-${arch}/Packages.gz" |
        gzip -dc >"$out"
}

# 从一份 Packages 索引中读出 Version 和 SHA256。
package_info() {
    awk -v pkg="$UPSTREAM_PKG" '
        /^Package: / { in_pkg = ($2 == pkg); next }
        in_pkg && /^Version: / { version = substr($0, 10); next }
        in_pkg && /^SHA256: / { sha = substr($0, 9); next }
        END { print version, sha }
    ' "$1"
}

fetch_index amd64 "$workdir/amd64"
fetch_index arm64 "$workdir/arm64"
read -r debver_amd64 sha256_amd64 <<<"$(package_info "$workdir/amd64")"
read -r debver_arm64 sha256_arm64 <<<"$(package_info "$workdir/arm64")"

[[ -n "$debver_amd64" && -n "$debver_arm64" ]] ||
    die "cannot read ${UPSTREAM_PKG} version from the upstream Packages index"
[[ "$debver_amd64" == "$debver_arm64" ]] ||
    die "upstream version mismatch: amd64=${debver_amd64} arm64=${debver_arm64}"
[[ -n "$sha256_amd64" && -n "$sha256_arm64" ]] ||
    die "cannot read ${UPSTREAM_PKG} SHA256 from the upstream Packages index"
[[ "$sha256_amd64" =~ ^[0-9a-f]{64}$ ]] || die "invalid amd64 SHA256: $sha256_amd64"
[[ "$sha256_arm64" =~ ^[0-9a-f]{64}$ ]] || die "invalid arm64 SHA256: $sha256_arm64"

# Debian 版本形如 3.18.0-1；Arch 的 pkgver 不带末尾的 Debian 修订号。
upstream_pkgver="${debver_amd64%-*}"
[[ "$upstream_pkgver" =~ ^[0-9][0-9A-Za-z._+]*$ ]] ||
    die "unsupported upstream version: $upstream_pkgver"

log "current pkgver:  ${current_pkgver}"
log "upstream pkgver: ${upstream_pkgver}"

if [[ "$upstream_pkgver" == "$current_pkgver" ]]; then
    log "already up to date"
    emit false "$current_pkgver"
    exit 0
fi

# 只接受严格更新的版本，避免上游误发旧版本时把包降级。
newest="$(printf '%s\n%s\n' "$current_pkgver" "$upstream_pkgver" | sort -V | tail -n1)"
if [[ "$newest" != "$upstream_pkgver" ]]; then
    log "upstream ${upstream_pkgver} is not newer than ${current_pkgver}; skipping"
    emit false "$current_pkgver"
    exit 0
fi

if [[ "$CHECK_ONLY" == true ]]; then
    log "update available: ${current_pkgver} -> ${upstream_pkgver} (check only, nothing changed)"
    emit false "$current_pkgver"
    exit 0
fi

# 确保每个字段在 PKGBUILD 中只出现一次，避免误替换。
for key in pkgver pkgrel sha256sums_x86_64 sha256sums_aarch64; do
    count="$(grep -c "^${key}=" PKGBUILD || true)"
    [[ "$count" -eq 1 ]] ||
        die "expected exactly one ${key}= line in PKGBUILD, found ${count}"
done

sed -i -E "s|^pkgver=.*|pkgver=${upstream_pkgver}|" PKGBUILD
sed -i -E "s|^pkgrel=.*|pkgrel=1|" PKGBUILD
sed -i -E "s|^sha256sums_x86_64=.*|sha256sums_x86_64=('${sha256_amd64}')|" PKGBUILD
sed -i -E "s|^sha256sums_aarch64=.*|sha256sums_aarch64=('${sha256_arm64}')|" PKGBUILD

log "updated ${AUR_PKG} to ${upstream_pkgver}-1"
emit true "$upstream_pkgver"
