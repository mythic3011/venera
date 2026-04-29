# venera

> Upstream status: the original repository is no longer maintained by the upstream author.
>
> This fork is maintained by `mythic3011` as a personal side-project fork. Maintenance is best-effort, personal-use first, and not a guaranteed support service.
>
> 上游狀態：原始儲存庫已由上游作者停止維護。
>
> 此 fork 由 `mythic3011` 作為個人 side project 維護。維護屬 best-effort，優先服務本人使用流程，並不提供保證式支援。

[![flutter](https://img.shields.io/badge/flutter-3.41.4-blue)](https://flutter.dev/)
[![License](https://img.shields.io/github/license/mythic3011/venera)](https://github.com/mythic3011/venera/blob/master/LICENSE)
[![stars](https://img.shields.io/github/stars/mythic3011/venera?style=flat)](https://github.com/mythic3011/venera/stargazers)

[![Download](https://img.shields.io/github/v/release/mythic3011/venera)](https://github.com/mythic3011/venera/releases)

A comic reader that support reading local and network comics.

## Features
- Read local comics
- Use javascript to create comic sources
- Read comics from network sources
- Manage favorite comics
- Download comics
- View comments, tags, and other information of comics if the source supports
- Login to comment, rate, and other operations if the source supports

## Build from source
1. Clone the repository
2. Install flutter, see [flutter.dev](https://flutter.dev/docs/get-started/install)
3. Install rust, see [rustup.rs](https://rustup.rs/)
4. Build for your platform: e.g. `flutter build apk`

## Release Channels

Official release channels for this fork are limited to this repository's GitHub Releases unless stated otherwise.

AUR, F-Droid, or other third-party packages may still point to the abandoned upstream project and are not maintained by this fork.

此 fork 的官方 release channel 僅限本 repository 的 GitHub Releases，除非另有說明。

AUR、F-Droid 或其他第三方 package 可能仍指向已停止維護的上游專案，並不由此 fork 維護。

## Contributing

Before opening an issue or pull request, read [Contribution And Issue Policy](CONTRIBUTING.md).

This repository is not a feature request queue. Issues must be actionable and include reproduction steps, logs, affected platform/version, and a concrete proposal where relevant.

Low-effort wishlist issues may be closed without implementation.

開 issue 或 PR 前，請先閱讀 [貢獻與 Issue 政策](CONTRIBUTING.md)。

本 repo 不是許願池。Issue 必須可執行，bug 回報必須包含重現步驟、log、受影響平台/版本；功能建議必須提供具體行為、設計方向與相關風險。

低成本、不可執行的許願式 issue 可能會被直接關閉，不會實作。

## Create a new comic source
See [Comic Source](doc/comic_source.md)

## Thanks

### Tags Translation
[EhTagTranslation](https://github.com/EhTagTranslation/Database)

The Chinese translation of the manga tags is from this project.

## Headless Mode
See [Headless Doc](doc/headless_doc.md)
