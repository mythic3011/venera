# Contribution And Issue Policy / 貢獻與 Issue 政策

## Maintainer Boundary / 維護邊界

This fork is personal-use first and maintained on a best-effort basis.

If the current direction does not fit your needs, you are free to use another project, maintain your own fork, or submit a pull request.

I am not obligated to implement feature requests, support every workflow, or preserve upstream behavior.

此 fork 以本人使用需求優先，採 best-effort 方式維護。

如果目前方向不符合你的需求，你可以選擇使用其他專案、自行維護 fork，或提交 pull request。

我沒有義務實作所有功能請求、支援所有使用流程，或保留上游既有行為。

## Contribution Expectation / 貢獻要求

If you believe something should work differently, provide one of the following:

- a reproducible bug report with logs and steps,
- a concrete implementation proposal,
- or a pull request.

Low-effort complaints, vague wishes, repeated requests, or demands for unpaid work may be closed without further discussion.

如果你認為某個地方應該改，請提供以下其中一項：

- 可重現的 bug 回報，包含 log 與步驟；
- 具體的實作建議；
- 或 pull request。

低成本抱怨、空泛許願、重複催促，或要求他人無償代工的 issue，可能會被直接關閉，不再另行討論。

## Not A Wishlist / 這裡不是許願池

This repository is not a wishlist or free implementation queue.

Low-effort requests may be closed without implementation.

Examples of low-effort requests:

- "Please add this source"
- "Add this button"
- "Make the UI better"
- "Support this website"
- "It does not work" without reproduction steps, logs, or screenshots
- Requests that only describe what you want, but not how it should work

本 repo 不是許願池，也不是免費代工隊列。

低成本、不可執行的請求可能會被直接關閉，不會實作。

低成本請求例子：

- 「請加這個漫畫源」
- 「請加這個按鈕」
- 「介面改好看一點」
- 「支援這個網站」
- 只說「不能用」，但沒有重現步驟、log、截圖
- 只描述想要甚麼，沒有說明應如何運作、影響甚麼、風險在哪

## Bug Reports / Bug 回報

A valid bug report must include:

- current behavior
- expected behavior
- reproduction steps
- platform and app version / commit
- logs, screenshots, or diagnostics
- whether it affects local comics, remote sources, downloads, reader, import, or settings

有效的 bug 回報必須包含：

- 目前行為
- 預期行為
- 重現步驟
- 平台與 app 版本 / commit
- log、截圖或 diagnostics
- 影響範圍：本地漫畫、遠端漫畫源、下載、閱讀器、匯入、設定等

Reports without enough information may be closed as not reproducible.

資料不足的回報可能會被標記為無法重現並關閉。

## Feature Proposals / 功能建議

Feature proposals must explain:

- the user problem
- why current behavior is insufficient
- proposed behavior
- possible implementation direction
- affected files/components if known
- edge cases and risks
- whether you are willing to implement or test it

功能建議必須說明：

- 要解決的使用者問題
- 為何現有功能不足
- 建議的具體行為
- 可能的實作方向
- 可能影響的檔案或元件
- 邊界情況與風險
- 你是否願意實作或協助測試

Requests without a concrete design may be deferred or closed.

沒有具體設計的請求可能會被延後或關閉。

## Pull Requests / PR

Pull requests should be small and reviewable.

A PR should include:

- clear scope
- linked issue or rationale
- test plan
- screenshots for UI changes
- migration notes for schema/storage changes
- security notes if touching network, cookies, account state, logs, or source runtime

PR 應保持小而可 review。

PR 應包含：

- 清楚範圍
- 關聯 issue 或修改原因
- 測試計劃
- UI 修改截圖
- schema / storage 修改的 migration 說明
- 若涉及 network、cookies、帳號狀態、logs、source runtime，必須提供安全性說明

Large or unfocused PRs may be rejected even if the idea is acceptable.

即使方向合理，過大或範圍不清的 PR 仍可能被拒絕。

## Architecture Direction / 架構方向

This fork is moving toward clearer ownership boundaries for routing, feature
contracts, storage authority, and diagnostics.

Contributions should prefer these directions:

- UI pages express user intent, but should not become long-term owners of
  shared route construction, feature contracts, or cross-feature models
- feature modules should own request/model contracts that cross page boundaries
- storage-backed changes should identify canonical authority, fallback, cache,
  preference, or diagnostic-only state before adding new reads or writes
- diagnostics should add decision-useful evidence, not only more event volume

If a change introduces a new cross-feature model, route helper, or storage read
path, explain why that ownership belongs in that layer.

If ownership is unclear, prefer an inventory, design note, or narrow refactor
plan first instead of expanding the ambiguity in code.

此 fork 正朝向更清晰的 routing、feature contract、storage authority、
diagnostics ownership boundary。

提交修改時，請優先符合以下方向：

- UI page 應表達 user intent，但不應長期擁有共享 route construction、
  feature contract 或跨 feature model
- 只要 request/model 會跨 page 邊界，就應由 feature module 擁有
- 涉及 storage 的修改，新增 read/write 前應先標明它是 canonical
  authority、fallback、cache、preference，還是 diagnostic-only state
- diagnostics 應提供可幫助決策的證據，而不只是增加 event 數量

如果變更引入新的跨 feature model、route helper 或 storage read path，
請說明該 ownership 為何屬於該層。

如果 ownership 仍不清晰，請先做 inventory、design note，或小型 refactor
plan，而不是直接把模糊邊界擴散到程式碼內。
